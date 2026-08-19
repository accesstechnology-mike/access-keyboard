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

                Text("An assistive iPad keyboard that starts from the standard iPadOS layout, especially the large iPad Pro board. Extra tools come later without throwing away the layout you already know.")
                    .foregroundStyle(.secondary)

                Group {
                    labeled("Who it’s for", "People who need a keyboard they can extend — motor, cognitive, vision, or other access needs — without learning a new key map first.")
                    labeled("Privacy", privacyText)
                    labeled("VoiceOver", "Every key is a keyboard accessibility element with a spoken label (Shift, Delete, Next Keyboard, and so on).")
                    labeled("What matches iPadOS", "Size-class layouts (compact, 11-inch iPad, 12.9/13-inch Pro), number row on large boards, tab, caps lock, shift-for-symbols, long-press accents, delete repeat, and the globe key Apple requires.")
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var privacyText: String {
        var text = "Full Access is requested so Beth mode can be shared with the keyboard extension, and so Fix can call the correction proxy. Keystrokes stay on this device. Tapping Fix sends the current field’s text to that proxy and does not store it there."
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
