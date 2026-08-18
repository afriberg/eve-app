# Roadmap

Status legend: **Not started** / **In progress** / **Blocked** (names what it's blocked on) / **Done (device-verified)** — nothing is marked done on the strength of code existing or compiling alone; voice/audio/Siri/Action-Button/Bluetooth claims specifically require physical-device verification (Engineering Principle 9).

## Milestone 0 — Discovery

**Status: Done.**

- [x] Read `eve-os` for existing APIs, Hermes interfaces, voice/STT/TTS, authentication, networking, session management — see `docs/backend-api.md`.
- [x] Checked current Apple API constraints against official/WWDC documentation — see `docs/ios-integrations.md`.
- [x] Proposed final iOS ↔ EVE architecture — see `docs/architecture.md`, `docs/voice-architecture.md`.
- [x] Repository, initial docs, Xcode skeleton, CI created.

**Key finding, updated 2026-08-16:** the initial discovery pass (reading only `eve-os`) concluded the backend had no conversation, voice, or per-device-auth surface at all. After being pointed at Hermes' actual source (`nousresearch/hermes-agent`) and reading it directly, that turned out to be substantially wrong: Hermes already has a working conversation/streaming API, SSE run events, an interrupt/steer mechanism, and pluggable TTS/STT already in production use — see `docs/backend-api.md`. The remaining blocker for Milestones 1-3 is narrower than originally scoped: build the **EVE Voice Gateway** (locked architecture decision, `docs/architecture.md`), which is now a well-scoped adapter over known, working Hermes endpoints plus new device-pairing logic — not an open-ended "invent conversation and voice from nothing" project. That Gateway work belongs in `eve-os` (decided 2026-08-16, as a new Docker Compose service, not a separate repository — see `eve-os/docs/voice-gateway.md`), so Milestones 1-3 remain blocked on it, just on a smaller, better-understood, and now-documented piece of work than before.

## Milestone 1 — Foundation

**Status: Done (device-verified).** The Gateway (`eve-os` `eve/gateway/`) is implemented and physically accepted. Client-side: `GatewayAPIClient` (health/pairing/session REST calls), `GatewayTrustEvaluator` (pins to the bundled EVE root CA, fails closed if it's absent), `GatewayWebSocketClient` (WSS session-lifecycle foundation), `DevicePairingService` + `PairingViewModel` (the real three-step request → owner-approve → claim flow, with a bounded poll loop), wired into Settings. Verified for real: a physical iPhone, sideloaded (no paid Apple Developer account — `docs/sideloading.md`), paired over the owner's real WireGuard VPN against the production Gateway, TLS validated against the pinned local EVE CA, and now holds a permanent device credential in `eve_gateway.devices`. Two real backend bugs (container TLS-key permissions, CA-key mount scope) were found and fixed during this pass — see `eve-os` `docs/voice-gateway.md`. A real client bug was also found and fixed this way: the Settings server-URL field wasn't persisting/redisplaying correctly across navigation on a real device (an async-vs-synchronous SwiftUI state-init race that didn't reproduce from reading the code, only from testing on hardware) — three iterative fixes, the last one (synchronous `.onAppear` prefill) confirmed working.

Acceptance: `iPhone → EVE Voice Gateway` works securely, over the owner's real WireGuard VPN, with a real paired device. **Run and passing.**

## Milestone 2 — Text conversation

**Status: Implemented, CI-verified — physical device/Gateway acceptance pending.**

```
iPhone → text → EVE Voice Gateway → Hermes/EVE → response → iPhone
```

`ConversationViewModel` + `ConversationView` (reachable from the main screen's toolbar, alongside Settings) send `conversation.message` over the same GW-M1 WS session (`GatewayWebSocketClient.sendConversationMessage`/`receiveConversationEvent`, decoding `session.started`/`conversation.response`/`error`/`session.closed`) and render the resulting turn history. One synchronous turn per message — no streaming yet, matching the Gateway's own GW-M2 scope (`eve-os` `docs/voice-gateway.md`). `ConversationTransport` is a small protocol `GatewayWebSocketClient` conforms to, purely so `ConversationViewModel` can be unit tested against a fake (`URLSessionWebSocketTask` has no `URLProtocol`-style interception seam the way `GatewayAPIClient`'s HTTP calls do). 9 new `ConversationViewModelTests` cover connect success/failure, turn recording, a Hermes-unavailable `error` event surfacing as a failed state without losing the user's own turn, empty-text and not-connected no-ops, and disconnect. Verification is CI-only (GitHub Actions macOS runner build+test) — no physical device or real Gateway/Hermes instance has exercised this yet.

Acceptance: the app can hold a real conversation with the existing EVE/Hermes system. The underlying Hermes capability already exists and works today (`POST /api/sessions/{id}/chat` / `.../chat/stream` — `docs/backend-api.md`); the Gateway now sits between the phone and it (`eve-os` `eve/gateway/hermes_client.py`), so this app never holds Hermes' shared `API_SERVER_KEY` directly. **Not yet run against a real device/Gateway/Hermes instance.**

## Milestone 3 — Push-to-talk

**Status: Implemented, CI-verified — physical device/Gateway acceptance pending.**

```
tap → speak → EVE → spoken response
```

`SpeechRecognitionService` captures the microphone and transcribes on-device (Architecture B, `docs/voice-architecture.md`) while the push-to-talk button is held; `VoiceViewModel` sends the final transcript as a normal GW-M2 `conversation.message` and reads an optional `data.audio` field off the `conversation.response` (a complete synthesized WAV utterance, base64-encoded — non-streaming, matching the Gateway's own GW-M3 scope, eve-os `docs/voice-gateway.md`); `AudioPlaybackService` plays it. A missing `audio` field (voice disabled, or synthesis failed on the Gateway) is not an error — the turn still completes with just the text, mirroring the Gateway's own graceful degradation. `SpeechCapturing`/`AudioSessionActivating`/`AudioPlaying` are small protocol seams (same reasoning as `ConversationTransport`) so `VoiceViewModel` is unit-testable against fakes rather than real hardware/frameworks — 9 new `VoiceViewModelTests` cover connect/listen/respond/error/disconnect. Unlike the original discovery pass assumed, TTS was not the real blocker — Hermes already has multiple working TTS providers in production; the Gateway ended up synthesizing locally via Piper instead of proxying Hermes' TTS (see `docs/voice-gateway.md`, "GW-M3 — Voice", for why), which changes where synthesis happens but not this client's protocol.

Acceptance (not yet run): a full voice round-trip — tap, speak Swedish, hear EVE's spoken reply — on a physical iPhone against the real Gateway/Hermes. Verification so far is CI-only (GitHub Actions macOS simulator build+test); Speech-framework/AVAudioEngine behavior specifically cannot be meaningfully exercised in the Simulator (no real microphone) and has not been tried on real hardware yet.

## Milestone 4 — Streaming voice

**Status: Not started.** Requires the WebSocket protocol in `docs/voice-architecture.md` to exist through the Gateway — which can be built by adapting Hermes' own working `/api/audio/speak-stream` mechanism (`docs/backend-api.md`) rather than inventing streaming synthesis from scratch. Acceptance: EVE begins responding without waiting for the full pipeline; latency measured per the metrics in this document's "Latency metrics" section below.

## Milestone 5 — Continuous conversation

**Status: Not started.** Natural multi-turn conversation without re-triggering push-to-talk for every turn. Acceptance: several questions answered in sequence without the user manually restarting each turn.

## Milestone 6 — Interruption (barge-in)

**Status: Not started, but lower-risk than originally scoped.** Protocol already designed to not require a version bump (`docs/voice-architecture.md`), and Hermes already has a full, shipping barge-in implementation for its other voice surfaces (`docs/backend-api.md`) that the Gateway can adapt via `/v1/runs/{id}/stop`/`steer`. Acceptance: user can interrupt EVE mid-response.

## Milestone 7 — Siri / App Intents

**Status: Not started.** "Siri, prata med EVE" per `docs/ios-integrations.md`. Acceptance: EVE's voice mode activates via Siri on a physical device (Simulator Siri behavior is not representative).

## Milestone 8 — Quick access

**Status: Not started.** Action Button, Lock Screen/Live Activities, Control Center, Shortcuts — see `docs/ios-integrations.md` for what Apple's current APIs actually allow here (notably: no cold-start background microphone activation). Acceptance target: minimum time from intention to EVE listening, within the platform's real constraints.

## Milestone 9 — Production hardening

**Status: Not started.** Reconnect, network transitions (Wi-Fi ↔ cellular ↔ VPN loss), backend restart, auth expiry, microphone interruptions, Bluetooth/AirPods, background/foreground transitions, battery usage, privacy, security. Every item requires physical-device verification.

## Latency metrics (instrumented from Milestone 3 onward)

- `speech_end → transcript_final`
- `transcript_final → backend_first_token`
- `backend_first_token → tts_first_audio`
- `speech_end → first_audio`
- `total_turn_duration`

## Definition of Done (first major release)

On a physical iPhone, at home on Wi-Fi, away from home over a secure connection, through the iPhone speaker, and through Bluetooth/AirPods:

```
User activates EVE (Siri, Action Button, or app tap)
        → EVE begins listening
        → user speaks Swedish
        → speech is processed
        → existing EVE receives the request
        → EVE uses her existing memory/tools/reasoning
        → response is generated
        → EVE speaks through iPhone/AirPods
        → user can continue speaking
        → user can interrupt EVE
```

Not done until every step above has been exercised on real hardware against a real backend — not simulated, not assumed from passing unit tests.

## Non-goals for this phase

Apple Watch, CarPlay, Widgets/Live Activities beyond status display, and multi-user support are explicitly future work (brief §35) and are not represented in the current Xcode skeleton beyond keeping the client architecture from actively blocking them (e.g., no iPhone-speaker-only assumptions baked into audio code).
