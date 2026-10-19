import XCTest
@testable import AccessKeyboardCore

@MainActor
final class KeyboardLockTests: XCTestCase {
    func testDefaultModeKeepsTheKeyboardFreeAndLeavesFixToTheServerAllowance() {
        XCTAssertEqual(SubscriptionConfig.monetization, .keyboardFreeFixAllowance)
        XCTAssertFalse(SubscriptionConfig.keyboardRequiresSubscription)
        XCTAssertFalse(SubscriptionConfig.fixRequiresSubscription)
        XCTAssertFalse(
            KeyboardLock.isLocked(
                requiresSubscription: SubscriptionConfig.keyboardRequiresSubscription,
                canReadEntitlement: false,
                entitled: false
            ),
            "Without Pro and without Full Access the keyboard must still type"
        )
        XCTAssertEqual(SubscriptionConfig.freeFixesPerMonth, 30)
        XCTAssertEqual(SubscriptionConfig.proFixesPerDay, 100)
        XCTAssertTrue(KeyboardMonetization.allFeaturesSubscribed.keyboardRequiresSubscription)
        XCTAssertTrue(KeyboardMonetization.allSubscribed.keyboardRequiresSubscription)
        XCTAssertFalse(KeyboardMonetization.coreKeyboardFreeFixSubscribed.keyboardRequiresSubscription)
        XCTAssertTrue(KeyboardMonetization.coreKeyboardFreeFixSubscribed.fixRequiresSubscription)
        XCTAssertEqual(
            KeyboardLock.trialMessage,
            "To type with access: keyboard, open the app and get Pro."
        )
        XCTAssertNotNil(SubscriptionConfig.paywallURL)
    }

    func testMissingEntitlementLocksAndKeepsNextKeyboard() {
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        let document = FakeDocument(text: "hi")
        let host = LockHost()
        engine.document = document
        engine.host = host
        engine.keyboardRequiresSubscription = true
        engine.sharedPreferencesAvailable = true
        engine.subscriptionIsActive = { false }

        XCTAssertTrue(engine.keyboardIsLocked)
        XCTAssertEqual(
            KeyboardLock.message(canReadEntitlement: true),
            KeyboardLock.trialMessage
        )

        engine.handleCharacter("a")
        engine.continueBackspace(byWord: false)
        engine.moveCursor(horizontal: -1, vertical: 0)
        XCTAssertEqual(document.text, "hi")

        engine.handle(.nextKeyboard)
        XCTAssertTrue(host.advanced)

        let view = KeyboardView(engine: engine)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 280)
        view.layoutIfNeeded()
        let message = view.descendant(identified: "keyboard.lock.message") as? UILabel
        let openApp = view.descendant(identified: "keyboard.lock.openApp")
        let nextKeyboard = view.descendant(identified: "keyboard.lock.nextKeyboard")
        XCTAssertEqual(message?.text, KeyboardLock.trialMessage)
        XCTAssertFalse(message?.isHidden ?? true)
        XCTAssertNotNil(openApp)
        XCTAssertFalse(openApp?.isHidden ?? true)
        XCTAssertGreaterThanOrEqual(openApp?.bounds.height ?? 0, 44)
        XCTAssertEqual(nextKeyboard?.accessibilityLabel, KeyboardLock.nextKeyboardTitle)
        XCTAssertGreaterThanOrEqual(nextKeyboard?.bounds.height ?? 0, 44)
        XCTAssertFalse(nextKeyboard?.isHidden ?? true)
    }

    func testLockedPanelWithoutAURLShowsTheMessageAndGlobeOnly() {
        let panel = KeyboardLockedPanel(frame: CGRect(x: 0, y: 0, width: 390, height: 280))
        panel.apply(
            message: KeyboardLock.trialMessage,
            appearance: .system(for: .light),
            showsOpenButton: false
        )
        panel.layoutIfNeeded()
        let message = panel.descendant(identified: "keyboard.lock.message") as? UILabel
        let openApp = panel.descendant(identified: "keyboard.lock.openApp")
        let nextKeyboard = panel.descendant(identified: "keyboard.lock.nextKeyboard")
        XCTAssertEqual(message?.text, KeyboardLock.trialMessage)
        XCTAssertFalse(message?.isHidden ?? true)
        XCTAssertTrue(openApp?.isHidden ?? false)
        XCTAssertEqual(nextKeyboard?.accessibilityLabel, KeyboardLock.nextKeyboardTitle)
        XCTAssertGreaterThanOrEqual(nextKeyboard?.bounds.height ?? 0, 44)
        XCTAssertFalse(nextKeyboard?.isHidden ?? true)
    }

    func testUnreadableEntitlementStaysLockedWithTheSameMessage() {
        XCTAssertEqual(
            KeyboardLock.message(canReadEntitlement: false),
            "To type with access: keyboard, open the app and get Pro."
        )
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.keyboardRequiresSubscription = true
        engine.sharedPreferencesAvailable = false
        engine.subscriptionIsActive = { true }
        XCTAssertTrue(engine.keyboardIsLocked)
    }

    func testActiveSubscriptionUnlocksTyping() {
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        let document = FakeDocument(text: "")
        engine.document = document
        engine.entitleForTests()
        engine.traits.autocapitalizationType = .none
        XCTAssertFalse(engine.keyboardIsLocked)
        engine.handleCharacter("a")
        XCTAssertEqual(document.text, "a")
    }

    func testFreeKeyboardModeStillTypesWithoutASubscription() {
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        let document = FakeDocument(text: "")
        engine.document = document
        engine.keyboardRequiresSubscription = false
        engine.sharedPreferencesAvailable = true
        engine.subscriptionIsActive = { false }
        engine.traits.autocapitalizationType = .none
        XCTAssertFalse(engine.keyboardIsLocked)
        engine.handleCharacter("z")
        XCTAssertEqual(document.text, "z")
    }
}

@MainActor
private final class LockHost: KeyboardHost {
    var advanced = false
    func advanceToNextInputMode() { advanced = true }
    func dismissKeyboard() {}
    var needsInputModeSwitchKey: Bool { false }
}

private extension UIView {
    func descendant(identified identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for child in subviews {
            if let found = child.descendant(identified: identifier) { return found }
        }
        return nil
    }
}
