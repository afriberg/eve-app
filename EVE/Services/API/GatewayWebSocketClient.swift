import Foundation

/// WSS client foundation for GW-M1: connects using a single-use ticket
/// (minted via `GatewayAPIClient.createSession()`) and exchanges only the
/// session-lifecycle envelope. Conversation streaming is GW-M2+ — see
/// docs/voice-architecture.md and eve-os `docs/voice-gateway.md`. Uses the
/// same pinned `URLSession` as `GatewayAPIClient`
/// (`URLSessionWebSocketTask` shares its owning session's delegate, so
/// `GatewayTrustEvaluator` covers this transport too).
actor GatewayWebSocketClient {
    enum ClientError: Error {
        case invalidURL
        case notConnected
    }

    struct InboundEnvelope: Decodable {
        let v: Int
        let type: String
    }

    private struct OutboundEnvelope: Encodable {
        let v: Int
        let type: String
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
        let envelope = OutboundEnvelope(v: 1, type: "session.close")
        let data = try JSONEncoder().encode(envelope)
        try await task.send(.data(data))
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
