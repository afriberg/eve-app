import XCTest
@testable import EVE

final class DevicePairingServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeService() -> (DevicePairingService, KeychainStore, GatewayAPIClient) {
        let client = GatewayAPIClient(session: MockURLProtocol.makeSession())
        let keychain = KeychainStore(service: "pw.friberg.eve.tests.pairing.\(UUID().uuidString)")
        return (DevicePairingService(client: client, keychain: keychain), keychain, client)
    }

    func testClaimBeforeApprovalMapsToNotYetApproved() async throws {
        let (service, keychain, client) = makeService()
        defer { try? keychain.delete() }
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["POST /v1/pairing/req-1/claim"] = .init(status: 404, body: Data())

        do {
            try await service.claim(requestId: "req-1")
            XCTFail("expected notYetApproved")
        } catch DevicePairingService.PairingError.notYetApproved {
            // expected
        }
    }

    func testSuccessfulClaimStoresCredentialInKeychain() async throws {
        let (service, keychain, client) = makeService()
        defer { try? keychain.delete() }
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["POST /v1/pairing/req-1/claim"] = .init(
            status: 200, body: Data(#"{"credential":"evgw_abc.def"}"#.utf8)
        )

        XCTAssertFalse(service.hasStoredCredential)
        try await service.claim(requestId: "req-1")

        XCTAssertTrue(service.hasStoredCredential)
        XCTAssertEqual(try keychain.read(), "evgw_abc.def")
    }

    func testForgetRemovesTheStoredCredential() async throws {
        let (service, keychain, client) = makeService()
        defer { try? keychain.delete() }
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["POST /v1/pairing/req-1/claim"] = .init(
            status: 200, body: Data(#"{"credential":"evgw_abc.def"}"#.utf8)
        )
        try await service.claim(requestId: "req-1")
        XCTAssertTrue(service.hasStoredCredential)

        try service.forget()

        XCTAssertFalse(service.hasStoredCredential)
    }
}
