# iOS System Integrations

Findings below are checked against current Apple developer documentation and WWDC material (see sources cited inline) rather than assumed. Where Apple's public documentation doesn't give a definitive answer, that is stated explicitly rather than guessed — per this project's principle of not basing architecture on unverified assumptions about platform capability.

## Siri / App Intents

**Verdict: use this. It's the primary v1 entry point.**

The `AppIntents` framework (iOS 16+) is how an app exposes actions to Siri, Spotlight, the Shortcuts app, and the Action Button, without a separate SiriKit domain integration. Two pieces:

- **`AppShortcutsProvider`** — a static struct the app declares; the system automatically registers a built-in voice phrase the moment the app is installed, with zero user setup. This is the mechanism for "Siri, prata med EVE" (brief's minimum requirement).
- **`AppIntent`** conforming types (e.g. `TalkToEVEIntent`) — the actual action. Setting `static var openAppWhenRun: Bool = true` brings the app to the foreground to complete the interaction (required here, since starting a voice session needs the app's own UI/audio session); background-only intents (`openAppWhenRun = false`) are for actions that don't need foreground UI, which doesn't fit this app's primary use case.

Parameterized intents (e.g. "Siri, fråga EVE om huset") are straightforward extensions of the same `AppIntent` pattern with an `@Parameter` — a natural-language topic string handed to the backend as the opening turn of a new conversation, not interpreted client-side. Per the brief's constraint, Siri is only ever the entry point; it must never itself decide what EVE's answer is.

**Open decision:** exact intent set and phrasing for Swedish ("prata med EVE", "fråga EVE om...") needs Apple's Swedish Siri phrase-matching behavior verified on-device once Milestone 7 starts — App Intents phrase matching quality for non-English locales is not something documented precisely enough to commit to before physical testing.

## Action Button

**Verdict: use this. Zero extra work beyond a correctly declared `AppShortcut`.**

On iPhone 15 Pro and later (and the standard iPhone 16e/17 button lineup as of current hardware), the Action Button is configured by the user in Settings → Action Button → Shortcut, and any `AppShortcut`/`AppIntent` an app exposes is automatically available there — no Action-Button-specific API. This makes it, from this app's perspective, exactly the same integration surface as Siri and Spotlight: implement the `AppIntent` once, get all three entry points.

**Important constraint (verified):** an intent triggered from a fully backgrounded/killed state **cannot cold-start microphone capture**. Apple's `AudioRecordingIntent` documentation and WWDC 2025 session ("Enhance your app's audio recording capabilities") are explicit that starting an `AVAudioSession` for recording from a fully backgrounded app is blocked by design; a recording session must be initiated while the app is foregrounded, after which it can be paused/resumed from the background (e.g. via a Live Activity button). In practice this means: Action Button / Siri intent → app launches to foreground (`openAppWhenRun = true`) → *then* the app requests the microphone and starts listening. The "microphone active" step in the brief's Action Button diagram (§12) happens after a real (if brief) app-foregrounding transition, not instantaneously from a locked/backgrounded state — this is an iOS platform limitation, not a gap in this app's design, and should be presented to the user as "one tap to launch, immediately listening" rather than "instant background activation."

## Lock Screen, widgets, Live Activities, Control Center

Documented Apple constraints, not this app's choices to make differently:

- **Live Activities (`ActivityKit`)** can show an active EVE session's state on the Lock Screen/Dynamic Island (e.g. "EVE is listening" / "EVE is speaking") and can offer buttons that pause/resume an *already-running* audio session. They cannot start a new microphone session from cold — see the Action Button constraint above, which applies identically here.
- Live Activity updates while background audio is playing are explicitly throttled by the system and behave differently on-device vs. in the Simulator (per Apple developer forum guidance) — this must be verified on physical hardware before any milestone claims it works, per Engineering Principle 9.
- **Widgets** can show connection status and offer a Shortcuts-based quick-launch button (same `AppIntent` mechanism as above); they cannot host any audio or long-running session logic themselves.
- **Control Center** does not have a general third-party "launch and immediately start doing X" module beyond what Shortcuts already exposes as a Control Center widget (iOS 18+ Controls API, itself backed by `AppIntent`) — no separate integration surface is needed beyond declaring the same intents as Control Center-eligible controls.
- **Background execution** for this app is fundamentally limited to: brief background audio continuation for an already-active session (`UIBackgroundModes: audio`), and standard background app refresh/push-triggered wake — not continuous microphone listening while backgrounded or locked. Any design implying "EVE is always listening in the background" would violate this constraint and is explicitly out of scope.

## Push-to-Talk framework

**Verdict: do not use for v1.** Evaluated per the brief's explicit request (§14) rather than dismissed without checking.

Apple's `PushToTalk` framework (introduced WWDC 2022) is purpose-built for walkie-talkie-style, multi-participant group communication apps (its own framing: "a new class of audio communication app... walkie-talkie style experience"), backed by `CallKit`/`PushKit` VoIP push infrastructure so a channel can wake the app and activate the microphone even from a killed state — which sounds superficially close to "instant EVE activation," but:

- It requires the dedicated `com.apple.developer.push-to-talk` entitlement, which Apple grants through its standard entitlement-request process for this specific app category; it is not something every app can simply enable. There is no public confirmation that a single-user personal-assistant use case (as opposed to a group radio/dispatch app) is a use Apple intends this entitlement for, and requesting it under false pretenses (declaring a walkie-talkie use case that doesn't exist) is not something this project will do.
- The framework's model — channels, participants, transmit/receive roles — doesn't map onto "one user talking to one assistant." Building around it would mean bending the app's actual interaction model to fit infrastructure designed for a different one, which fails this project's "native Apple APIs first, but only where they actually fit" principle (brief §37.4/§14's own instruction: "use the framework only if it actually fits").
- iOS 26 tightened VoIP-push/PushKit obligations further (apps receiving a VoIP push must report to CallKit or be terminated by the system), adding compliance surface for a framework that wasn't the right fit to begin with.

**Recommendation:** get "activate EVE fast" from the Action Button + Siri App Intents path instead (§ above), which has none of PushToTalk's entitlement gating or category mismatch. Revisit only if Apple's guidance for this entitlement changes, or if a future multi-user/multi-device "broadcast to EVE" scenario actually emerges.

## Bluetooth / AirPods

Standard `AVAudioSession` route handling (`Services/Audio`), not a separate integration:

- `AVAudioSession.Category.playAndRecord` with a voice-oriented mode (`.voiceChat` or `.spokenAudio` depending on which best fits conversational latency vs. audio quality trade-offs — to be validated on-device in Milestone 3/4) plus `.allowBluetooth`/`.allowBluetoothA2DP` options routes audio through AirPods automatically once paired, without app-specific Bluetooth code.
- The app must not hardcode iPhone-speaker-specific behavior anywhere (no assumptions about output route in UI copy or audio processing) — route changes (AirPods connect/disconnect mid-session, phone call interruption, Siri interruption) are handled via `AVAudioSession.routeChangeNotification` / `interruptionNotification`, restoring or gracefully ending the session rather than crashing or hanging in `listening`/`processing` state (ties to the state-machine design in `docs/architecture.md` and the "must not get stuck" requirement in the brief, §26).

## Speech framework (on-device STT)

Two generations are relevant, both from Apple's own framework, not a third-party dependency:

- **`SFSpeechRecognizer`** (`Speech` framework, iOS 10+) — the long-standing API; supports on-device recognition (`requiresOnDeviceRecognition`) for a set of locales that has grown over time and is only reliably checked at runtime via `SFSpeechRecognizer.supportedLocales()`.
- **`SpeechAnalyzer` / `SpeechTranscriber`** (new in iOS 26, WWDC 2025) — a newer on-device model line built for more accurate, longer-form transcription, explicitly positioned by Apple as the successor path. It ships alongside a `SpeechDetector` module for voice-activity detection, which is directly useful for the barge-in detection described in `docs/voice-architecture.md`.

**Resolved during Milestone 3 implementation:** `SpeechRecognitionService` (`EVE/Services/Speech/`) targets `SFSpeechRecognizer` with `sv-SE`, matching this app's `deploymentTarget` of iOS 17.0 — `SpeechAnalyzer`/`SpeechTranscriber` requires iOS 26+, which the app doesn't require yet. Physically verified working (real Swedish speech, real device, `docs/roadmap.md` Milestone 3) — `sv-SE` on-device recognition coverage is confirmed sufficient in practice, not just checked against Apple's locale API. Migrating to `SpeechAnalyzer`/`SpeechTranscriber` once the deployment target allows it remains open future work (noted directly in the code), not a hard requirement.
