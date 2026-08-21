import SwiftUI
import AccessKeyboardCore

struct SettingsView: View {
    @AppStorage(KeyboardPreferences.letterLayoutKey, store: KeyboardPreferences.suite)
    private var letterLayoutRaw = LetterLayout.qwerty.rawValue

    @State private var colourOptionRaw = KeyboardPreferences.colourOption.rawValue

    @State private var extensionHasFullAccess = KeyboardPreferences.extensionHasFullAccess

    var body: some View {
        List {
            Section {
                Picker("Letter layout", selection: $letterLayoutRaw) {
                    ForEach(LetterLayout.allCases) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("QWERTY is the standard iPad board. ABC keeps that frame and spells the alphabet in order. Frequency uses the EARDU letter order from ACE Centre’s switch-scanning analysis. Space stays on the toolbar.")
                    Link(
                        "ACE Centre switch-scanning frequency analysis",
                        destination: URL(string: "https://acecentre.org.uk/projects/switch-scanning-frequency-analysis")!
                    )
                }
            }

            Section {
                Picker("Colours", selection: $colourOptionRaw) {
                    ForEach(ColourOption.allCases) { value in
                        Text(value.title).tag(value.rawValue)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System keeps the ordinary iPad key colours. Coloured vowels paint a, e, i, o, u purple, consonants green, numbers red, and punctuation yellow. Beth uses Beth Moulam’s synesthetic colours. Hi-contrast white is white on black. Hi-contrast yellow is yellow on black.")
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
                Text("To use these settings or Fix in other apps, iPadOS still requires Settings → General → Keyboard → Keyboards → access: keyboard → Allow Full Access.")
                if !extensionHasFullAccess {
                    Text("The system-wide keyboard has not reported Full Access yet, so it will not see these settings or Fix until that switch is on. The Type screen in this app can Fix without that switch.")
                }
            }
        }
        .onAppear {
            extensionHasFullAccess = KeyboardPreferences.extensionHasFullAccess
            KeyboardPreferences.persistMigratedColourOptionIfNeeded()
            colourOptionRaw = KeyboardPreferences.colourOption.rawValue
        }
        .onChange(of: letterLayoutRaw) { _, _ in KeyboardPreferences.notify() }
        .onChange(of: colourOptionRaw) { _, newValue in
            if let option = ColourOption(rawValue: newValue) {
                KeyboardPreferences.colourOption = option
            } else {
                KeyboardPreferences.notify()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
}
