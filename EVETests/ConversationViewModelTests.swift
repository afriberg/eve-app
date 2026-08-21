import XCTest
@testable import EVE

/// `GatewayWebSocketClient` has no `URLProtocol`-style interception seam
/// (unlike `GatewayAPIClient`, tested via `MockURLProtocol`), so
/// `ConversationTransport` exists specifically to make this testable —
/// see that protocol's doc comment.
final class FakeConversationTransport: ConversationTransport, @unchecked Sendable {
    enum ReceiveScript {
        case event(ConversationEvent)
        case error(Error)
    }

    enum FakeError: Error {
        case connectFailed
        case scriptExhausted
    }

    var connectError: Error?
    /// Throws once (decrementing) before falling through to `connectError`'s
    /// normal (persistent) behavior — lets a test simulate a transient
    /// connect failure that succeeds on retry, distinct from `connectError`
    /// alone, which fails every call.
    var connectFailureCount = 0
    var sendError: Error?
    var receiveScript: [ReceiveScript] = []
    private(set) var sentMessages: [String] = []
    private(set) var connectCallCount = 0
    private(set) var closeCallCount = 0

    func connect(baseURL: URL, ticket: String) async throws {
        connectCallCount += 1
        if connectFailureCount > 0 {
            connectFailureCount -= 1
            throw connectError ?? FakeError.connectFailed
        }
        if let connectError { throw connectError }
    }

    func sendConversationMessage(_ text: String) async throws {
        if let sendError { throw sendError }
        sentMessages.append(text)
    }

    func receiveConversationEvent() async throws -> ConversationEvent {
        guard !receiveScript.isEmpty else { throw FakeError.scriptExhausted }
        switch receiveScript.removeFirst() {
        case .event(let event): return event
        case .error(let error): throw error
        }
    }

    func sendClose() async throws {}

    func close() async {
        closeCallCount += 1
    }
}

@MainActor
final class ConversationViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeConfiguredClient() async -> GatewayAPIClient {
        let client = GatewayAPIClient(session: MockURLProtocol.makeSession())
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        await client.setDeviceCredential("evgw_abc.def")
        MockURLProtocol.stubs["POST /v1/sessions"] = .init(
            status: 200,
            body: Data(
                #"{"session_id":"s1","ticket":"tk1","expires_at":"2026-08-16T00:00:30Z"}"#.utf8
            )
        )
        return client
    }

    func testConnectFailsWithoutAConfiguredServer() async {
        let unconfiguredClient = GatewayAPIClient(session: MockURLProtocol.makeSession())
        let transport = FakeConversationTransport()
        let viewModel = ConversationViewModel(apiClient: unconfiguredClient, transport: transport)

        await viewModel.connect()

        guard case .failed = viewModel.connectionState else {
            return XCTFail("expected .failed, got \(viewModel.connectionState)")
        }
        XCTAssertEqual(transport.connectCallCount, 0)
    }

    func testConnectBecomesConnectedOnSessionStarted() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [.event(.sessionStarted(sessionId: "s1"))]
        let viewModel = ConversationViewModel(apiClient: client, transport: transport)

        await viewModel.connect()

        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(transport.connectCallCount, 1)
    }

    func testConnectFailsWhenTransportThrows() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.connectError = FakeConversationTransport.FakeError.connectFailed
        let viewModel = ConversationViewModel(apiClient: client, transport: transport)

        await viewModel.connect()

        guard case .failed = viewModel.connectionState else {
            return XCTFail("expected .failed, got \(viewModel.connectionState)")
        }
    }

    func testSendAppendsUserTurnThenEveResponseTurn() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [
            .event(.sessionStarted(sessionId: "s1")),
            .event(.response(text: "Hej! Hur mår du?", audio: nil)),
        ]
        let viewModel = ConversationViewModel(apiClient: client, transport: transport)
        await viewModel.connect()

        await viewModel.send(text: "Hej EVE")

        XCTAssertEqual(viewModel.turns.count, 2)
        XCTAssertEqual(viewModel.turns[0].speaker, .user)
        XCTAssertEqual(viewModel.turns[0].text, "Hej EVE")
        XCTAssertEqual(viewModel.turns[1].speaker, .eve)
        XCTAssertEqual(viewModel.turns[1].text, "Hej! Hur mår du?")
        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(transport.sentMessages, ["Hej EVE"])
    }

    func testSendSurfacesAGatewayErrorEventAsFailedState() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [
            .event(.sessionStarted(sessionId: "s1")),
            .event(.error(code: "hermes_unavailable", message: "EVE's reasoning backend is unreachable right now")),
        ]
        let viewModel = ConversationViewModel(apiClient: client, transport: transport)
        await viewModel.connect()

        await viewModel.send(text: "Hej EVE")

        XCTAssertEqual(
            viewModel.connectionState,
            .failed("EVE's reasoning backend is unreachable right now")
        )
        // The user's own turn is still recorded even though the reply failed.
        XCTAssertEqual(viewModel.turns.count, 1)
    }

    func testSendIsANoOpWhenNotConnected() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        let viewModel = ConversationViewModel(apiClient: client, transport: transport)

        await viewModel.send(text: "Hej EVE")

        XCTAssertTrue(viewModel.turns.isEmpty)
        XCTAssertTrue(transport.sentMessages.isEmpty)
    }

    func testEmptyOrWhitespaceTextIsNeverSent() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [.event(.sessionStarted(sessionId: "s1"))]
        let viewModel = ConversationViewModel(apiClient: client, transport: transport)
        await viewModel.connect()

        await viewModel.send(text: "   ")

        XCTAssertTrue(viewModel.turns.isEmpty)
        XCTAssertTrue(transport.sentMessages.isEmpty)
    }

    func testDisconnectClosesTheTransportAndResetsState() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [.event(.sessionStarted(sessionId: "s1"))]
        let viewModel = ConversationViewModel(apiClient: client, transport: transport)
        await viewModel.connect()

        await viewModel.disconnect()

        XCTAssertEqual(viewModel.connectionState, .idle)
        XCTAssertEqual(transport.closeCallCount, 1)
    }
}
