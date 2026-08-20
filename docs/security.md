# Security

## Principles

- No hardcoded API tokens, passwords, certificates, or private keys in this repository, ever — not even for development. Anything that looks like it should be a secret goes in Settings, backed by the Keychain.
- The backend is source of truth; the phone minimizes what it stores.
- Fail closed: if authentication, pairing, or the network is in a bad state, the app must not silently proceed as if it weren't.

## Network architecture (revised 2026-08-19 — local-only, home LAN + WireGuard)

**Superseded:** an earlier draft of this document specified Tailscale as the network transport, with Tailscale-provisioned public-CA certificates. Both are rejected — EVE's voice infrastructure is a hard requirement to stay fully local/private: no Tailscale, no public DNS, no Let's Encrypt or any public certificate authority, no cloud relay, no public internet exposure of the Gateway at all.

**Also superseded (revised again after GW-M1 physical acceptance, 2026-08-18):** an earlier version of this section described the Gateway as reachable only through a "WireGuard interface," implying a tunnel-only address distinct from the home LAN. Physical testing showed this was a wrong assumption about the owner's actual network: the owner's WireGuard setup routes into the same home subnet the Gateway is bound to, rather than assigning a separate tunnel-only address — so there is only ever one address to reach, not two.

EVE's production deployment is entirely loopback-bound today (`eve-os/docs/architecture.md`, `docs/deployment.md`, `docs/physical-acceptance.md`): EVE API at `127.0.0.1:8000`, Hermes API at `127.0.0.1:8642`, WhatsApp bridge at `127.0.0.1:3000`. Nothing is exposed to the internet, and there is no reverse proxy or public TLS termination in front of any of it. The Gateway is a deliberate, narrow exception: the first non-loopback listener on the host, bound to its home-LAN address (`eve-os` `docs/voice-gateway.md`, "Network and deployment design").

**Decision: reach the EVE Voice Gateway at the host's home-LAN address — directly when on that LAN, or through the owner's existing WireGuard VPN when away (not a new VPN this project introduces) — with TLS layered on top either way.**

```
iPhone → home LAN, directly — or existing WireGuard VPN (same address either way) → HTTPS/WSS → EVE Voice Gateway
```

Network reachability (LAN or WireGuard) is explicitly not treated as a substitute for transport encryption or for application-level authentication. "It's already on the home network" is not a reason to serve plaintext HTTP, and reachability is never treated as proof of who's connecting — the Gateway still independently authenticates the specific paired device (`docs/security.md` §"Device enrollment" below) regardless of network path. This matches the existing security posture (loopback-only-except-for-this-one-narrow-exception, private-network-only) instead of requiring EVE to grow a public-facing surface and a hardened ingress before this project has even reached Milestone 2, and means the app talks to the same private-network address whether the user is home or away, simplifying the connection-status logic in `Features/Connection`. No public endpoint is exposed for v1, and none is planned.

This app does not bundle a WireGuard SDK or implement any VPN logic itself — WireGuard connectivity, when used, is provided entirely by the owner's existing, separately-configured VPN client on the phone, outside this app's scope. The client's `Services/API` layer only ever talks to a configured base URL (the Gateway's private home-LAN address) and has no VPN-specific code path; if the network transport ever changes, only the configured server URL changes, not the app's architecture.

## TLS

All traffic between the app and the EVE Voice Gateway is TLS, full stop — including over the VPN, since "it's already on a private network" is not a reason to skip encryption for a channel carrying personal conversations and infrastructure control. TLS validation is never disabled, and the app never falls back to plaintext HTTP/WS.

- **Termination:** directly in the EVE Voice Gateway process (`eve-os/docs/voice-gateway.md`, "TLS: local EVE CA") — no reverse proxy, since with no public CA involved there's no automatic-renewal problem a proxy would exist to solve.
- **Certificate authority:** a private, EVE-owner-controlled root CA — not any publicly trusted CA, and not the system trust store. The Gateway's server certificate is a leaf signed by this CA, with an IP SAN matching its home-LAN bind address (no DNS dependency, internal or public) — reachable that way whether the phone is on the LAN directly or via WireGuard, since both resolve to the same address (see "Network architecture" above).
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

**Implemented flow** (`eve-os` `eve/gateway/api.py`, `credential_claims.py` — this superseded an earlier two-step sketch once GW-M1 implementation surfaced a real gap: the owner approving and the phone that asked to be paired are different principals, so the credential can't just come back in the approval response):

```
iPhone  → POST /v1/pairing/request (device name/model)             → Gateway (pending)
Owner   → POST /v1/pairing/{id}/approve (X-EVE-Owner-Approval)      → Gateway mints credential, holds it in memory
iPhone  → POST /v1/pairing/{id}/claim (no auth — request_id is the  → credential → Keychain
           proof of continuity, polled until it succeeds)
```

`DevicePairingService` implements exactly this: `requestPairing(deviceName:deviceModel:)` for the first call, `claim(requestId:)` for the third, with `PairingViewModel` owning a bounded poll loop (attempts every few seconds, gives up after ~2 minutes and lets the user retry) between step 2 finishing (out of band, currently CLI/`curl`-only on the Gateway side) and step 3 succeeding. `.notYetApproved` (mapped from the Gateway's 404 while nothing has been approved yet) is the expected, routine result while waiting — never surfaced to the user as an error.

The backend (Gateway) can: **enumerate registered devices** (`GET /v1/devices`, name/model, created/last-used), **revoke a specific device's credential** (`POST /v1/devices/{id}/revoke`) independently of any other device or of the shared Hermes/EVE tokens it holds internally, and **expire an unapproved pairing request** (`GATEWAY_PAIRING_REQUEST_TTL_SECONDS`, default 1 hour).

**Not implemented in GW-M1:** the device-generated keypair refinement described in the original design (Secure Enclave-bound signatures instead of a bearer string alone). GW-M1 issues a simple, high-entropy bearer credential — `evgw_<token_id>.<secret>`, only ever transmitted once, over the pinned TLS connection, at claim time — which the original design already flagged as an acceptable first cut. Revisit only if the bearer-credential threat model proves insufficient in practice.

### Keychain usage

`Services/Authentication/KeychainStore` is the only code in this repository allowed to read or write Keychain items. Stored items:

- the device credential issued at pairing (`kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never synced via iCloud Keychain, since a credential bound to *this* device should not silently reappear on another device)
- nothing else. No conversation content, no memory content, no raw pairing tokens (discarded immediately after exchange, per the flow above).

## Privacy — what stays on the phone

Per the brief's principle (minimize local storage of private data):

**Not stored persistently, ever:**
- raw microphone recordings (audio is only ever transient, in-memory, for the duration of a turn)
- EVE's memory/knowledge base (the app is a client, never a cache of the backend's durable memory)
- infrastructure credentials (home-automation, virtualization/hosting, etc. — those stay entirely server-side and are never sent to or rendered by this app)

**Stored, bounded:**
- a small local cache of recent conversation turns for UX responsiveness (§ "Conversation history" below) — bounded size, evictable, never treated as authoritative
- connection/session metadata (server URL, last-connected timestamp) — not sensitive
- device credential — Keychain only, see above

## Conversation history

EVE/Hermes backend is the source of truth for conversation history — this app must not attempt to reconstruct or duplicate EVE's memory system locally (per the project's core design principle). The app may display a local cache of recent turns purely for UX (instant scroll-back without a network round trip, smooth reconnect experience), clearly bounded and understood by the client code as disposable: if the cache is cleared, nothing about the user's relationship with EVE is lost, because none of it lived here.

## Logging

Structured logging covers connection events, session lifecycle, latency (see `docs/roadmap.md` §25 metrics), and audio-subsystem/API errors. Logging must never include: authentication secrets, device credentials, pairing tokens, or full conversation transcripts. Error logs may include enough of a request (e.g., endpoint, status code, session id) to debug a private, on-device-only deployment without including the private content of what was said.
