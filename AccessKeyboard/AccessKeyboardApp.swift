import AccessKeyboardCore
import SwiftUI

@main
struct AccessKeyboardApp: App {
    @StateObject private var subscriptions = SubscriptionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        KeyboardPreferences.persistMigratedColourOptionIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(subscriptions)
                .task { subscriptions.start() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await subscriptions.refresh() }
                }
        }
    }
}
