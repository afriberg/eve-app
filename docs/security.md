# Security

## Principles

- No hardcoded API tokens, passwords, certificates, or private keys in this repository, ever — not even for development. Anything that looks like it should be a secret goes in Settings, backed by the Keychain.
- The backend is source of truth; the phone minimizes what it stores.
- Fail closed: if authentication, pairing, or the network is in a bad state, the app must not silently proceed as if it weren't.

## Network architecture (locked 2026-08-16)

EVE's production deployment is entirely loopback-bound today (`eve-os/docs/architecture.md`, `docs/deployment.md`, `docs/physical-acceptance.md`): EVE API at `127.0.0.1:8000`, Hermes API at `127.0.0.1:8642`, WhatsApp bridge at `127.0.0.1:3000`. Nothing is exposed to the internet, and there is no reverse proxy or TLS termination in front of any of it.

**Decision: reach the EVE Voice Gateway over Tailscale, with TLS layered on top — not either/or.**

```
iPhone → Tailscale → HTTPS/WSS → EVE Voice Gateway
```

Tailscale is the network boundary; it is explicitly not treated as a substitute for transport encryption. "It's already on WireGuard" is not a reason to serve plaintext HTTP — see TLS below. This matches the existing security posture (loopback-only, private-network-only) instead of requiring EVE to grow a public-facing surface and a hardened ingress before this project has even reached Milestone 2, and means the app talks to the same private-network address whether the user is home or away, simplifying the connection-status logic in `Features/Connection`. No public endpoint is exposed for v1.

This is the v1 default, not a permanent architectural lock-in: the client's `Services/API` layer talks to a configured base URL and never assumes VPN-specific behavior (no Tailscale SDK dependency, no hardcoded `*.ts.net` hostname handling). If a future decision moves to a proper public ingress with its own TLS termination, only the configured server URL and the pairing flow's discovery step change.

## TLS

All traffic between the app and the EVE Voice Gateway is TLS, full stop — including over the VPN, since "it's already on a private network" is not a reason to skip encryption for a channel carrying personal conversations and infrastructure control.

- **Termination:** at the EVE Voice Gateway (see `docs/architecture.md`, locked decision #1) — wherever that service ends up physically living (`docs/backend-api.md`, closing section). This repository does not implement or vendor a TLS terminator.
- **Hostname strategy:** the app connects to whatever hostname the user configures during pairing (see below) — a Tailscale MagicDNS name is the expected default (e.g. `eve.tailnet-name.ts.net`), not a hardcoded value.
- **Certificate handling:** standard system trust store validation (`URLSession` defaults). No custom trust evaluation, no accepting self-signed/invalid certificates, even in development — if local development needs TLS, use a real certificate (e.g. via Tailscale's built-in HTTPS certs, or a local CA the developer explicitly trusts at the OS level, never in app code).
- **Certificate pinning:** not implemented for v1. Revisit only if the network model changes to expose EVE beyond the VPN boundary, where pinning would defend against a compromised or malicious network path in a way that a private VPN-only design doesn't need as urgently. Pinning also has an operational cost (a botched pin update can lock out the only client), which needs to be weighed against the actual threat model before adopting it.

## Device enrollment (pairing) — locked 2026-08-16

Decision: **adopt device pairing with explicit owner approval**, request-initiated by the phone rather than pre-minted by the owner:

```
iPhone → pairing request → EVE owner approval → device credential → Keychain
```

Every paired device gets, at minimum:

- its own device ID
- its own credential (never a permanent, general-purpose API token shared across devices)
- a name/model label
- created and last-used timestamps
- independent revoke status

No such flow exists in `eve-os` or Hermes today (`docs/backend-api.md`) — both currently authenticate with one shared static token (`EVE_API_TOKEN`, `API_SERVER_KEY`). This is new, EVE-Voice-Gateway-owned work, needed before Milestone 1's acceptance criterion can be met for anything beyond a health check. It has two real, validated precedents to build on rather than a blank page:

1. **`eve-os`'s own owner-approval pattern** (`eve-os/docs/self-administration.md`): the server never durably holds anything more sensitive than what it needs to verify a credential; the owner presents a raw secret only at the moment of approval.
2. **Hermes' DM-pairing system** (`gateway/pairing.py` in `nousresearch/hermes-agent`): a full, shipping implementation of almost exactly this shape — 8-character cryptographically random codes, salted-hash storage (a code is never held in plaintext), 1-hour expiry, per-principal rate limiting, lockout after 5 failed approval attempts, CLI-driven owner approval, clean revocation. It authorizes messaging-platform user IDs, not iPhones, so the Gateway can't call it directly — but its threat model and implementation choices (hash-not-plaintext codes, short TTL, rate limiting, lockout, explicit revoke) are exactly what a new Gateway-owned device-pairing store should mirror.

Proposed flow, refining the locked shape above:

```
EVE Voice Gateway
     │  iPhone sends a pairing request (device name/model, a device-generated
     │  keypair's public key)
     ▼
Gateway holds the request pending
     │  owner approves (mirroring gateway/pairing.py's CLI-approval model,
     │  or an equivalent EVE owner-approval surface)
     ▼
Gateway issues a device credential bound to that device
     ▼
iPhone stores the device credential in Keychain
```

The backend (Gateway) must be able to: **enumerate registered devices** (name/model, created/last-used), **revoke a specific device's credential** independently of any other device or of the shared Hermes/EVE tokens it holds internally, and **expire an unapproved pairing request quickly** (minutes, not days).

The device-side keypair (generated on-device with `SecKey`/Secure Enclave where available, private key never leaving the device) lets the credential exchange avoid ever transmitting a long-lived secret over the wire in plaintext during pairing — the Gateway can issue a credential bound to signatures from that key rather than a bearer string alone. This is a proposed refinement, not a requirement for a functioning v1 pairing flow: a simple issued bearer-style device token, stored only in Keychain, is an acceptable first cut and is what Milestone 1 should target if Secure Enclave key-binding turns out to add Gateway complexity disproportionate to the risk it closes.

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
