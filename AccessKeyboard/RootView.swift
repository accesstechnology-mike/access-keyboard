import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    TypingScreen()
                        .navigationTitle("Type")
                } label: {
                    Label("Type", systemImage: "keyboard")
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
}
