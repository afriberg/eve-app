import XCTest
@testable import EVE

final class VoiceSessionStateTests: XCTestCase {
    func testIdleAndInterruptedAreDistinctStates() {
        XCTAssertNotEqual(VoiceSessionState.idle, VoiceSessionState.interrupted)
    }

    func testErrorCarriesMessage() {
        let state = VoiceSessionState.error("boom")
        XCTAssertEqual(state.label, "boom")
    }

    func testLocalizedIdleLabelIsNotEmpty() {
        XCTAssertFalse(VoiceSessionState.idle.label.isEmpty)
    }
}
