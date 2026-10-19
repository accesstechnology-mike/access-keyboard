import XCTest
@testable import AccessKeyboardCore

@MainActor
extension KeyboardEngine {
    func entitleForTests() {
        sharedPreferencesAvailable = true
        subscriptionIsActive = { true }
    }
}
