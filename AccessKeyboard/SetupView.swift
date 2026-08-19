import SwiftUI

struct SetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Use this keyboard in every app")
                    .font(.title2.weight(.semibold))

                Text("iPadOS only lets a custom keyboard run after you add it in Settings. The keyboard inside this app works immediately; these steps turn it on system-wide.")
                    .foregroundStyle(.secondary)

                step(1, title: "Open Settings", detail: "Settings → General → Keyboard → Keyboards.")
                step(2, title: "Add the keyboard", detail: "Tap Add New Keyboard…, then choose access: keyboard.")
                step(3, title: "Allow it (optional)", detail: "Full Access is off on purpose. Leave it off unless a later feature needs it. Typing still works.")
                step(4, title: "Switch to it", detail: "In any text field, tap the globe key until you see access: keyboard.")

                Text("iPadOS does not let an app open the keyboard list for you. You have to add it in Settings yourself — that’s an Apple restriction, not a missing feature.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func step(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
