# Architecture

## Design principle

The app is EVE's native interface on Apple platforms. It is not EVE.

```
iOS App
    │
    │ interface (UI, mic, speaker, transport, local session state)
    ▼
EVE Voice Gateway
    │
    │ transport, sessions, streaming, interruption, device auth
    ▼
Hermes / EVE
    │
    ├── identity
    ├── reasoning / LLM routing
    ├── memory
    ├── tools
    ├── automation
    ├── infrastructure knowledge
    ├── TTS / STT (already built, pluggable — see docs/backend-api.md)
    └── integrations (Home Assistant, WhatsApp, ...)
```

Every architectural decision in this document is evaluated against one question: does this keep reasoning, memory, and tool authority on the server, and the phone thin? If a design pushes any of those onto the device, it is wrong regardless of how much it simplifies the client.

## System diagram (locked 2026-08-16)

```
┌──────────────────────┐
│      EVE iOS App     │
│                      │
│ SwiftUI              │
│ Apple STT            │
│ AVFoundation         │
│ App Intents          │
└──────────┬───────────┘
           │
     HTTPS / WSS
           │
       Tailscale
           │
┌──────────▼───────────┐
│   EVE Voice Gateway  │
│                      │
│ Authentication       │
│ Device pairing       │
│ Voice sessions       │
│ Streaming/events     │
│ Interruptions        │
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│      Hermes/EVE      │
│                      │
│ Reasoning / LLM      │
│ Memory               │
│ Tools                │
│ Home Assistant       │
│ Automation           │
│ TTS/STT              │
└──────────────────────┘
```

The gateway is a **dedicated, versioned service between the app and Hermes — not a new Hermes channel adapter.** The iOS client never speaks Hermes' internal protocol or holds Hermes' shared `API_SERVER_KEY`; the gateway holds that one credential and exposes a stable, mobile-appropriate API instead. This was an open question in the original discovery pass; it's now a locked decision (§ below) after weighing it against the alternative of a new built-in Hermes platform adapter (`gateway/platforms/ADDING_A_PLATFORM.md` in the Hermes source documents exactly how that alternative would work) — a channel adapter would couple this app tightly to Hermes' internal session/platform model, which is Hermes' business to evolve, not this app's.

Concretely: EVE API stays at `127.0.0.1:8000` (memory/identity, unchanged), Hermes' own API stays at `127.0.0.1:8642` (confirmed via `nousresearch/hermes-agent`, `gateway/platforms/api_server.py` — see `docs/backend-api.md` for exactly what it already exposes), and the EVE Voice Gateway is a new component that talks to both, sitting between the phone and this pair. Where the gateway's code should physically live (a new service in `eve-os`, or its own repository) is the next open decision — see `docs/backend-api.md`.

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

## Architecture decisions (locked 2026-08-16)

Made by the project owner after the Milestone 0 discovery pass, including a direct read of Hermes' actual source (`nousresearch/hermes-agent` — see `docs/backend-api.md`):

1. **Dedicated EVE Voice Gateway in front of Hermes, not a Hermes channel adapter.** The iOS client needs a stable, versioned API for sessions, streaming, interruption, auth, and future Apple integrations — it should not couple to Hermes' internal channel model. Flow: `EVE iOS App → EVE Voice Gateway → Hermes/EVE`. Hermes remains the agent/runtime; the gateway is the transport/session layer.
2. **On-device STT as the primary track for v1.** Lower Pi load, less bandwidth, better privacy; the app transcribes locally and sends text, receiving text/audio back. The protocol still abstracts STT (see `docs/voice-architecture.md`) so server-side streaming audio (Hermes already does this in production for other channels — see `docs/backend-api.md`) can be added later without a protocol redesign; it is not locked to text-only.
3. **Device pairing with owner approval.** `iPhone → pairing request → EVE owner approval → device credential → Keychain`. Every device gets its own ID, its own credential, a name/model, created/last-used timestamps, and independent revoke status. No permanent, general-purpose API token ships in the app — a compromised phone can be revoked individually. See `docs/security.md` for the full flow.
4. **Tailscale + TLS, layered, not either/or.** `iPhone → Tailscale → HTTPS/WSS → EVE Voice Gateway`. Tailscale is the network boundary; TLS runs on top of it regardless — plaintext HTTP over WireGuard was explicitly rejected. No public endpoint for v1. See `docs/security.md`.

**Still open**, and the next thing to resolve before Milestone 1 implementation starts: where the EVE Voice Gateway's code physically lives — a new service alongside the existing EVE API in `eve-os` (this project's default per its engineering principles: backend changes belong in `eve-os`), or its own repository. See `docs/backend-api.md`, closing section.
