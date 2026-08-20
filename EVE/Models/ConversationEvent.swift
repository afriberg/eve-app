import Foundation

/// A synthesized spoken reply attached to a `conversation.response` (GW-M3 —
/// eve-os `eve/gateway/tts.py`, "GW-M3 — Voice"). `dataURL` is a complete
/// `data:audio/wav;base64,...` URL — the whole utterance, not a stream
/// (streaming voice is GW-M4, not implemented here).
struct ConversationAudio: Equatable {
    let dataURL: String
    let mimeType: String
}

/// One decoded message from the Gateway's `/v1/ws` conversation protocol
/// (GW-M2/GW-M3 — eve-os `docs/voice-gateway.md`, `eve/gateway/api.py`).
/// Mirrors the envelope's `type` field; `.response`/`.error` carry the parts
/// of `data` this client actually needs, nothing more.
enum ConversationEvent: Equatable {
    case sessionStarted(sessionId: String)
    /// `audio` is absent when GW-M3 voice is disabled on the Gateway, or
    /// when synthesis failed there — the Gateway always degrades to
    /// text-only rather than losing the turn (eve/gateway/api.py), and this
    /// client must treat a missing `audio` the same way, not as an error.
    case response(text: String, audio: ConversationAudio?)
    case error(code: String, message: String)
    case sessionClosed
    /// A message type this client doesn't recognize yet — surfaced rather
    /// than silently dropped, but deliberately not fatal: forward
    /// compatibility with server-side additions this client hasn't been
    /// taught about yet.
    case unknown(type: String)
}
