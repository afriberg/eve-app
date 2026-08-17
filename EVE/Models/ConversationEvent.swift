import Foundation

/// One decoded message from the Gateway's `/v1/ws` conversation protocol
/// (GW-M2 — eve-os `docs/voice-gateway.md`, `eve/gateway/api.py`). Mirrors
/// the envelope's `type` field; `.response`/`.error` carry the parts of
/// `data` this client actually needs, nothing more.
enum ConversationEvent: Equatable {
    case sessionStarted(sessionId: String)
    case response(text: String)
    case error(code: String, message: String)
    case sessionClosed
    /// A message type this client doesn't recognize yet (e.g. a future
    /// GW-M3+ voice event) — surfaced rather than silently dropped, but
    /// deliberately not fatal: forward compatibility with server-side
    /// additions this client hasn't been taught about yet.
    case unknown(type: String)
}
