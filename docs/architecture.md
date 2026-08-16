# Architecture

## Design principle

The app is EVE's native interface on Apple platforms. It is not EVE.

```
iOS App
    │
    │ interface (UI, mic, speaker, transport, local session state)
    ▼
EVE / Hermes backend
    │
    ├── identity
    ├── reasoning / LLM routing
    ├── memory
    ├── tools
    ├── automation
    ├── infrastructure knowledge
    └── integrations (Home Assistant, WhatsApp, ...)
```

Every architectural decision in this document is evaluated against one question: does this keep reasoning, memory, and tool authority on the server, and the phone thin? If a design pushes any of those onto the device, it is wrong regardless of how much it simplifies the client.

## System diagram

```
┌──────────────┐
│    iPhone    │
│              │
│ EVE iOS App  │
└──────┬───────┘
       │
       │ TLS, over Tailscale/VPN (see docs/security.md)
       │
┌──────▼───────┐
│  EVE / Hermes │
│   backend     │
└──────┬───────┘
       │
 ┌─────┴──────────────┐
 │                     │
STT                   TTS
 │                     │
 └──── EVE reasoning ──┘
       (identity, memory, tools, automation)
```

Today, "EVE / Hermes backend" is two separately-owned systems reachable at different loopback ports on the same host (`eve-os/docs/physical-acceptance.md`): EVE API at `127.0.0.1:8000` (memory/identity, no conversation capability) and a Hermes API at `127.0.0.1:8642` (conversation runtime, contents undocumented outside its own repository). This app talks to whichever of those ends up exposing a conversation/voice surface — see `docs/backend-api.md` for the gap and the open decision on where that surface should live.

## Client architecture (this repository)

```
EVE/
├── App/            application entry point, root scene
├── Features/
│   ├── Voice/          push-to-talk main screen (idle → listening → processing → speaking)
│   ├── Conversation/   turn history view, backed by server state, local cache only for UX
│   ├── Settings/       server URL, pairing, permissions, diagnostics
│   └── Connection/     connection status indicator + reconnect logic
├── Services/
│   ├── Audio/          AVAudioSession session management, route/interruption handling
│   ├── API/            HTTP/WebSocket client, request/response models
│   ├── Speech/         on-device STT wrapper (Architecture B / hybrid — see voice-architecture.md)
│   └── Authentication/ Keychain-backed device credential, pairing flow
├── Models/         Codable wire models, local view state (not a memory system)
├── UI/             shared SwiftUI components, theme
├── Intents/        App Intents (Siri, Action Button, Shortcuts)
└── Resources/      localized strings (sv default, en scaffold), assets
```

`Features/` depends on `Services/`, never the reverse. `Services/Authentication` is the only place that touches the Keychain. `Services/API` is the only place that knows the wire protocol; `Features/Conversation` and `Features/Voice` consume typed models from `Models/`, not raw JSON.

### State machine

The voice UI is driven by one state enum shared across `Features/Voice` and `Features/Connection` (see `EVE/Models/VoiceSessionState.swift`):

```
idle → listening → processing → speaking → idle
                                     │
                                     └─ interrupted → listening
any state → disconnected (network loss)
any state → error (recoverable → idle, unrecoverable → disconnected)
```

This is the same list as the brief's UI-states requirement (§24) and doubles as the barge-in state (`interrupted`, §10). No hidden states: everything the user needs to understand about what EVE is doing is representable here.

### Source of truth

EVE/Hermes remains the source of truth for identity, memory, and conversation history. The client's local cache (recent turns, connection state, pairing metadata) exists only to make the UI responsive and to survive brief network loss; it is not a second copy of EVE's memory and is not treated as durable. See `docs/security.md` for exactly what is and is not persisted on-device.

## Open architecture decisions

These are unresolved as of this writing and are blocking Milestone 1+ (see `docs/roadmap.md`):

1. **Where does the conversation/voice surface live?** A new Hermes channel adapter (parallel to the WhatsApp bridge) vs. a small dedicated gateway service in front of Hermes. Needs a decision from whoever owns the Hermes deployment, since Hermes' source isn't visible from this project.
2. **Transport for streaming** — WebSocket vs. HTTP+SSE vs. WebRTC; see `docs/voice-architecture.md`.
3. **Where STT/TTS run** — server-side vs. on-device vs. hybrid; see `docs/voice-architecture.md`.
4. **Device pairing mechanics** — see `docs/security.md`.
