import AccessKeyboardCore
import StoreKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var showSubscription = false

    private var needsSubscription: Bool {
        SubscriptionConfig.keyboardRequiresSubscription
            && !subscriptions.record.isActive(at: Date())
    }

    var body: some View {
        Group {
            if needsSubscription {
                PaywallView()
            } else {
                main
            }
        }
        .onOpenURL { url in
            guard url.scheme == SubscriptionConfig.urlScheme else { return }
            if !needsSubscription {
                showSubscription = true
            }
        }
        .sheet(isPresented: $showSubscription) {
            NavigationStack {
                PaywallView()
                    .navigationTitle("access: keyboard")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showSubscription = false }
                        }
                    }
            }
        }
    }

    private var main: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    TypingScreen()
                        .navigationTitle("Type")
                } label: {
                    Label("Type", systemImage: "keyboard")
                }
                NavigationLink {
                    SettingsView()
                        .navigationTitle("Settings")
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                NavigationLink {
                    PaywallView()
                        .navigationTitle("Pro")
                } label: {
                    Label("Pro", systemImage: "checkmark.seal")
                }
                NavigationLink {
                    SetupView()
                        .navigationTitle("Enable system-wide")
                } label: {
                    Label("Enable system-wide", systemImage: "gear")
                }
                NavigationLink {
                    AboutView()
                        .navigationTitle("About")
                } label: {
                    Label("About", systemImage: "heart.text.square")
                }
            }
            .navigationTitle("access: keyboard")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            TypingScreen()
                .navigationTitle("Type")
        }
    }
}

struct TypingScreen: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TypingViewControllerRepresentable(onReviewMoment: { requestReviewIfAppropriate() })
            .ignoresSafeArea(.keyboard)
            .background(Color(uiColor: .systemBackground))
    }

    /// After a sentence, or when leaving Type, and only once this version.
    /// StoreKit may still decline to show anything.
    private func requestReviewIfAppropriate() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard ReviewPrompt.shouldRequest(currentVersion: version) else { return }
        ReviewPrompt.markRequested(currentVersion: version)
        requestReview()
    }
}

#Preview {
    RootView()
        .environmentObject(SubscriptionManager())
}
