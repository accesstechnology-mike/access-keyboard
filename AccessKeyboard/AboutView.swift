import AccessKeyboardCore
import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    Image("CompanyMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("access: keyboard")
                            .font(.largeTitle.weight(.bold))
                        Text("access: technology")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("access: keyboard, from access: technology")

                Text(summary)
                    .foregroundStyle(.secondary)

                Group {
                    labeled("Who it’s for", "People who need a keyboard they can extend — motor, cognitive, vision, or other access needs — without learning a new key map first.")
                    labeled("Privacy", privacyText)
                    labeled("VoiceOver", "Every key is a keyboard accessibility element with a spoken label (Shift, Delete, Next Keyboard, and so on).")
                    labeled("What matches iOS/iPadOS", "Size-class layouts (compact iPhone, 11-inch iPad, 12.9/13-inch Pro), number row on large boards, tab, caps lock, shift-for-symbols, long-press accents, double-space period, hold-delete that moves from letters to words, two-finger cursor movement anywhere on the keyboard, and the globe key Apple requires.")
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var summary: String {
        "An assistive keyboard for iPhone and iPad that starts from the standard iOS/iPadOS layout, adapting from a compact board on iPhone up to the large iPad Pro board. Extra tools come later without throwing away the layout you already know. ABC, frequency, coloured vowels, Beth colours, and hi-contrast themes are optional; QWERTY stays the starting board. Keys stay large for eye-gaze, and the literacy font is always on."
    }

    private var privacyText: String {
        var text = "The keyboard still types with Full Access off and with no network. Full Access lets layout, colour, and on-device learned predictions (PredictionMemory in the shared App Group) be shared with the keyboard extension, and lets Fix reach the correction proxy. Keystrokes stay on this device. Purchases are handled by Apple. Pro status is stored on this device so the keyboard knows whether Fix is included."
        if FeatureFlags.fixConsentRequired {
            text += " Tapping Fix asks once before sending this field’s text to that proxy, which forwards it to OpenAI and does not store it. You can turn that off in Settings."
        } else {
            text += " Tapping Fix sends the current field’s text to that proxy, which forwards it to OpenAI and does not store it."
        }
        if let endpoint = URLSessionFixClient.configuredEndpointString() {
            text += " This build’s proxy is \(endpoint)."
        }
        return text
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}
