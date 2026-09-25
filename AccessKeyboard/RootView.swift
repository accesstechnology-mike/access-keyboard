import AccessKeyboardCore
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
                        .navigationTitle("Subscription")
                } label: {
                    Label("Subscription", systemImage: "checkmark.seal")
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
    var body: some View {
        TypingViewControllerRepresentable()
            .ignoresSafeArea(.keyboard)
            .background(Color(uiColor: .systemBackground))
    }
}

#Preview {
    RootView()
        .environmentObject(SubscriptionManager())
}
