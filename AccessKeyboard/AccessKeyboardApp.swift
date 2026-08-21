import AccessKeyboardCore
import SwiftUI

@main
struct AccessKeyboardApp: App {
    init() {
        KeyboardPreferences.persistMigratedColourOptionIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
