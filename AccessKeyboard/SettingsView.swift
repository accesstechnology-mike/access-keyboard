import SwiftUI
import AccessKeyboardCore

struct SettingsView: View {
    @AppStorage(KeyboardPreferences.letterLayoutKey, store: KeyboardPreferences.suite)
    private var letterLayoutRaw = LetterLayout.qwerty.rawValue

    @AppStorage(KeyboardPreferences.predictionPlacementKey, store: KeyboardPreferences.suite)
    private var predictionPlacementRaw = PredictionPlacement.preferSide.rawValue

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
                Picker("Predictions on landscape iPad", selection: $predictionPlacementRaw) {
                    ForEach(PredictionPlacement.allCases) { placement in
                        Text(placement.title).tag(placement.rawValue)
                    }
                }
            } footer: {
                Text("Only applies to an iPad in landscape. Prefer side keeps predictions and Fix in a column on the left of the keys. Prefer top puts them in a bar above the keys, so your hands do not cover them, and Fix keeps the same size. Portrait iPad, iPhone, and any board too narrow for the side column ignore this and keep their usual layout.")
            }

            Section {
                Text("On iPhone, Fix sits at the left of the prediction bar. On iPad, it sits at the bottom of the prediction list on the left, or at the left of the top bar with Prefer top in landscape. One tap corrects the whole field. Undo puts the original back. Password fields are skipped.")
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
                Text("The keyboard still types in other apps with Full Access off and with no network. Allow Full Access to share colour and layout settings and on-device learned predictions, and to let Fix reach the correction service.")
                if !extensionHasFullAccess {
                    Text("The system keyboard has not reported Full Access, so it keeps its own colours and its own learned words. Fix explains that and does not send text. The Type screen in this app can still Fix.")
                }
            }
        }
        .onAppear {
            extensionHasFullAccess = KeyboardPreferences.extensionHasFullAccess
            KeyboardPreferences.persistMigratedColourOptionIfNeeded()
            colourOptionRaw = KeyboardPreferences.colourOption.rawValue
        }
        .onChange(of: letterLayoutRaw) { _, _ in KeyboardPreferences.notify() }
        .onChange(of: predictionPlacementRaw) { _, _ in KeyboardPreferences.notify() }
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

    private var fixFooter: String {
        if FeatureFlags.fixConsentRequired {
            return "Tapping Fix sends that field’s text to OpenAI through the correction proxy, and only after you allow it. Ordinary keystrokes are not sent."
        }
        return "Tapping Fix sends that field’s text to the correction proxy. Ordinary keystrokes are not sent."
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
}
