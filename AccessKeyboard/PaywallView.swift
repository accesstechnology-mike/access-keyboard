import AccessKeyboardCore
import StoreKit
import SwiftUI
import UIKit

struct PaywallView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("access: keyboard Pro")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("The keyboard stays free to use. Pro adds Fix, which can correct the current text field after you allow it.")
                    .font(.body)

                if let headline = trialHeadline {
                    Text(headline)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }

                if subscriptions.record.isActive(at: Date()) {
                    Text(activeSummary)
                        .font(.body)
                }

                if subscriptions.products.isEmpty {
                    Text(subscriptions.statusMessage ?? "Loading subscriptions…")
                        .font(.body)
                    actionButton("Try again") {
                        Task { await subscriptions.refresh() }
                    }
                } else {
                    ForEach(subscriptions.products, id: \.id) { product in
                        planButton(product)
                    }
                }

                Text(renewalTerms)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let status = subscriptions.statusMessage, !subscriptions.products.isEmpty {
                    Text(status)
                        .font(.body)
                        .accessibilityLabel(status)
                }

                actionButton("Restore Purchases") {
                    Task { await subscriptions.restore() }
                }
                .accessibilityHint("Checks your Apple ID for an existing Pro subscription")

                actionButton("Manage Subscriptions") {
                    Task { await manageSubscriptions() }
                }
                .accessibilityHint("Opens Apple’s subscription management")

                Link("Privacy Policy", destination: SubscriptionConfig.privacyPolicyURL)
                    .frame(minHeight: 44)
                Link("Terms of Use", destination: SubscriptionConfig.termsOfUseURL)
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .task {
            subscriptions.start()
            await subscriptions.refresh()
        }
    }

    private var trialHeadline: String? {
        let lines = subscriptions.products.compactMap { trialLine(for: $0) }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: " ")
    }

    private var activeSummary: String {
        if let expires = subscriptions.record.expiresAt {
            return "Pro is active until \(expires.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Pro is active."
    }

    private var renewalTerms: String {
        "Payment is charged to your Apple ID. A subscription renews automatically at the price shown for that plan unless you cancel at least 24 hours before the end of the current period. Cancel in Settings, or with Manage Subscriptions. The trial length, if a plan has one, is the introductory offer Apple shows for that plan."
    }

    @ViewBuilder
    private func planButton(_ product: Product) -> some View {
        let period = product.subscription.map { Self.periodDescription($0.subscriptionPeriod) }
        let priceLine = period.map { "\(product.displayPrice) per \($0)" } ?? product.displayPrice
        let trial = trialLine(for: product)
        Button {
            Task { await subscriptions.purchase(product) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(product.displayName)
                    .font(.headline)
                Text(priceLine)
                    .font(.body)
                if let trial {
                    Text(trial)
                        .font(.subheadline)
                }
                Text("Renews automatically until cancelled.")
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to subscribe through Apple. Renews automatically.")
    }

    private func trialLine(for product: Product) -> String? {
        guard let offer = subscriptions.introductoryOffer(for: product),
              let renewal = product.subscription.map({ Self.periodDescription($0.subscriptionPeriod) }) else {
            return nil
        }
        let length = Self.periodDescription(offer.period, repeats: offer.periodCount)
        switch offer.paymentMode {
        case .freeTrial:
            return "\(product.displayName) includes a free trial of \(length) if you are eligible. Then \(product.displayPrice) per \(renewal)."
        case .payAsYouGo, .payUpFront:
            return "\(product.displayName) has an introductory offer of \(offer.displayPrice) for \(length) if you are eligible. Then \(product.displayPrice) per \(renewal)."
        @unknown default:
            return nil
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.bordered)
    }

    private func manageSubscriptions() async {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let scene {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                return
            } catch {
                openURL(SubscriptionConfig.manageSubscriptionsURL)
                return
            }
        }
        openURL(SubscriptionConfig.manageSubscriptionsURL)
    }

    static func periodDescription(_ period: Product.SubscriptionPeriod, repeats: Int = 1) -> String {
        let value = period.value * max(repeats, 1)
        let unit: String
        switch period.unit {
        case .day:
            unit = value == 1 ? "day" : "days"
        case .week:
            unit = value == 1 ? "week" : "weeks"
        case .month:
            unit = value == 1 ? "month" : "months"
        case .year:
            unit = value == 1 ? "year" : "years"
        @unknown default:
            unit = value == 1 ? "period" : "periods"
        }
        return value == 1 ? unit : "\(value) \(unit)"
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager())
}
