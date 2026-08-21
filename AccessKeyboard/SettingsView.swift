import SwiftUI
import AccessKeyboardCore

struct SettingsView: View {
    @AppStorage(KeyboardPreferences.letterLayoutKey, store: KeyboardPreferences.suite)
    private var letterLayoutRaw = LetterLayout.qwerty.rawValue

    @AppStorage(KeyboardPreferences.handednessKey, store: KeyboardPreferences.suite)
    private var handednessRaw = Handedness.standard.rawValue

    @AppStorage(KeyboardPreferences.keyColouringKey, store: KeyboardPreferences.suite)
    private var keyColouringRaw = KeyColouring.none.rawValue

    @AppStorage(KeyboardPreferences.contrastThemeKey, store: KeyboardPreferences.suite)
    private var contrastThemeRaw = ContrastTheme.system.rawValue

    @AppStorage(KeyboardPreferences.literacyFontEnabledKey, store: KeyboardPreferences.suite)
    private var literacyFontEnabled = false

    @AppStorage(KeyboardPreferences.bethModeEnabledKey, store: KeyboardPreferences.suite)
    private var bethModeEnabled = false

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
                Picker("Handedness", selection: $handednessRaw) {
                    ForEach(Handedness.allCases) { value in
                        Text(value.title).tag(value.rawValue)
                    }
                }
            } footer: {
                Text("On ABC and Frequency, Right mirrors each row so the home cell sits top-right. On QWERTY, Hands colouring marks the left and right halves; Left or Right dims the other side.")
            }

            Section {
                Picker("Key colouring", selection: $keyColouringRaw) {
                    ForEach(KeyColouring.allCases) { value in
                        Text(value.title).tag(value.rawValue)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coloured vowels paint a, e, i, o, u purple, consonants green, numbers red, and punctuation yellow. Hands split the QWERTY halves. Beth uses Beth Moulam’s synesthetic colours. High-contrast themes turn colouring off. Shift still types capitals; Beth and the literacy font keep letter keycaps lowercase.")
                    Link(
                        "Beth’s article on synaesthesia",
                        destination: URL(string: "https://www.bethmoulam.com/life-skills/learning/learning-styles-synaesthesia/")!
                    )
                }
            }

            Section {
                Picker("Contrast", selection: $contrastThemeRaw) {
                    ForEach(ContrastTheme.allCases) { value in
                        Text(value.title).tag(value.rawValue)
                    }
                }
            } footer: {
                Text("Black on white, white on black, yellow on black, and black on yellow replace decorative key colours so the board stays high contrast.")
            }

            Section {
                Toggle("Literacy font", isOn: $literacyFontEnabled)
            } footer: {
                Text("Uses a literacy face with a single-story handwritten a — the form people actually write — and keeps letter keycaps lowercase.")
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
            migrateLegacyBethIfNeeded()
        }
        .onChange(of: letterLayoutRaw) { _, _ in KeyboardPreferences.notify() }
        .onChange(of: handednessRaw) { _, _ in KeyboardPreferences.notify() }
        .onChange(of: keyColouringRaw) { _, newValue in
            bethModeEnabled = newValue == KeyColouring.beth.rawValue
            KeyboardPreferences.notify()
        }
        .onChange(of: contrastThemeRaw) { _, _ in KeyboardPreferences.notify() }
        .onChange(of: literacyFontEnabled) { _, _ in KeyboardPreferences.notify() }
    }

    private func migrateLegacyBethIfNeeded() {
        if KeyboardPreferences.suite.string(forKey: KeyboardPreferences.keyColouringKey) == nil,
           bethModeEnabled {
            keyColouringRaw = KeyColouring.beth.rawValue
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
