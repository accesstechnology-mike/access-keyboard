import AccessKeyboardCore
import SwiftUI

@main
struct AccessKeyboardApp: App {
    init() {
        URLSessionFixClient.persistConfigurationFromBundle()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
