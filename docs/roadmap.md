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

**Status: Blocked on the EVE Voice Gateway's device-pairing/auth (`docs/security.md`).**

Deliver: repository, Xcode project, SwiftUI application shell, networking layer, configuration, Keychain, connection status. All of this is scaffolded in this initial commit (see `EVE/` and `project.yml`) as buildable stubs; none of it has been run against a real backend, because the Gateway and its pairing flow don't exist yet.

Acceptance: `iPhone → EVE Voice Gateway` works securely. Achievable today only as an unauthenticated-to-authenticated `/health`-equivalent reachability check once a device is pointed at a real deployment over Tailscale; full acceptance needs the pairing flow.

## Milestone 2 — Text conversation

**Status: Blocked on the EVE Voice Gateway existing at all (`docs/architecture.md`).**

```
iPhone → text → EVE Voice Gateway → Hermes/EVE → response → iPhone
```

Acceptance: the app can hold a real conversation with the existing EVE/Hermes system. The underlying Hermes capability already exists and works today (`POST /api/sessions/{id}/chat` / `.../chat/stream` — `docs/backend-api.md`); what's missing is the Gateway to sit between the phone and it, since this app must never hold Hermes' shared `API_SERVER_KEY` directly.

## Milestone 3 — Push-to-talk

**Status: Blocked on Milestones 1-2; the underlying STT/TTS this depends on already exists in Hermes (`docs/backend-api.md`).**

```
tap → speak → EVE → spoken response
```

Acceptance: a full voice round-trip works on a physical iPhone. Client-side pieces (mic capture, on-device STT per `docs/voice-architecture.md`'s locked Architecture B decision, audio playback) are scaffolded but unverified. Unlike the original discovery pass assumed, TTS is not the blocker here — Hermes already has multiple working TTS providers in production; the Gateway just needs to expose one of them through the protocol in `docs/voice-architecture.md`.

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
