import XCTest
@testable import AccessKeyboardCore

final class DocumentTextAssemblerTests: XCTestCase {
    func testCombinedPrefersLiveContext() {
        let text = DocumentTextAssembler.combined(
            before: "Hello ",
            selected: nil,
            after: "world",
            fallback: "stale"
        )
        XCTAssertEqual(text, "Hello world")
    }

    func testCombinedFallsBackToShadowWhenProxyIsEmpty() {
        let text = DocumentTextAssembler.combined(
            before: nil,
            selected: nil,
            after: nil,
            fallback: "typed so far"
        )
        XCTAssertEqual(text, "typed so far")
    }

    func testPreferredKeepsShadowWhenLiveIsAWindow() {
        let preferred = DocumentTextAssembler.preferred(
            live: "the mesage",
            shadow: "I recieve the mesage"
        )
        XCTAssertEqual(preferred, "I recieve the mesage")
    }

    func testPreferredTakesLongerLiveText() {
        let preferred = DocumentTextAssembler.preferred(
            live: "I recieve the mesage now",
            shadow: "I recieve"
        )
        XCTAssertEqual(preferred, "I recieve the mesage now")
    }
}
