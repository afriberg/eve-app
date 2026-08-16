# Backend API — What Exists, What's Missing

This document is the required "read first" audit called for by this project's engineering principles (never invent a backend that doesn't exist; verify before extending). It originally reflected only `eve-os`, since Hermes' source wasn't available. **Updated 2026-08-16** after being pointed at [`github.com/nousresearch/hermes-agent`](https://github.com/nousresearch/hermes-agent) and reading it directly — confirmed to be the actual Hermes runtime `eve-os` integrates with (`~/.hermes` paths, `hermes config set memory.provider eve`, WhatsApp gateway, and the exact port `eve-os/docs/physical-acceptance.md` cites for the Hermes API, `127.0.0.1:8642`, all match `gateway/platforms/api_server.py`'s `DEFAULT_PORT = 8642`). This revision replaces the earlier, more pessimistic gap analysis — most of what looked missing turns out to already exist in Hermes.

## System boundary (source: `eve-os/docs/architecture.md`, `docs/hermes-integration.md`)

```
EVE owns: identity, durable memory, relationships, goals/tasks/decisions,
          episodes, self-administration, retrieval.

Hermes owns: conversation runtime and agent loop, LLM/provider access,
             tool and skill execution, WhatsApp, voice and channels,
             scheduling, external system interaction.
```

`eve-os/docs/reuse-inventory.md` explicitly lists "WhatsApp, Discord or voice runtimes" under **DO NOT PORT** into EVE. This boundary still holds after reading Hermes' source: EVE is a memory/intelligence store, Hermes is where conversation, voice, and channels actually live.

## What the EVE API exposes today (`eve-os`)

Unchanged from the original audit — read directly from `eve-os/eve/api/main.py` (FastAPI app, 476 lines, no other route files): identity, memory CRUD, hygiene, retrieval, intelligence (relationships/goals/tasks/decisions/episodes/stewardship/reflection), migration, self-admin. Authenticated by one static shared secret (`EVE_API_TOKEN`, `Authorization: Bearer`), with a narrower digest-verified `X-EVE-Owner-Approval` header gating high-risk mutations. Bound to `127.0.0.1:8000`. No conversation, streaming, voice, or device-auth concept anywhere in it. `POST /v1/conversations/ingest` is a write-only memory-extraction sink for a turn that happened elsewhere — not a chat endpoint. This part of the picture hasn't changed.

## What Hermes actually exposes (`nousresearch/hermes-agent`)

This is the corrected part. Hermes ships a full OpenAI-compatible API server (`gateway/platforms/api_server.py`, 7,600+ lines, `DEFAULT_HOST=127.0.0.1`, `DEFAULT_PORT=8642`, overridable via `API_SERVER_HOST`/`API_SERVER_PORT` — matching exactly what `eve-os/docs/physical-acceptance.md` and `docs/deployment.md` say about keeping it host-local):

| Endpoint | Purpose |
|---|---|
| `POST /v1/chat/completions` | OpenAI Chat Completions format; stateless by default, opt-in session continuity via `X-Hermes-Session-Id` |
| `POST /v1/responses` | OpenAI Responses API format; stateful via `previous_response_id` |
| `GET/POST /api/sessions`, `GET/PATCH/DELETE /api/sessions/{id}` | list/create/read/update/delete a persisted Hermes session |
| `GET /api/sessions/{id}/messages` | session message history |
| `POST /api/sessions/{id}/fork` | branch a session |
| `POST /api/sessions/{id}/chat` and `.../chat/stream` | **chat with a persisted session — the actual conversation endpoint**, with a streaming variant |
| `POST /v1/runs` → `GET /v1/runs/{id}` | start a run (returns `run_id` immediately, 202), poll status |
| `GET /v1/runs/{id}/events` | **SSE stream of structured lifecycle events** |
| `POST /v1/runs/{id}/stop` | **interrupt a running agent** |
| `POST /v1/runs/{id}/steer` | **inject guidance into a running agent mid-turn** — closer to true barge-in than a simple stop |
| `POST /v1/runs/{id}/approval` | resolve a pending run approval |
| `GET /v1/capabilities` | machine-readable capability discovery, explicitly documented as "for external UIs" |
| `GET /health`, `GET /health/detailed` | liveness/readiness |

**Authentication:** `API_SERVER_KEY` — again a single static shared secret, the same weakness `EVE_API_TOKEN` has. However, Hermes' own desktop app (`apps/desktop`, an Electron app — see below) authenticates its WebSocket connections via a `GatewayAuthMode` of either `'token'` (the static key) or `'oauth'`, where OAuth mode **mints a fresh, single-use WebSocket ticket per connection** (`apps/shared/src/websocket-url.ts`, `resolveGatewayWsUrl`). The identity model behind that OAuth mode is Nous account auth and isn't directly reusable for a household device, but the *mechanism* — mint a short-lived, single-use credential right before opening a connection, rather than embedding a long-lived static key in the client — is a real, production precedent worth mirroring in the EVE Voice Gateway's own device-credential design (`docs/security.md`).

**Pairing precedent, not a device system:** `gateway/pairing.py` is a full DM-pairing implementation — 8-char cryptographically random codes, salted-hash storage (codes are never stored in plaintext), 1-hour expiry, rate limiting, lockout after 5 failed attempts, owner-approval via CLI, per-platform revocation. It's real and well-built, but it authorizes *messaging-platform user IDs* (a Telegram/Discord/WhatsApp user talking to the bot) against a platform allowlist — it has no concept of "a specific iPhone" as a principal. It is not something the Gateway can call directly; it's a validated design pattern to structurally mirror for a new, Gateway-owned device-credential store, not a shared dependency.

## TTS and STT already exist and are already abstracted

This directly contradicts the original audit's biggest claimed gap. Hermes has:

- **`agent/tts_registry.py`** + `tools/tts_tool.py` — pluggable TTS behind one interface, built-in providers `edge` (free, no key), `openai`, `elevenlabs`, `minimax`, `gemini`, `mistral`, `xai`, `piper`, `kittentts`, `neutts` (local, free), plus a plugin extension point.
- **`agent/transcription_registry.py`** + `tools/transcription_tools.py` — pluggable STT, built-in providers `local` (faster-whisper, free, no key), `local_command`, `groq`, `openai`, `mistral`, `xai`, `elevenlabs`, `deepinfra`. Provider fallback order: local → groq → openai.

Both are already live in production across every existing Hermes channel: WhatsApp voice notes, Telegram/Discord voice replies, Discord voice-channel conversations, and CLI/TUI/desktop voice mode (`website/docs/user-guide/features/voice-mode.md`). Full barge-in is already implemented there too — VAD-based interruption, a configurable "stop" stop-phrase, mid-generation interrupt, and the agent is told in its next turn that it was cut off. None of this needs to be built from scratch; the question for the EVE Voice Gateway is which of these already-working pieces to call, not whether they exist.

## The real-time voice protocol already has a working reference implementation

Hermes' Electron desktop app (`apps/desktop`) implements exactly the kind of low-latency streaming voice UX this project wants, over a concrete WebSocket protocol:

- **`/api/audio/speak-stream`** (`apps/desktop/src/lib/voice-playback.ts`) — one WebSocket per reply. Client sends `{"text": "..."}` frames as LLM response deltas arrive and `{"done": true}` when generation finishes. Server responds with a `{"type":"start","sample_rate":24000}` control frame, then raw binary 16-bit PCM audio frames streamed as they're synthesized (sentence-by-sentence, so speech starts before the full reply is generated), then `{"type":"end"}` — or `{"type":"fallback"}` if the provider can't stream and the client should fall back to whole-utterance playback. The client schedules PCM buffers back-to-back via Web Audio for gapless playback. Barge-in is just closing the socket — "the server aborts synthesis on disconnect."
- **`/api/ws`** — the base gateway WebSocket the desktop app authenticates against (token or single-use ticket, see above); `/api/audio/speak-stream` shares its auth.

This is close enough to what `docs/voice-architecture.md` already proposed (a WebSocket carrying JSON control frames plus binary audio) that the right move is to treat it as the reference implementation to adapt for iOS, not a from-scratch design. See `docs/voice-architecture.md` for the updated protocol section.

## What's actually still missing

Much shorter than the original list:

1. **No mobile/generic-voice-client surface.** Hermes' channels are messaging platforms (Telegram, Discord, WhatsApp, ...) or the bespoke desktop app's own WS pair. There's no "a phone, talking to Hermes directly" precedent — that's what the EVE Voice Gateway is for (see `docs/architecture.md`, locked decision #1: a dedicated gateway, not a new Hermes platform adapter, precisely so this app never has to speak Hermes' internal protocol or hold Hermes' shared `API_SERVER_KEY`).
2. **Per-device pairing for a household phone.** Real precedent exists (`gateway/pairing.py`'s code/approval/revocation model, the desktop app's ticket-minting pattern) but nothing that issues a credential to "this specific iPhone" against an EVE owner-approval decision. This is Gateway-owned, new work — see `docs/security.md`.
3. **The Gateway itself.** Per the locked architecture, a small service that: authenticates devices (item 2), holds the one Hermes `API_SERVER_KEY` internally, translates the iOS-facing protocol in `docs/voice-architecture.md` into calls against Hermes' existing `/api/sessions/{id}/chat/stream`, `/api/audio/speak-stream`, `/v1/runs/{id}/stop`/`steer`, and (per the locked decision to keep STT on-device for v1) accepts already-transcribed text from the phone rather than raw audio. This is now a well-scoped adapter/proxy over known, working Hermes endpoints — not an open-ended "build conversation and voice from nothing" project.
4. **TLS/network exposure.** Settled by the locked decision (revised 2026-08-16): the owner's existing WireGuard VPN, with TLS from a private EVE-owned CA layered on top — no Tailscale, no public CA/DNS, no public endpoint for v1 (see `docs/security.md`).

**Decided (2026-08-16): the Gateway lives in `eve-os`**, as a new service alongside the existing EVE API in the Docker Compose stack — not a separate repository. This is a deliberate extension of the currently accepted Raspberry Pi topology (today: Postgres + EVE only, loopback-bound), so `eve-os` is updating its own architecture/roadmap docs before any Gateway implementation starts — see `eve-os/docs/voice-gateway.md`.
