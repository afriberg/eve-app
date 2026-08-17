import Foundation

/// The subset of `GatewayWebSocketClient` a conversation view model needs —
/// exists purely so `ConversationViewModel` can be unit tested against a
/// fake, the same reason `DevicePairingService` is tested via
/// `MockURLProtocol` rather than a live network: `URLSessionWebSocketTask`
/// has no equivalent request-interception seam, so a protocol boundary is
/// the seam instead.
protocol ConversationTransport: Sendable {
    func connect(baseURL: URL, ticket: String) async throws
    func sendConversationMessage(_ text: String) async throws
    func receiveConversationEvent() async throws -> ConversationEvent
    func sendClose() async throws
    func close() async
}

extension GatewayWebSocketClient: ConversationTransport {}
