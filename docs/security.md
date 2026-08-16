# Security

## Principles

- No hardcoded API tokens, passwords, certificates, or private keys in this repository, ever — not even for development. Anything that looks like it should be a secret goes in Settings, backed by the Keychain.
- The backend is source of truth; the phone minimizes what it stores.
- Fail closed: if authentication, pairing, or the network is in a bad state, the app must not silently proceed as if it weren't.

## Network architecture (revised 2026-08-16 — local-only, WireGuard)

**Superseded:** an earlier draft of this document specified Tailscale as the network transport, with Tailscale-provisioned public-CA certificates. Both are rejected — EVE's voice infrastructure is a hard requirement to stay fully local/private: no Tailscale, no public DNS, no Let's Encrypt or any public certificate authority, no cloud relay, no public internet exposure of the Gateway at all.

EVE's production deployment is entirely loopback-bound today (`eve-os/docs/architecture.md`, `docs/deployment.md`, `docs/physical-acceptance.md`): EVE API at `127.0.0.1:8000`, Hermes API at `127.0.0.1:8642`, WhatsApp bridge at `127.0.0.1:3000`. Nothing is exposed to the internet, and there is no reverse proxy or public TLS termination in front of any of it.

**Decision: reach the EVE Voice Gateway over the owner's existing WireGuard VPN — not a new VPN this project introduces — with TLS layered on top.**

```
iPhone → existing WireGuard VPN → home network, private address → HTTPS/WSS → EVE Voice Gateway
```

WireGuard is the network boundary; it is explicitly not treated as a substitute for transport encryption or for application-level authentication. "It's already on WireGuard" is not a reason to serve plaintext HTTP, and WireGuard membership is never treated as proof of who's connecting — the Gateway still independently authenticates the specific paired device (`docs/security.md` §"Device enrollment" below) regardless of network path. This matches the existing security posture (loopback-only, private-network-only) instead of requiring EVE to grow a public-facing surface and a hardened ingress before this project has even reached Milestone 2, and means the app talks to the same private-network address whether the user is home or away, simplifying the connection-status logic in `Features/Connection`. No public endpoint is exposed for v1, and none is planned.

This app does not bundle a WireGuard SDK or implement any VPN logic itself — WireGuard connectivity is provided entirely by the owner's existing, separately-configured VPN client on the phone, outside this app's scope. The client's `Services/API` layer only ever talks to a configured base URL (a private WireGuard-reachable address) and has no VPN-specific code path; if the network transport ever changes, only the configured server URL changes, not the app's architecture.

## TLS

All traffic between the app and the EVE Voice Gateway is TLS, full stop — including over the VPN, since "it's already on a private network" is not a reason to skip encryption for a channel carrying personal conversations and infrastructure control. TLS validation is never disabled, and the app never falls back to plaintext HTTP/WS.

- **Termination:** directly in the EVE Voice Gateway process (`eve-os/docs/voice-gateway.md`, "TLS: local EVE CA") — no reverse proxy, since with no public CA involved there's no automatic-renewal problem a proxy would exist to solve.
- **Certificate authority:** a private, EVE-owner-controlled root CA — not any publicly trusted CA, and not the system trust store. The Gateway's server certificate is a leaf signed by this CA, with an IP SAN matching its WireGuard-bound address (no DNS dependency, internal or public).
- **iOS trust model — pinning is required, not optional:** the EVE root CA's public certificate ships as a bundled resource in this app (`EVE/Resources/`). `Services/API` supplies a custom server-trust evaluator (`URLSessionDelegate`/`URLSessionWebSocketDelegate`, evaluating the presented chain against the bundled root via `SecTrustSetAnchorCertificates`) instead of relying on the system trust store, which correctly has no reason to trust a private CA. A connection whose certificate doesn't chain to the bundled root fails closed — never a silent fallback to "accept anyway."
- **Why pin to the root, not the leaf:** the Gateway's leaf certificate is expected to be renewed periodically (`eve-os/docs/voice-gateway.md`); pinning to the CA root instead of the leaf means routine leaf renewal needs zero app changes. Only a root CA rotation (rare — compromise or a deliberate refresh) requires shipping a new app build with an updated bundled root, and that's treated as a real, documented event, not assumed away.
- **Hostname strategy:** the app connects to whatever private IP/address the user configures during pairing setup (Settings → EVE Server) — no hardcoded value, no assumption of any DNS resolution being available.

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
