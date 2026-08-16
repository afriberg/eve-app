# Backend API — What Exists, What's Missing

This document is the required "read first" audit called for by this project's engineering principles (never invent a backend that doesn't exist; verify before extending). It reflects a direct read of the `eve-os` repository as of 2026-08-16, plus what `eve-os`'s own documentation says Hermes provides. It does **not** reflect a read of Hermes' own source, which is a separate, external system not present in `eve-os`.

## System boundary (source: `eve-os/docs/architecture.md`, `docs/hermes-integration.md`)

```
EVE owns: identity, durable memory, relationships, goals/tasks/decisions,
          episodes, self-administration, retrieval.

Hermes owns: conversation runtime and agent loop, LLM/provider access,
             tool and skill execution, WhatsApp, voice and channels,
             scheduling, external system interaction.
```

`eve-os/docs/reuse-inventory.md` explicitly lists "WhatsApp, Discord or voice runtimes" under **DO NOT PORT** into EVE. This is a deliberate, documented boundary, not an oversight — EVE is a memory/intelligence store, not a conversation server.

## What the EVE API exposes today

Read directly from `eve-os/eve/api/main.py` (FastAPI app, `eve/api/main.py`, 476 lines, no other route files):

| Endpoint | Purpose |
|---|---|
| `GET /health`, `GET /ready` | liveness/readiness, unauthenticated |
| `GET/PUT /v1/identity` | EVE's identity record (name, persona, self-reference policy) |
| `POST /v1/memories`, `GET /v1/memories/{id}`, `.../retract`, `.../correct` | durable memory CRUD |
| `GET/POST /v1/memories/hygiene` | memory hygiene scan/apply |
| `POST /v1/context/retrieve` | hybrid retrieval for a given query — returns a context block, not a conversational answer |
| `POST /v1/conversations/ingest` | accepts one already-completed conversation turn for memory extraction; does not generate a response |
| `POST/GET /v1/intelligence/*` | relationships, goals, tasks, decisions, episodes, stewardship, reflection |
| `POST /v1/intelligence/migrate` | legacy data migration |
| `GET/POST /v1/self-admin/*` | bounded self-maintenance assessments/actions |

**Authentication:** a single static shared secret (`EVE_API_TOKEN`), checked as `Authorization: Bearer <token>` with `hmac.compare_digest`. One token for the whole deployment — there is no concept of a device, a session, or a per-caller identity anywhere in this API. A separate, narrower `X-EVE-Owner-Approval` header (verified against a SHA-256 digest, `EVE_OWNER_APPROVAL_TOKEN_SHA256`) gates a small set of high-risk mutations (identity changes, self-admin approval, data migration). This pattern — owner presents a raw secret once, server only ever stores/compares a digest — is the closest existing precedent for a pairing flow (see `docs/security.md`).

**Network exposure:** `eve-os/docs/deployment.md` and `docs/architecture.md` confirm the EVE API is bound to `127.0.0.1:8000` on the Raspberry Pi. Nothing in this deployment is exposed to the internet today; there is no reverse proxy, no TLS termination, no Tailscale/VPN wiring documented in `eve-os`.

**What is absent, in full:** no conversation/chat-completion endpoint, no streaming (no WebSocket, no SSE), no voice/audio endpoint of any kind, no STT/TTS, no session concept, no interruption/barge-in signal, no device registration/pairing, no push notifications. `POST /v1/conversations/ingest` is a write-only memory-extraction sink for a turn that already happened elsewhere — it cannot be used to hold a conversation.

## What Hermes is documented to own, and what we don't know

`eve-os/docs/hermes-integration.md` and `docs/architecture.md` describe Hermes as owning the conversation loop, LLM access, tool execution, and "WhatsApp, voice and channels." `docs/physical-acceptance.md` confirms a Hermes API server exists and is bound to `127.0.0.1:8642` on the production Pi, and a separate WhatsApp bridge process at `127.0.0.1:3000`.

That is the extent of what `eve-os` tells us. Hermes' own source, its API's actual request/response shapes, its voice/STT/TTS implementation (if any exists today beyond WhatsApp voice notes), and whether it has any concept of a non-WhatsApp channel are **not visible from this repository** and were not assumed. `eve-os/docs/reuse-inventory.md` calls WhatsApp/voice "runtimes" — plural, external — reinforcing that Hermes' voice handling, if any, is bespoke to WhatsApp today and not a generic channel API.

## The gap this app depends on

Every numbered item below is backend work. None of it belongs in this repository (`EVE-IOS-APP`); per the project brief, backend changes belong in `eve-os` (or in Hermes, wherever Hermes' source actually lives — outside the scope of what this project has access to).

1. **A conversational entry point for a non-WhatsApp channel.** Something has to accept "here is what the user said" and return "here is what EVE said," running the same identity/memory/tool loop WhatsApp gets today. Whether that's a new Hermes channel adapter, or a small gateway service in front of Hermes, is an open architecture decision — see `docs/architecture.md`.
2. **Session/streaming transport.** A WebSocket (or equivalent) that can carry the event protocol in `docs/voice-architecture.md` (§ Protocol) — partial transcripts, streamed response tokens, streamed TTS audio, interruption signals.
3. **STT.** Either server-side (Architecture A) or client-side via Apple's Speech framework (Architecture B) — see `docs/voice-architecture.md` for the tradeoff. If server-side, this is new Hermes/gateway work; no STT exists in `eve-os` today.
4. **TTS.** No TTS provider is wired up anywhere visible in `eve-os`. The brief calls for an abstracted TTS interface so EVE can have one consistent voice across clients; today there is nothing to abstract over yet.
5. **Per-device authentication.** A pairing flow that mints a revocable device credential, replacing (for this app) the single shared `EVE_API_TOKEN`. The self-administration owner-approval pattern (§ above) is a reasonable template but does not exist for devices today.
6. **Interruption/barge-in signal.** No existing concept of "stop what you were doing, the user is talking again" anywhere in EVE or documented Hermes behavior.
7. **External network exposure design.** Today's deployment is loopback-only by design. Reaching it from outside the home network needs a decision (Tailscale is the brief's suggested v1 default — see `docs/security.md`) and, if any part of the surface is ever exposed beyond the VPN, TLS termination that doesn't exist yet.

Until at least (1)-(3) and (5) exist in some form, this app cannot complete Milestone 1's acceptance criterion ("iPhone → EVE backend works securely") for anything beyond a `/health` connectivity check, and cannot start Milestone 2 (text conversation) at all. This is the single most important open decision blocking implementation — see `docs/roadmap.md`, Milestone 0.
