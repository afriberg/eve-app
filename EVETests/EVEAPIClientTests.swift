import XCTest
@testable import EVE

final class EVEAPIClientTests: XCTestCase {
    func testCheckHealthThrowsWhenNotConfigured() async {
        let client = EVEAPIClient()
        do {
            _ = try await client.checkHealth()
            XCTFail("expected notConfigured")
        } catch EVEAPIClient.EVEAPIError.notConfigured {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSendConversationTurnIsNotYetImplementedByBackend() async {
        let client = EVEAPIClient()
        do {
            _ = try await client.sendConversationTurn(text: "hej")
            XCTFail("expected notImplementedByBackend")
        } catch EVEAPIClient.EVEAPIError.notImplementedByBackend {
            // expected — see docs/backend-api.md, gap item 1
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
