import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationSplitView {
            NavigationStack {
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
                .toolbarBackground(.visible, for: .navigationBar)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            NavigationStack {
                TypingScreen()
                    .navigationTitle("Type")
                    .toolbarBackground(.visible, for: .navigationBar)
            }
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
}
