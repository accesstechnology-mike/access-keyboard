import SwiftUI
import AccessKeyboardCore

struct SettingsView: View {
    @AppStorage(KeyboardPreferences.letterLayoutKey, store: KeyboardPreferences.suite)
    private var letterLayoutRaw = LetterLayout.qwerty.rawValue

    @State private var colourOptionRaw = KeyboardPreferences.colourOption.rawValue

    @State private var extensionHasFullAccess = KeyboardPreferences.extensionHasFullAccess

    @AppStorage(KeyboardPreferences.fixConsentGrantedKey, store: KeyboardPreferences.suite)
    private var fixConsentGranted = false

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
                    Text("QWERTY is the standard keyboard board. ABC keeps that frame and spells the alphabet in order. Frequency uses a Smartbox-style grid order docked to the left of the keyboard for glide and switch scanning, with Space in the top-left and Shift in the bottom-right.")
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
                    Text("System keeps the ordinary system key colours. Coloured vowels paint a, e, i, o, u purple, consonants green, numbers red, and punctuation yellow. Beth uses Beth Moulam’s synesthetic colours. Hi-contrast white is white on black. Hi-contrast yellow is yellow on black.")
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
                    Text(fixFooter)
                    if let endpoint = URLSessionFixClient.configuredEndpointString() {
                        Text("This build calls \(endpoint).")
                    }
                }
            }

            if FeatureFlags.fixConsentRequired {
                Section {
                    Toggle("Allow Fix to send text", isOn: $fixConsentGranted)
                } footer: {
                    Text("Fix sends the current text field to OpenAI to correct it. Turn this off to stop that. The next Fix will ask again. Password fields are never sent.")
                }
            }

            Section {
                Text(fullAccessSummary)
                if !extensionHasFullAccess {
                    Text(fullAccessWarning)
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
        .onChange(of: fixConsentGranted) { _, _ in
            KeyboardPreferences.notify()
        }
    }

    private var fullAccessSummary: String {
        if SubscriptionConfig.keyboardRequiresSubscription {
            return "In other apps the keyboard stays locked until Allow Full Access is on, so it can see your subscription. The locked keyboard shows how to open this app and keeps a globe key that switches keyboards. Allow Full Access also shares colour and layout settings and on-device learned predictions, and lets Fix reach the correction service."
        }
        return "The keyboard still types in other apps with Full Access off and with no network. Allow Full Access to share colour and layout settings and on-device learned predictions, and to let Fix reach the correction service."
    }

    private var fullAccessWarning: String {
        if SubscriptionConfig.keyboardRequiresSubscription {
            return "The system keyboard has not reported Full Access, so it cannot see your subscription and stays locked. The Type screen in this app can still be used."
        }
        return "The system keyboard has not reported Full Access, so it keeps its own colours and its own learned words. Fix explains that and does not send text. The Type screen in this app can still Fix."
    }

    private var fixFooter: String {
        var text = FeatureFlags.fixConsentRequired
            ? "Tapping Fix sends that field’s text to OpenAI through the correction proxy, and only after you allow it. Ordinary keystrokes are not sent."
            : "Tapping Fix sends that field’s text to the correction proxy. Ordinary keystrokes are not sent."
        if SubscriptionConfig.keyboardRequiresSubscription {
            text += " The keyboard, including Fix, requires a subscription."
        } else if SubscriptionConfig.fixRequiresSubscription {
            text += " Fix requires a subscription."
        }
        return text
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
}
