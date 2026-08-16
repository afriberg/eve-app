# EVE root CA certificate — required before building

`GatewayTrustEvaluator` (`EVE/Services/API/GatewayTrustEvaluator.swift`) pins every connection to the EVE Voice Gateway to a bundled certificate named `EVERootCA.cer` in this directory. **That file is intentionally not included in this repository** — it is generated per-deployment by `eve-os`'s `scripts/eve-gateway-tls-init.sh` and is specific to one owner's EVE instance; committing a real one here would mean nothing (there is no single "the" EVE root CA), and committing a fake one would be actively misleading.

Before building this app for real use:

1. On the EVE host, run `scripts/eve-gateway-tls-init.sh` (see `eve-os`'s `docs/deployment.md` and `docs/voice-gateway.md`, "TLS: local EVE CA").
2. Copy the root CA certificate it prints (`eve-root-ca.crt`, DER or PEM) into this directory as `EVERootCA.cer`.
3. Add it to the Xcode project (or re-run `xcodegen generate` — `project.yml`'s `sources: [EVE]` picks up any file placed under this folder automatically) and rebuild.

Without this file, `GatewayTrustEvaluator`'s initializer throws `rootCertificateNotBundled`, `GatewayEnvironment` falls back to the system trust store (which correctly and safely rejects the Gateway's private-CA certificate on every request — see that type's doc comment), and the app can never successfully reach the Gateway. This is deliberate fail-closed behavior, not a bug: the app must never silently trust an unpinned connection to something calling itself "the Gateway."
