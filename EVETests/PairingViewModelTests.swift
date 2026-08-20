import XCTest
@testable import EVE

@MainActor
final class PairingViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeViewModel() async -> (PairingViewModel, KeychainStore) {
        let client = GatewayAPIClient(session: MockURLProtocol.makeSession())
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        let keychain = KeychainStore(service: "com.eve-app.eve.tests.pairingvm.\(UUID().uuidString)")
        let service = DevicePairingService(client: client, keychain: keychain)
        return (PairingViewModel(pairingService: service), keychain)
    }

    func testInitialStateIsPairedWhenACredentialAlreadyExists() throws {
        let client = GatewayAPIClient(session: MockURLProtocol.makeSession())
        let keychain = KeychainStore(service: "com.eve-app.eve.tests.pairingvm.\(UUID().uuidString)")
        try keychain.save("evgw_existing.credential")
        defer { try? keychain.delete() }

        let viewModel = PairingViewModel(pairingService: DevicePairingService(client: client, keychain: keychain))

        XCTAssertEqual(viewModel.state, .paired)
    }

    func testInitialStateIsIdleWithNoStoredCredential() async {
        let (viewModel, keychain) = await makeViewModel()
        defer { try? keychain.delete() }

        XCTAssertEqual(viewModel.state, .idle)
    }

    func testStartPairingSurfacesAnImmediateRequestFailure() async throws {
        let (viewModel, keychain) = await makeViewModel()
        defer { try? keychain.delete() }
        // No stub registered for POST /v1/pairing/request -> MockURLProtocol fails the load.

        viewModel.startPairing(deviceName: "iPhone", deviceModel: "iPhone16,2")

        // Give the detached Task a moment to run; startPairing itself is synchronous
        // (it only kicks off the Task), so poll briefly rather than assume timing.
        for _ in 0..<20 {
            if viewModel.state != .requesting { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        guard case .failed = viewModel.state else {
            XCTFail("expected .failed, got \(viewModel.state)")
            return
        }
    }

    func testStartPairingSucceedsWhenClaimSucceedsOnFirstAttempt() async throws {
        let (viewModel, keychain) = await makeViewModel()
        defer { try? keychain.delete() }
        MockURLProtocol.stubs["POST /v1/pairing/request"] = .init(
            status: 200,
            body: Data(
                """
                {"id":"req-1","device_name":"iPhone","device_model":"iPhone16,2","status":"pending",
                 "requested_at":"2026-08-16T00:00:00Z","decided_at":null,"expires_at":"2026-08-16T01:00:00Z"}
                """.utf8
            )
        )
        MockURLProtocol.stubs["POST /v1/pairing/req-1/claim"] = .init(
            status: 200, body: Data(#"{"credential":"evgw_abc.def"}"#.utf8)
        )

        viewModel.startPairing(deviceName: "iPhone", deviceModel: "iPhone16,2")

        for _ in 0..<40 {
            if viewModel.state == .paired { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(viewModel.state, .paired)
        XCTAssertTrue(try XCTUnwrap(keychain.read()) == "evgw_abc.def")
    }
}
