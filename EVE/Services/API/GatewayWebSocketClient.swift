import Foundation

/// WSS client for the Gateway's `/v1/ws` session-lifecycle envelope (GW-M1)
/// and GW-M2's `conversation.message`/`conversation.response` text
/// exchange — see docs/voice-architecture.md and eve-os
/// `docs/voice-gateway.md`. Uses the same pinned `URLSession` as
/// `GatewayAPIClient` (`URLSessionWebSocketTask` shares its owning
/// session's delegate, so `GatewayTrustEvaluator` covers this transport
/// too). Streaming/voice (GW-M3+) is not implemented here.
actor GatewayWebSocketClient {
    enum ClientError: Error {
        case invalidURL
        case notConnected
        case malformedMessage
    }

    struct InboundEnvelope: Decodable {
        let v: Int
        let type: String
    }

    private struct OutboundSessionClose: Encodable {
        let v: Int
        let type: String
    }

    private struct ConversationMessagePayload: Encodable {
        let text: String
    }

    private struct OutboundConversationMessage: Encodable {
        let v: Int
        let type: String
        let data: ConversationMessagePayload
    }

    private struct SessionStartedPayload: Decodable {
        let sessionId: String
    }

    /// `keyDecodingStrategy = .convertFromSnakeCase` (below) maps the wire's
    /// `data_url`/`mime_type` (eve-os `eve/gateway/tts.py`) onto these.
    private struct AudioPayload: Decodable {
        let dataUrl: String
        let mimeType: String
    }

    private struct ConversationResponsePayload: Decodable {
        let text: String
        let audio: AudioPayload?
    }

    private struct ErrorPayload: Decodable {
        let code: String
        let message: String
    }

    /// Decodes an inbound envelope's `data` object once its `type` is
    /// already known, reusing the same raw bytes `InboundEnvelope` decoded.
    private struct PayloadEnvelope<Payload: Decodable>: Decodable {
        let data: Payload
    }

    private static var payloadDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(session: URLSession) {
        self.session = session
    }

    /// `baseURL` is the Gateway's `https://` base — this rewrites the scheme
    /// to `wss://` and targets `/v1/ws`, matching eve-os `eve/gateway/api.py`.
    func connect(baseURL: URL, ticket: String) throws {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/v1/ws"
        components.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        guard let url = components.url else { throw ClientError.invalidURL }

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    func receiveOne() async throws -> InboundEnvelope {
        guard let task else { throw ClientError.notConnected }
        let message = try await task.receive()
        switch message {
        case .data(let data):
            return try JSONDecoder().decode(InboundEnvelope.self, from: data)
        case .string(let text):
            return try JSONDecoder().decode(InboundEnvelope.self, from: Data(text.utf8))
        @unknown default:
            throw ClientError.notConnected
        }
    }

    func sendClose() async throws {
        guard let task else { throw ClientError.notConnected }
        let envelope = OutboundSessionClose(v: 1, type: "session.close")
        let data = try JSONEncoder().encode(envelope)
        try await task.send(.data(data))
    }

    /// GW-M2: send one text turn. Non-streaming — the Gateway replies with
    /// exactly one `conversation.response` (or `error`), never a partial
    /// stream; see eve-os `eve/gateway/hermes_client.py`.
    func sendConversationMessage(_ text: String) async throws {
        guard let task else { throw ClientError.notConnected }
        let envelope = OutboundConversationMessage(
            v: 1, type: "conversation.message", data: ConversationMessagePayload(text: text)
        )
        let data = try JSONEncoder().encode(envelope)
        try await task.send(.data(data))
    }

    /// Decodes one inbound frame into a `ConversationEvent`, dispatching on
    /// its `type`. An unrecognized `type` becomes `.unknown` rather than a
    /// thrown error — see `ConversationEvent.unknown`'s doc comment.
    func receiveConversationEvent() async throws -> ConversationEvent {
        guard let task else { throw ClientError.notConnected }
        let message = try await task.receive()
        let raw: Data
        switch message {
        case .data(let data): raw = data
        case .string(let text): raw = Data(text.utf8)
        @unknown default: throw ClientError.notConnected
        }

        let envelope = try JSONDecoder().decode(InboundEnvelope.self, from: raw)
        switch envelope.type {
        case "session.started":
            let payload = try Self.payloadDecoder.decode(PayloadEnvelope<SessionStartedPayload>.self, from: raw)
            return .sessionStarted(sessionId: payload.data.sessionId)
        case "conversation.response":
            let payload = try Self.payloadDecoder.decode(PayloadEnvelope<ConversationResponsePayload>.self, from: raw)
            let audio = payload.data.audio.map { ConversationAudio(dataURL: $0.dataUrl, mimeType: $0.mimeType) }
            return .response(text: payload.data.text, audio: audio)
        case "error":
            let payload = try Self.payloadDecoder.decode(PayloadEnvelope<ErrorPayload>.self, from: raw)
            return .error(code: payload.data.code, message: payload.data.message)
        case "session.closed":
            return .sessionClosed
        default:
            return .unknown(type: envelope.type)
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
