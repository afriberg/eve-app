# Voice Architecture

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
| Privacy | Raw voice audio leaves the device on every turn. | Only transcribed text leaves the device. Meaningfully better for a personal assistant handling private household/infrastructure topics (per `eve-os`'s own domain: Home Assistant, Proxmox, family matters). |
| Bandwidth | Continuous audio upstream (compressed, but still real audio). | Small: text upstream, audio only downstream for the answer. Matters on cellular/VPN. |
| Swedish recognition quality | Depends entirely on whatever STT the backend runs — quality/language coverage is a backend decision, currently unknown (`docs/backend-api.md` — no STT exists in `eve-os` today). | Depends on Apple's on-device models. Apple's Speech framework has supported Swedish (`sv-SE`) as a recognizer locale for years; iOS 26 additionally ships `SpeechAnalyzer`/`SpeechTranscriber`, a newer on-device model line (WWDC 2025) aimed at long-form, more accurate transcription, replacing `SFSpeechRecognizer` as the default going forward. Exact on-device-vs.-server-required locale support must be verified at implementation time via `SFSpeechRecognizer.supportedLocales()` / the `SpeechTranscriber` locale API on the target OS version — do not assume `sv-SE` support without checking, since Apple's documentation does not publish a stable locale table and it has changed release to release.
| Reliability / offline | Fails completely without network for the whole turn (recognition + reasoning both need the backend). | Transcription can succeed offline; the turn as a whole still needs network for EVE's reasoning, so full offline operation isn't a realistic goal either way — but degraded connectivity fails later in the pipeline (after the user already sees their words recognized), which is a better user experience than silence. |
| Interruption / barge-in | Server needs to be told to stop generating/streaming TTS; the client just stops playback and starts a new audio stream — simple client-side, needs a clear server protocol (see below). | Same server-side requirement, but the client's own STT can also detect the user is speaking again as a *local* signal (voice activity), giving faster barge-in detection than waiting on a server round-trip. |
| Server load | Every household member's every utterance is server-side audio-to-text work. On a Raspberry Pi (the documented production host), this is a real constraint. | STT cost is offloaded to Apple Silicon on the phone; the Pi only handles reasoning and TTS. |
| Streaming capability | Naturally streams (it's an audio pipe); partial transcripts depend on the server STT supporting streaming. | Apple's on-device recognizers support partial-result callbacks natively and cheaply. |
| Consistency across future clients (Watch, CarPlay, other users) | One STT implementation to maintain and tune. | STT quality/behavior potentially differs per platform's on-device capability (a real concern if a Watch client uses a weaker on-device model, or no on-device model at all). |

## Recommendation

**Hybrid, defaulting to Architecture B for STT, with the transport designed so Architecture A remains possible per-turn without a redesign.**

Reasoning: the target host is a Raspberry Pi already carrying EVE, PostgreSQL, and Hermes (`eve-os/docs/architecture.md` — Accepted Raspberry Pi topology). Adding continuous server-side audio-to-text for a personal, always-nearby assistant is a meaningful load and privacy cost for a benefit (STT quality/consistency) that Apple's on-device recognizers largely close today. On-device STT also directly serves the brief's dominant goal — minimum latency to EVE starting to respond — since it removes a full network round trip from the hot path before the LLM can even begin.

This is *not* a permanent, unconditional choice. The event protocol below places `transcript.partial`/`transcript.final` in the same envelope whether they were produced on-device or server-side, so a future decision to route raw audio to a stronger server STT (e.g., if Swedish recognition quality on-device proves insufficient in practice, or if a non-Apple client needs support) is a backend/protocol-version change, not a client rearchitecture. TTS is server-side in both architectures — see below.

This recommendation should be revisited after Milestone 2/3 physical testing against real Swedish speech, per Engineering Principle 3 (verify, don't assume).

## TTS

TTS is abstracted behind a single interface on the backend side; the client only ever receives audio (or streamed audio chunks) and metadata, never a provider identifier. Per the brief, the desired end state is one permanent, recognizable EVE voice, consistent across every client (iOS, and later Watch/CarPlay) — which argues for TTS staying entirely server-side (Hermes' existing TTS, Edge TTS, ElevenLabs, or a future provider) rather than falling back to on-device `AVSpeechSynthesizer` for anything but hard-failure degraded mode (e.g., a local "connection lost" utterance). No such provider exists yet in what's visible from `eve-os` — see `docs/backend-api.md`, gap item 4.

## Streaming

Recommended transport: **WebSocket** for the voice session, carrying the event protocol below as JSON text frames plus binary audio frames (for TTS playback, and for architecture-A raw audio if/when enabled). Rationale against the alternatives the brief asks to evaluate:

- **HTTP streaming / chunked responses** — works one-directional (server → client token/audio streaming) but is awkward for the client's need to send an interruption signal mid-response without opening a second connection.
- **Server-Sent Events** — same one-directional limitation as above; no clean way to carry binary audio frames.
- **WebRTC** — the right tool if this project ever needs true full-duplex audio (simultaneous send+receive, e.g., for a more natural talk-over experience or multi-party Home Assistant-style audio). It is significant additional complexity (ICE/STUN/TURN, media negotiation) for v1's push-to-talk/turn-based interaction model. Revisit if/when true duplex barge-in (not just "stop and restart") becomes a hard requirement.

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
  "data": { "text": "hur mår proxmox" }
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

Designed into the protocol from the start (per brief §10 — "should be introducible without an architecture change"), even though it is a later milestone (Milestone 6):

1. Client detects interruption: either explicit (user taps a "stop" affordance) or, once local voice-activity detection is wired up, implicit (on-device STT/voice-activity detector notices speech while `speaking`).
2. Client immediately stops local TTS audio playback — this is a local, zero-latency action, never waits on a server round trip.
3. Client sends `conversation.interrupted` with the session id and current playback position (so the server can decide how much of its prior response to treat as "delivered" for memory/context purposes — a server-side decision, not this client's).
4. Client transitions state to `listening` and begins capturing the new utterance immediately; the new utterance is sent as a normal new turn once finalized.

No new message types are needed beyond `conversation.interrupted`, which already exists in the v1 event catalog above — this is why barge-in doesn't require a protocol version bump when implemented.
