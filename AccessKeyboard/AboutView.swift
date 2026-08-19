import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("access: keyboard")
                    .font(.largeTitle.weight(.bold))
                Text("An assistive iPad keyboard that starts from the standard iPadOS layout, especially the large iPad Pro board. Extra tools come later without throwing away the layout you already know.")
                    .foregroundStyle(.secondary)

                Group {
                    labeled("Who it’s for", "People who need a keyboard they can extend — motor, cognitive, vision, or other access needs — without learning a new key map first.")
                    labeled("Privacy", "Full Access is not requested. Keystrokes are inserted into the current text field on device. Nothing is sent anywhere.")
                    labeled("VoiceOver", "Every key is a keyboard accessibility element with a spoken label (Shift, Delete, Next Keyboard, and so on).")
                    labeled("What matches iPadOS", "Size-class layouts (compact, 11-inch iPad, 12.9/13-inch Pro), number row on large boards, tab, caps lock, shift-for-symbols, long-press accents, delete repeat, and the globe key Apple requires.")
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
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
