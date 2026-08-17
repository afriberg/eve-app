# EVE iOS App

A native iOS voice client for **EVE**, a persistent personal intelligence layer. This app is not EVE — it is EVE's thin, native interface on Apple platforms.

## Purpose

Let the owner reach EVE from an iPhone with as few steps as possible: activate, speak, hear a spoken answer, keep talking. No WhatsApp, no typing, no menu diving.

```
User speaks → iPhone captures/streams audio → EVE/Hermes backend → speech understood →
EVE reasons using her existing identity/memory/tools → response generated →
response spoken back → user can keep talking or interrupt
```

## What this app is (and is not)

This app owns:

- SwiftUI user interface and voice-first interaction states
- microphone capture and audio playback (AVFoundation / AVAudioSession)
- on-device speech recognition where the chosen architecture calls for it (Speech framework)
- secure transport to the EVE/Hermes backend
- local session/connection state and a small local cache for UX
- Siri / App Intents / Action Button entry points
- Keychain-backed device credentials

This app explicitly does **not** own, and must never re-implement:

- EVE's identity, durable memory, or world model
- LLM routing, reasoning, or tool execution
- Home Assistant integration or other automation
- Hermes' conversation runtime, scheduling, or channel handling (WhatsApp etc.)

All of that remains server-side, in the separate [`eve-os`](../eve-os) repository (EVE) and the Hermes runtime it integrates with. See [`docs/architecture.md`](docs/architecture.md) for the full system boundary and [`docs/backend-api.md`](docs/backend-api.md) for exactly what the existing backend already exposes versus what is still missing.

## Current project status

**Milestone 1 (Foundation) — client-side implemented, CI-green, not yet device-verified.** The `EVE Voice Gateway` this app talks to is now real and implemented in `eve-os` (`eve/gateway/`, repository/CI-verified — see its `docs/voice-gateway.md`). This repository's client foundation is implemented against that real API: a pinned `GatewayAPIClient`/`GatewayTrustEvaluator` (TLS pinned to a bundled, per-deployment EVE root CA — never the system trust store), the real three-step pairing flow (`DevicePairingService`, `PairingViewModel`), a `GatewayWebSocketClient` session-lifecycle foundation, and Keychain-backed credential storage. GitHub Actions (macOS runner) builds the app and runs the full test suite on every push — both green as of commit `fd67472`, including the launch UI test passing on a real booted iOS Simulator. See [`docs/roadmap.md`](docs/roadmap.md) for exactly what that does and doesn't cover (no microphone/Siri/real-network verification yet), and `EVE/Resources/EVERootCA-README.md` for the one manual step required before this app can build against a real deployment.

**Backend picture:** the architecture is locked — a dedicated **EVE Voice Gateway** sits between this app and Hermes (`EVE iOS App → EVE Voice Gateway → Hermes/EVE`, reachable only over the owner's existing WireGuard VPN, never Tailscale or any public endpoint), handling device pairing, sessions, and streaming. See [`docs/architecture.md`](docs/architecture.md) for the decision and [`docs/backend-api.md`](docs/backend-api.md) for exactly what the Gateway (and the Hermes API it adapts — confirmed via reading [`nousresearch/hermes-agent`](https://github.com/nousresearch/hermes-agent) directly) already provides versus what's still foundation-only.

## Requirements

- Xcode 16 or later, iOS 17+ deployment target (see [`docs/roadmap.md`](docs/roadmap.md) for why; some integrations such as the Action Button and the newest on-device speech APIs require iOS 17/18/26 depending on feature)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml` (the generated project is not committed — see below)
- A physical iPhone for any voice/audio work; the Simulator cannot exercise microphone, AirPods routing, or Siri/Action Button integrations

## Development setup

```bash
brew install xcodegen
xcodegen generate
open EVE.xcodeproj
```

The `.xcodeproj` is generated, not committed, so the repository stays diff-friendly and avoids merge conflicts in Xcode's project file format. Regenerate it after adding/removing files or editing `project.yml`.

## Build

```bash
xcodegen generate
xcodebuild -project EVE.xcodeproj -scheme EVE -destination 'generic/platform=iOS Simulator' build
```

## Test

```bash
xcodebuild -project EVE.xcodeproj -scheme EVE -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Unit and integration tests run in CI on every push (see `.github/workflows/ci.yml`). Voice, microphone, Bluetooth/AirPods routing, and Siri/Action Button behavior are **not** verifiable in CI or the Simulator and require physical-device acceptance before any milestone claiming those features is considered done (see [`docs/roadmap.md`](docs/roadmap.md), Engineering Principle 9).

## Backend dependency

This app talks to the EVE/Hermes backend described in the sibling `eve-os` repository. It does not vendor, duplicate, or reimplement any backend logic. Configuring a backend server (URL, pairing) happens once per device via Settings → EVE Server; see [`docs/security.md`](docs/security.md) for the device-enrollment design.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — system boundary, client architecture, state machine
- [`docs/backend-api.md`](docs/backend-api.md) — what `eve-os`/Hermes already expose today, and the gap this app depends on closing
- [`docs/voice-architecture.md`](docs/voice-architecture.md) — Architecture A vs. B analysis, streaming/barge-in protocol, TTS abstraction
- [`docs/security.md`](docs/security.md) — device enrollment, Keychain usage, transport, privacy
- [`docs/ios-integrations.md`](docs/ios-integrations.md) — Siri/App Intents, Action Button, Lock Screen/Live Activities, Push-to-Talk framework findings against current Apple documentation
- [`docs/roadmap.md`](docs/roadmap.md) — milestones and current status

## License

Private project. Not licensed for external use or distribution.
