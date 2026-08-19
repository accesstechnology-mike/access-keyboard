import SwiftUI
import AccessKeyboardCore

struct SettingsView: View {
    @AppStorage(KeyboardPreferences.bethModeEnabledKey, store: KeyboardPreferences.suite)
    private var bethModeEnabled = false

    @State private var extensionHasFullAccess = KeyboardPreferences.extensionHasFullAccess

    var body: some View {
        List {
            Section {
                Toggle("Beth mode", isOn: $bethModeEnabled)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paints each letter with Beth Moulam’s synesthetic colors, sampled from her TD Snap keyboard. Shift still types capitals; keycaps stay lowercase, as on that board.")
                    Link(
                        "Beth’s article on synaesthesia",
                        destination: URL(string: "https://www.bethmoulam.com/life-skills/learning/learning-styles-synaesthesia/")!
                    )
                }
            }

            Section {
                Text("Fix sits on the suggestion bar. One tap corrects the whole field. Undo puts the original back. Password fields are skipped.")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tapping Fix sends that field’s text to the correction proxy. Ordinary keystrokes are not sent.")
                    if let endpoint = URLSessionFixClient.configuredEndpointString() {
                        Text("This build calls \(endpoint).")
                    }
                }
            }

            Section {
                Text("To use Beth mode or Fix in other apps, iPadOS still requires Settings → General → Keyboard → Keyboards → access: keyboard → Allow Full Access.")
                if !extensionHasFullAccess {
                    Text("The system-wide keyboard has not reported Full Access yet, so it will not see Beth mode or Fix until that switch is on. The Type screen in this app can Fix without that switch.")
                }
            }
        }
        .onAppear {
            extensionHasFullAccess = KeyboardPreferences.extensionHasFullAccess
        }
        .onChange(of: bethModeEnabled) { _, _ in
            KeyboardPreferences.notify()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
}
