import XCTest
@testable import AccessKeyboardCore

final class ReviewPromptTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "test.access.keyboard.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testAsksOnceAfterRealUseAndNotBefore() {
        let store = defaults()
        XCTAssertFalse(ReviewPrompt.shouldRequest(currentVersion: "1.0.1", defaults: store))

        ReviewPrompt.recordLaunch(in: store)
        ReviewPrompt.recordLaunch(in: store)
        ReviewPrompt.recordTypedCharacters(ReviewPrompt.minimumCharacters, in: store)
        XCTAssertFalse(ReviewPrompt.shouldRequest(currentVersion: "1.0.1", defaults: store))

        ReviewPrompt.recordLaunch(in: store)
        XCTAssertTrue(ReviewPrompt.shouldRequest(currentVersion: "1.0.1", defaults: store))

        ReviewPrompt.markRequested(currentVersion: "1.0.1", defaults: store)
        XCTAssertFalse(ReviewPrompt.shouldRequest(currentVersion: "1.0.1", defaults: store))
        XCTAssertTrue(ReviewPrompt.shouldRequest(currentVersion: "1.0.2", defaults: store))
    }

    func testEmptyVersionAndZeroCharactersNeverAsk() {
        let store = defaults()
        ReviewPrompt.recordLaunch(in: store)
        ReviewPrompt.recordLaunch(in: store)
        ReviewPrompt.recordLaunch(in: store)
        ReviewPrompt.recordTypedCharacters(0, in: store)
        XCTAssertFalse(ReviewPrompt.shouldRequest(currentVersion: "1.0.1", defaults: store))
        XCTAssertFalse(ReviewPrompt.shouldRequest(currentVersion: "  ", defaults: store))
    }
}
