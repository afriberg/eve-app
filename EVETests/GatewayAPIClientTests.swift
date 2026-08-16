import XCTest
@testable import EVE

final class GatewayAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeClient() -> GatewayAPIClient {
        GatewayAPIClient(session: MockURLProtocol.makeSession())
    }

    func testRequestsBeforeConfigureThrowNotConfigured() async {
        let client = makeClient()
        do {
            _ = try await client.checkHealth()
            XCTFail("expected notConfigured")
        } catch GatewayAPIClient.GatewayAPIError.notConfigured {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCheckHealthReturnsTrueOn200() async throws {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["GET /health"] = .init(status: 200, body: Data(#"{"status":"ok"}"#.utf8))

        let healthy = try await client.checkHealth()
        XCTAssertTrue(healthy)
    }

    func testCheckHealthReturnsFalseOnServerError() async throws {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["GET /health"] = .init(status: 503, body: Data())

        let healthy = try await client.checkHealth()
        XCTAssertFalse(healthy)
    }

    func testRequestPairingDecodesResponse() async throws {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","device_name":"Test iPhone",
         "device_model":"iPhone16,2","status":"pending",
         "requested_at":"2026-08-16T00:00:00Z","decided_at":null,
         "expires_at":"2026-08-16T01:00:00Z"}
        """
        MockURLProtocol.stubs["POST /v1/pairing/request"] = .init(status: 200, body: Data(json.utf8))

        let view = try await client.requestPairing(deviceName: "Test iPhone", deviceModel: "iPhone16,2")

        XCTAssertEqual(view.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(view.status, "pending")
        XCTAssertNil(view.decidedAt)
    }

    func testRequestPairingDoesNotSendAnAuthorizationHeader() async throws {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["POST /v1/pairing/request"] = .init(
            status: 200,
            body: Data(
                """
                {"id":"1","device_name":"iPhone","device_model":"","status":"pending",
                 "requested_at":"2026-08-16T00:00:00Z","decided_at":null,"expires_at":"2026-08-16T01:00:00Z"}
                """.utf8
            )
        )

        _ = try await client.requestPairing(deviceName: "iPhone", deviceModel: "")

        let sent = MockURLProtocol.requestLog.last
        XCTAssertNil(sent?.value(forHTTPHeaderField: "Authorization"))
    }

    func testClaimPairingCredentialReturnsCredentialOn200() async throws {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["POST /v1/pairing/req-1/claim"] = .init(
            status: 200, body: Data(#"{"credential":"evgw_abc.def"}"#.utf8)
        )

        let credential = try await client.claimPairingCredential(requestId: "req-1")
        XCTAssertEqual(credential, "evgw_abc.def")
    }

    func testClaimPairingCredentialSurfacesHTTPStatusOn404() async throws {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        MockURLProtocol.stubs["POST /v1/pairing/req-1/claim"] = .init(status: 404, body: Data())

        do {
            _ = try await client.claimPairingCredential(requestId: "req-1")
            XCTFail("expected .http(status: 404, ...)")
        } catch GatewayAPIClient.GatewayAPIError.http(let status, _) {
            XCTAssertEqual(status, 404)
        }
    }

    func testCreateSessionRequiresADeviceCredential() async {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)

        do {
            _ = try await client.createSession()
            XCTFail("expected notConfigured")
        } catch GatewayAPIClient.GatewayAPIError.notConfigured {
            // expected — no device credential set yet
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCreateSessionSendsBearerCredentialAndDecodesTicket() async throws {
        let client = makeClient()
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        await client.setDeviceCredential("evgw_abc.def")
        MockURLProtocol.stubs["POST /v1/sessions"] = .init(
            status: 200,
            body: Data(
                #"{"session_id":"s1","ticket":"tk1","expires_at":"2026-08-16T00:00:30Z"}"#.utf8
            )
        )

        let ticket = try await client.createSession()

        XCTAssertEqual(ticket.sessionId, "s1")
        XCTAssertEqual(ticket.ticket, "tk1")
        let sent = MockURLProtocol.requestLog.last
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Authorization"), "Bearer evgw_abc.def")
    }
}
