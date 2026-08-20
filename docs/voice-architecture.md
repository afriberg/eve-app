# Voice Architecture

## Implementation status (GW-M3, updated 2026-08-18)

Milestone 3 (push-to-talk) is implemented against the **simpler, non-streaming** transport this document already flagged as the right choice before Milestone 4 exists: it reuses GW-M2's `conversation.message`/`conversation.response` request-response pair rather than the full streaming event catalog below (`transcript.partial`, `tts.audio.chunk`, etc.) — that catalog remains the target for Milestone 4 (streaming), not yet built. Concretely: `SpeechRecognitionService` captures and transcribes on-device (Architecture B, as decided below); `VoiceViewModel` sends the final transcript as a normal `conversation.message`; the Gateway's `conversation.response` now carries an optional `data.audio` field — one complete synthesized WAV utterance as a base64 data URL, not a stream — which `AudioPlaybackService` plays back. Its absence (voice disabled or synthesis failed server-side) is not an error; the turn still completes with just the text. See eve-os `docs/voice-gateway.md`, "GW-M3 — Voice", including why TTS synthesis there ended up local/offline (Piper) rather than proxied through Hermes as the "TTS" section below originally assumed.

## Two candidate architectures

### Architecture A — audio streaming (server-side STT/TTS)

```
Microphone → iPhone → secure audio stream → EVE/Hermes → STT → EVE → TTS → audio stream → iPhone speaker
```

The phone is a dumb audio pipe. All recognition and synthesis happen server-side.

### Architecture B — local/native STT, server-side TTS

```
Microphone → Apple Speech (on-device) → text → EVE API → EVE/Hermes → response → TTS → iPhone
```

The phone transcribes locally and sends text; audio only flows back for the spoken response.

## Comparison

| Dimension | A — audio streaming | B — local STT |
|---|---|---|
| Latency to first token | Extra hop: audio → network → server STT, before the LLM even starts. Best case if server STT is fast and colocated with the LLM. | STT starts the instant speech starts (on-device, no network round trip); text reaches the backend as soon as the user stops talking. Generally lower latency to first LLM token. |
| Privacy | Raw voice audio leaves the device on every turn. | Only transcribed text leaves the device. Meaningfully better for a personal assistant handling private household/infrastructure topics (per `eve-os`'s own domain: home automation, self-hosted infrastructure, family matters). |
| Bandwidth | Continuous audio upstream (compressed, but still real audio). | Small: text upstream, audio only downstream for the answer. Matters on cellular/VPN. |
| Swedish recognition quality | Hermes' server-side STT (`docs/backend-api.md`) is real and pluggable (local faster-whisper, Groq, OpenAI, Mistral, xAI, ElevenLabs, DeepInfra) — quality/language coverage depends on which provider is configured, not on whether STT exists at all. | Depends on Apple's on-device models. Apple's Speech framework has supported Swedish (`sv-SE`) as a recognizer locale for years; iOS 26 additionally ships `SpeechAnalyzer`/`SpeechTranscriber`, a newer on-device model line (WWDC 2025) aimed at long-form, more accurate transcription, replacing `SFSpeechRecognizer` as the default going forward. Exact on-device-vs.-server-required locale support must be verified at implementation time via `SFSpeechRecognizer.supportedLocales()` / the `SpeechTranscriber` locale API on the target OS version — do not assume `sv-SE` support without checking, since Apple's documentation does not publish a stable locale table and it has changed release to release.
| Reliability / offline | Fails completely without network for the whole turn (recognition + reasoning both need the backend). | Transcription can succeed offline; the turn as a whole still needs network for EVE's reasoning, so full offline operation isn't a realistic goal either way — but degraded connectivity fails later in the pipeline (after the user already sees their words recognized), which is a better user experience than silence. |
| Interruption / barge-in | Server needs to be told to stop generating/streaming TTS; the client just stops playback and starts a new audio stream — simple client-side, needs a clear server protocol (see below). | Same server-side requirement, but the client's own STT can also detect the user is speaking again as a *local* signal (voice activity), giving faster barge-in detection than waiting on a server round-trip. |
| Server load | Every household member's every utterance is server-side audio-to-text work. On modest, single-machine self-hosted hardware (the documented production host), this is a real constraint. | STT cost is offloaded to Apple Silicon on the phone; the host only handles reasoning and TTS. |
| Streaming capability | Naturally streams (it's an audio pipe); partial transcripts depend on the server STT supporting streaming. | Apple's on-device recognizers support partial-result callbacks natively and cheaply. |
| Consistency across future clients (Watch, CarPlay, other users) | One STT implementation to maintain and tune. | STT quality/behavior potentially differs per platform's on-device capability (a real concern if a Watch client uses a weaker on-device model, or no on-device model at all). |

## Decision (locked 2026-08-16)

**On-device STT (Architecture B) as the primary track for v1, with the transport designed so Architecture A remains addable per-turn without a redesign.**

Reasoning, confirmed by the project owner: the target host is modest, single-machine self-hosted hardware already carrying EVE, PostgreSQL, and Hermes (`eve-os/docs/architecture.md` — accepted self-hosted topology). Adding continuous server-side audio-to-text for a personal, always-nearby assistant is a meaningful load and privacy cost for a benefit (STT quality/consistency) that Apple's on-device recognizers largely close today — and unlike the original discovery pass assumed, this isn't a case of "server STT doesn't exist yet so there's no real alternative": Hermes already runs production server-side STT for its other channels (`docs/backend-api.md`), so the choice is a genuine tradeoff, not a default born of absence. On-device STT also directly serves the brief's dominant goal — minimum latency to EVE starting to respond — since it removes a full network round trip from the hot path before the LLM can even begin.

This is explicitly *not* a permanent, protocol-level lock-in — the owner was clear the architecture must abstract STT so server-side streaming audio can be added later without redesigning the wire protocol. The event protocol below places `transcript.partial`/`transcript.final` in the same envelope whether they were produced on-device or server-side, so routing raw audio through the gateway to Hermes' existing STT (e.g., if Swedish recognition quality on-device proves insufficient in practice) is a gateway/protocol-version change, not a client rearchitecture. TTS is server-side in both architectures — see below.

The choice should still be validated after Milestone 2/3 physical testing against real Swedish speech, per Engineering Principle 3 (verify, don't assume) — "locked" means it's the plan to build against, not that it's been proven correct on-device yet.

## TTS

**As actually built (GW-M3, 2026-08-19):** the Gateway synthesizes voice replies itself, locally and fully offline, via Piper (`eve-os` `eve/gateway/tts.py`) — a single fixed voice (`sv_SE-lisa-medium`, a female Swedish voice, baked into the Gateway's Docker image), not a Hermes-selected or client-selectable provider. This app receives one complete synthesized WAV per turn as a base64 `data_url` on `conversation.response` (`AudioPlaybackService`) — never a provider identifier, and never streamed audio chunks yet (that's Milestone 4). The rest of this section is the original discovery-pass research and is still factually true of Hermes itself, just not what this app's voice path actually uses:

Hermes' `agent/tts_registry.py` + `tools/tts_tool.py` implement a pluggable-backend TTS interface (`edge` free/no-key, `openai`, `elevenlabs`, `minimax`, `gemini`, `mistral`, `xai`, `piper`, `kittentts`, `neutts` free/local), in production use across WhatsApp, Telegram, Discord, and the CLI/desktop voice modes (`docs/backend-api.md`) — for those *other* Hermes channels, not for this app. Proxying that registry for this app's voice replies was the original GW-M3 plan; it was abandoned during implementation because the only working Hermes-side TTS surface turned out to be an undocumented, desktop-app-internal endpoint requiring its own always-on Hermes-side process (see `eve-os` `docs/voice-gateway.md`, "GW-M3 — Voice", for the full reasoning).

On-device `AVSpeechSynthesizer` is reserved for hard-failure degraded mode only (e.g., a local "connection lost" utterance when the gateway is unreachable), never as a stand-in for EVE's actual voice.

## Streaming

Recommended transport: **WebSocket** for the voice session, carrying the event protocol below as JSON text frames plus binary audio frames (for TTS playback, and for architecture-A raw audio if/when enabled). This isn't a design built from nothing — it deliberately mirrors a real, working reference implementation: Hermes' own desktop app streams TTS over exactly this shape today (`docs/backend-api.md` — `/api/audio/speak-stream`: client sends `{"text": "..."}` deltas and `{"done": true}`, server replies with a `{"type":"start","sample_rate":...}` control frame, raw 16-bit PCM binary frames as they're synthesized, then `{"type":"end"}`/`{"type":"fallback"}`). The EVE Voice Gateway's job for the TTS-out half of the protocol was originally scoped as largely proxying/adapting that existing, production-proven mechanism for iOS rather than inventing a new one.

**This needs revisiting before Milestone 4:** it was written before the GW-M3 decision (above, "TTS") to synthesize voice replies locally via Piper instead of depending on any Hermes TTS surface at all. Streaming Piper's own output in chunks, rather than adopting Hermes' `/api/audio/speak-stream` mechanism this app's voice path no longer otherwise touches, is likely the more consistent design for Milestone 4 — not yet decided, called out here rather than silently carried forward (see `eve-os` `docs/voice-gateway.md`, "GW-M4 — Streaming", for the matching note on the Gateway side). The transcript/response-text event needs described in the rest of this section are unaffected either way.

Rationale against the alternatives the brief asks to evaluate:

- **HTTP streaming / chunked responses** — works one-directional (server → client token/audio streaming) but is awkward for the client's need to send an interruption signal mid-response without opening a second connection.
- **Server-Sent Events** — same one-directional limitation as above; no clean way to carry binary audio frames.
- **WebRTC** — the right tool if this project ever needs true full-duplex audio (simultaneous send+receive, e.g., for a more natural talk-over experience or multi-party home-automation-style audio). It is significant additional complexity (ICE/STUN/TURN, media negotiation) for v1's push-to-talk/turn-based interaction model. Revisit if/when true duplex barge-in (not just "stop and restart") becomes a hard requirement.

A plain request/response (`POST /api/v1/conversation`) remains the right transport for Milestone 2 (text-only conversation, no streaming yet) before the WebSocket voice session is built in Milestone 4.

### Target low-latency flow

```
User speaking
     ↓
(on-device STT, streaming partials)
     ↓
transcript.final over WebSocket
     ↓
LLM processing (server)
     ↓
response.text.delta events (streamed)
     ↓
incremental TTS (server starts synthesizing before the full response text is done)
     ↓
tts.audio.chunk events, played as they arrive
```

The goal stated in the brief — EVE starts responding rather than waiting for the whole pipeline — requires the backend to start TTS on partial response text, not just stream text and wait for it to finish before synthesizing. That is a backend implementation detail this client cannot force, but the protocol below is designed to carry it once available.

## Protocol

JSON envelope, one event per WebSocket text frame:

```json
{
  "v": 1,
  "type": "transcript.partial",
  "session_id": "uuid",
  "seq": 42,
  "ts": "2026-08-16T10:00:00Z",
  "data": { "text": "hur mår servern hemma" }
}
```

- `v` — protocol version, integer, incremented on any breaking change to event shapes. The client rejects/logs (does not crash on) an event with an unrecognized `type` or a higher `v` than it understands, per Engineering Principle: fail closed, not silently.
- `seq` — monotonically increasing per session, lets the client detect drops/reordering over an unreliable connection.

Event catalog (from the brief, §18), grouped by direction:

**Client → server:** `session.started`, `audio.started`, `audio.chunk` (binary frame, if architecture A is active for this session), `audio.finished`, `conversation.interrupted`, `session.closed`.

**Server → client:** `transcript.partial`, `transcript.final` (echoed back even for on-device STT, so the UI and any server-side logging agree on exactly what was heard), `assistant.thinking`, `response.started`, `response.text.delta`, `response.text.completed`, `tts.started`, `tts.audio.chunk` (binary frame), `tts.completed`, `error`.

`error` carries a machine-readable `code` and human-readable `message`, and never terminates the session by itself — the client decides whether to retry the turn or surface the error, per the "must not get stuck listening/processing" requirement (brief §26).

### Versioning

The envelope's `v` field is the only compatibility contract. New event types may be added without a version bump (clients must ignore unknown types). Any change to an existing event's required fields is a breaking change and bumps `v`. The server should support at least the current and previous `v` during a migration window; this repository documents but does not implement server-side version negotiation, since that's backend work.

## Barge-in (interruption)

Designed into the protocol from the start (per brief §10 — "should be introducible without an architecture change"), even though it is a later milestone (Milestone 6). Unlike the rest of this document's original draft, this isn't speculative: Hermes already has a full, shipping barge-in implementation for its other voice surfaces (CLI, TUI, desktop, Discord voice channels — `docs/backend-api.md`) — VAD-based interruption during either generation or playback, a configurable stop-phrase, and the interrupted turn is fed back to the model so it knows it was cut off. The gateway has real primitives to call: `POST /v1/runs/{id}/stop` to hard-interrupt a run, `POST /v1/runs/{id}/steer` to inject guidance into a still-running turn, and — for the TTS-out half — simply closing the `/api/audio/speak-stream`-equivalent socket, which the desktop client confirms "the server aborts synthesis on disconnect." This app's job is the same shape, translated to the gateway's protocol rather than Hermes' internal one:

1. Client detects interruption: either explicit (user taps a "stop" affordance) or, once local voice-activity detection is wired up, implicit (on-device STT/voice-activity detector notices speech while `speaking`).
2. Client immediately stops local TTS audio playback — this is a local, zero-latency action, never waits on a server round trip.
3. Client sends `conversation.interrupted` with the session id and current playback position (so the gateway can decide how much of its prior response to treat as "delivered" for memory/context purposes — a gateway/Hermes-side decision, not this client's — and can map it onto `/v1/runs/{id}/stop` or `/steer` as appropriate).
4. Client transitions state to `listening` and begins capturing the new utterance immediately; the new utterance is sent as a normal new turn once finalized.

No new message types are needed beyond `conversation.interrupted`, which already exists in the v1 event catalog above — this is why barge-in doesn't require a protocol version bump when implemented.
