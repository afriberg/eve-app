import XCTest
@testable import EVE

final class KeychainStoreTests: XCTestCase {
    func testSaveReadDeleteRoundTrip() throws {
        let store = KeychainStore(service: "pw.friberg.eve.tests.\(UUID().uuidString)")
        defer { try? store.delete() }

        XCTAssertNil(try store.read())

        try store.save("test-credential")
        XCTAssertEqual(try store.read(), "test-credential")

        try store.delete()
        XCTAssertNil(try store.read())
    }
}
