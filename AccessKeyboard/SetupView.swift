import AccessKeyboardCore
import SwiftUI

struct SetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Use this keyboard in every app")
                    .font(.title2.weight(.semibold))

                Text("iOS and iPadOS only let a custom keyboard run after you add it in Settings. The keyboard inside this app works immediately; these steps turn it on system-wide.")
                    .foregroundStyle(.secondary)

                step(1, title: "Open Settings", detail: "Settings → General → Keyboard → Keyboards.")
                step(2, title: "Add the keyboard", detail: "Tap Add New Keyboard…, then choose access: keyboard.")
                step(3, title: "Allow Full Access", detail: setupFullAccessDetail)
                step(4, title: "Switch to it", detail: "In any text field, tap the globe key until you see access: keyboard.")

                Text("iOS and iPadOS do not let an app open the keyboard list for you. You have to add it in Settings yourself — that’s an Apple restriction, not a missing feature.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Text("On a physical iPhone or iPad the app and keyboard must be signed with the same development team so they can share an App Group.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var setupFullAccessDetail: String {
        var detail: String
        if SubscriptionConfig.keyboardRequiresSubscription {
            detail = "Open access: keyboard in that list and turn on Allow Full Access. Other apps can only see your subscription through that switch. Without it, the keyboard stays locked, with a button back to this app and a globe key that switches keyboards."
        } else {
            detail = "Open access: keyboard in that list and turn on Allow Full Access if you want colour settings and learned predictions to be shared, or if you want Fix to reach the correction service. The keyboard still types with Full Access off. Typing stays on this device."
        }
        if FeatureFlags.fixConsentRequired {
            detail += " Tapping Fix asks before it sends the current field, and you can turn that off in Settings."
        } else {
            detail += " Tapping Fix sends the current field to the correction service."
        }
        return detail
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
