import AccessKeyboardCore
import SwiftUI

@main
struct AccessKeyboardApp: App {
    @StateObject private var subscriptions = SubscriptionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        KeyboardPreferences.persistMigratedColourOptionIfNeeded()
        MetricKitDiagnostics.shared.start()
        DiagnosticsLog.memory("launch", category: "app")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(subscriptions)
                .task { subscriptions.start() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    ReviewPrompt.recordLaunch()
                    DiagnosticsLog.memory("active", category: "app")
                    Task { await subscriptions.refresh() }
                }
        }
    }
}
