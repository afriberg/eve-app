# Roadmap

Status legend: **Not started** / **In progress** / **Blocked** (names what it's blocked on) / **Done (device-verified)** — nothing is marked done on the strength of code existing or compiling alone; voice/audio/Siri/Action-Button/Bluetooth claims specifically require physical-device verification (Engineering Principle 9).

## Milestone 0 — Discovery

**Status: Done.**

- [x] Read `eve-os` for existing APIs, Hermes interfaces, voice/STT/TTS, authentication, networking, session management — see `docs/backend-api.md`.
- [x] Checked current Apple API constraints against official/WWDC documentation — see `docs/ios-integrations.md`.
- [x] Proposed final iOS ↔ EVE architecture — see `docs/architecture.md`, `docs/voice-architecture.md`.
- [x] Repository, initial docs, Xcode skeleton, CI created.

**Key finding that changes everything downstream:** the backend has no conversation, voice, or per-device-auth surface today (`docs/backend-api.md`). Milestones 1-3 below cannot reach their acceptance criteria until that backend work — which belongs in `eve-os`/Hermes, not here — exists in some form.

## Milestone 1 — Foundation

**Status: Blocked on backend pairing/auth (`docs/backend-api.md` gap item 5).**

Deliver: repository, Xcode project, SwiftUI application shell, networking layer, configuration, Keychain, connection status. All of this is scaffolded in this initial commit (see `EVE/` and `project.yml`) as buildable stubs; none of it has been run against a real backend, because a real backend pairing flow doesn't exist yet.

Acceptance: `iPhone → EVE backend` works securely. Achievable today only as an unauthenticated-to-authenticated `/health` reachability check once a device is pointed at a real EVE deployment over Tailscale; full acceptance needs the pairing flow.

## Milestone 2 — Text conversation

**Status: Blocked on backend conversation endpoint (`docs/backend-api.md` gap item 1).**

```
iPhone → text → EVE → response → iPhone
```

Acceptance: the app can hold a real conversation with the existing EVE/Hermes system. Cannot start until something server-side accepts a live turn and returns a response — `POST /v1/conversations/ingest` in the current EVE API does not do this (it only records an already-completed turn for memory extraction).

## Milestone 3 — Push-to-talk

**Status: Blocked on Milestones 1-2, plus backend STT/TTS (`docs/backend-api.md` gap items 3-4).**

```
tap → speak → EVE → spoken response
```

Acceptance: a full voice round-trip works on a physical iPhone. Client-side pieces (mic capture, on-device STT per `docs/voice-architecture.md` Architecture B recommendation, audio playback) are scaffolded but unverified; TTS specifically has no backend provider to call yet.

## Milestone 4 — Streaming voice

**Status: Not started.** Requires the WebSocket protocol in `docs/voice-architecture.md` to exist server-side. Acceptance: EVE begins responding without waiting for the full pipeline; latency measured per the metrics in this document's "Latency metrics" section below.

## Milestone 5 — Continuous conversation

**Status: Not started.** Natural multi-turn conversation without re-triggering push-to-talk for every turn. Acceptance: several questions answered in sequence without the user manually restarting each turn.

## Milestone 6 — Interruption (barge-in)

**Status: Not started.** Protocol already designed to not require a version bump (`docs/voice-architecture.md`). Acceptance: user can interrupt EVE mid-response.

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
