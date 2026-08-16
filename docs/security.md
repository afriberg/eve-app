# Security

## Principles

- No hardcoded API tokens, passwords, certificates, or private keys in this repository, ever — not even for development. Anything that looks like it should be a secret goes in Settings, backed by the Keychain.
- The backend is source of truth; the phone minimizes what it stores.
- Fail closed: if authentication, pairing, or the network is in a bad state, the app must not silently proceed as if it weren't.

## Network architecture

EVE's production deployment is entirely loopback-bound today (`eve-os/docs/architecture.md`, `docs/deployment.md`, `docs/physical-acceptance.md`): EVE API at `127.0.0.1:8000`, Hermes API at `127.0.0.1:8642`, WhatsApp bridge at `127.0.0.1:3000`. Nothing is exposed to the internet, and there is no reverse proxy or TLS termination in front of any of it.

**v1 recommendation: reach EVE over Tailscale (or an equivalent WireGuard-based VPN).**

```
iPhone → Tailscale → home network → EVE/Hermes
```

This matches the existing security posture (loopback-only, private-network-only) instead of requiring EVE to grow a public-facing surface, TLS certificates, and a hardened ingress before this project has even reached Milestone 2. It also means the app talks to the same private-network address whether the user is home or away, which simplifies the connection-status logic in `Features/Connection`.

This is a v1 default, not an architectural lock-in: the client's `Services/API` layer talks to a configured base URL and never assumes VPN-specific behavior (no Tailscale SDK dependency, no hardcoded `*.ts.net` hostname handling). If a future decision moves to a proper public ingress with its own TLS termination, only the configured server URL and the pairing flow's discovery step change.

## TLS

All traffic between the app and the backend is TLS, full stop — including over the VPN, since "it's already on a private network" is not a reason to skip encryption for a channel carrying personal conversations and infrastructure control.

- **Termination:** wherever the backend's HTTP/WebSocket surface is added (see `docs/backend-api.md`, gap items 1-2), TLS terminates there. This repository does not implement or vendor a TLS terminator.
- **Hostname strategy:** the app connects to whatever hostname the user configures during pairing (see below) — a Tailscale MagicDNS name is the expected default (e.g. `eve.tailnet-name.ts.net`), not a hardcoded value.
- **Certificate handling:** standard system trust store validation (`URLSession` defaults). No custom trust evaluation, no accepting self-signed/invalid certificates, even in development — if local development needs TLS, use a real certificate (e.g. via Tailscale's built-in HTTPS certs, or a local CA the developer explicitly trusts at the OS level, never in app code).
- **Certificate pinning:** not implemented for v1. Revisit only if the network model changes to expose EVE beyond the VPN boundary, where pinning would defend against a compromised or malicious network path in a way that a private VPN-only design doesn't need as urgently. Pinning also has an operational cost (a botched pin update can lock out the only client), which needs to be weighed against the actual threat model before adopting it.

## Device enrollment (pairing)

No such flow exists in `eve-os` today (`docs/backend-api.md`, gap item 5) — the entire backend currently authenticates with one shared static token. This section is a proposed design; implementation is backend work outside this repository, needed before Milestone 1's acceptance criterion can be met for anything beyond a health check.

```
EVE backend
     │  owner generates a one-time pairing token (short TTL, single use)
     ▼
iPhone
     │  user enters/scans the pairing token in Settings → EVE Server
     ▼
device registration request (pairing token + device-generated keypair's public key)
     ▼
EVE backend validates the pairing token, issues a device credential bound to that device
     ▼
iPhone stores the device credential in Keychain; discards the pairing token
```

This closely mirrors the pattern `eve-os` already uses for owner-approval of high-risk mutations (`eve-os/docs/self-administration.md`): the server never needs to durably hold anything more sensitive than what it needs to verify a device credential, and a compromised device credential is scoped to one device rather than compromising the single shared `EVE_API_TOKEN` used everywhere else. Concretely, the backend should be able to:

- **Enumerate registered devices** (name, platform, first-seen, last-seen).
- **Revoke a specific device's credential** without affecting any other device or the shared API token used by other integrations (Hermes itself, etc.).
- **Expire pairing tokens quickly** (minutes, not days) so a leaked pairing token has a small window of usefulness.

The device-side keypair (generated on-device with `SecKey`/Secure Enclave where available, private key never leaving the device) lets the credential exchange avoid ever transmitting a long-lived secret over the wire in plaintext during pairing — the backend can issue a credential that's bound to signatures from that key rather than a bearer string alone. This is a proposed refinement, not a requirement for a functioning v1 pairing flow (a simple issued bearer-style device token, stored only in Keychain, is an acceptable first cut and is what Milestone 1 should target if Secure Enclave key-binding turns out to add backend complexity disproportionate to the risk it closes).

### Keychain usage

`Services/Authentication/KeychainStore` is the only code in this repository allowed to read or write Keychain items. Stored items:

- the device credential issued at pairing (`kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never synced via iCloud Keychain, since a credential bound to *this* device should not silently reappear on another device)
- nothing else. No conversation content, no memory content, no raw pairing tokens (discarded immediately after exchange, per the flow above).

## Privacy — what stays on the phone

Per the brief's principle (minimize local storage of private data):

**Not stored persistently, ever:**
- raw microphone recordings (audio is only ever transient, in-memory, for the duration of a turn)
- EVE's memory/knowledge base (the app is a client, never a cache of the backend's durable memory)
- infrastructure credentials (Home Assistant, Proxmox, etc. — those stay entirely server-side and are never sent to or rendered by this app)

**Stored, bounded:**
- a small local cache of recent conversation turns for UX responsiveness (§ "Conversation history" below) — bounded size, evictable, never treated as authoritative
- connection/session metadata (server URL, last-connected timestamp) — not sensitive
- device credential — Keychain only, see above

## Conversation history

EVE/Hermes backend is the source of truth for conversation history — this app must not attempt to reconstruct or duplicate EVE's memory system locally (per the project's core design principle). The app may display a local cache of recent turns purely for UX (instant scroll-back without a network round trip, smooth reconnect experience), clearly bounded and understood by the client code as disposable: if the cache is cleared, nothing about the user's relationship with EVE is lost, because none of it lived here.

## Logging

Structured logging covers connection events, session lifecycle, latency (see `docs/roadmap.md` §25 metrics), and audio-subsystem/API errors. Logging must never include: authentication secrets, device credentials, pairing tokens, or full conversation transcripts. Error logs may include enough of a request (e.g., endpoint, status code, session id) to debug a private, on-device-only deployment without including the private content of what was said.
