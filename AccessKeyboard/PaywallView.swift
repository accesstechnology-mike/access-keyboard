import AccessKeyboardCore
import StoreKit
import SwiftUI
import UIKit

struct PaywallView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @Environment(\.openURL) private var openURL
    @State private var redeemingCode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("access: keyboard")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text(PaywallCopy.intro)
                    .font(.body)

                Text(PaywallCopy.whyPaid)
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
                    Text(subscriptions.statusMessage ?? "Loading Pro options…")
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
                .accessibilityHint("Checks your Apple Account for Pro you already bought")

                actionButton("Redeem Code") {
                    redeemingCode = true
                }
                .accessibilityHint("Enter an offer code from access: technology")

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
        .offerCodeRedemption(isPresented: $redeemingCode) { result in
            Task { await subscriptions.finishCodeRedemption(result) }
        }
    }

    private var trialHeadline: String? {
        let lines = subscriptions.products.compactMap { trialLine(for: $0) }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: " ")
    }

    private var activeSummary: String {
        if subscriptions.record.isLifetime {
            return "You have Pro Lifetime."
        }
        if let expires = subscriptions.record.expiresAt {
            return "Pro is active. Your plan renews or ends on \(expires.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Pro is active."
    }

    private var renewalTerms: String { PaywallCopy.terms }

    @ViewBuilder
    private func planButton(_ product: Product) -> some View {
        let period = product.subscription.map { Self.periodDescription($0.subscriptionPeriod) }
        let isLifetime = SubscriptionConfig.lifetimeProductIDs.contains(product.id)
        let priceLine = period.map { "\(product.displayPrice) per \($0)" }
            ?? (isLifetime ? "\(product.displayPrice), paid once" : product.displayPrice)
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
                Text(isLifetime ? "One payment. Never renews." : "Renews automatically until you cancel.")
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
        .accessibilityHint(
            isLifetime
                ? "Double tap to buy Pro Lifetime through Apple. One payment."
                : "Double tap to subscribe through Apple. Renews automatically."
        )
    }

    private func trialLine(for product: Product) -> String? {
        guard let offer = subscriptions.introductoryOffer(for: product),
              let renewal = product.subscription.map({ Self.periodDescription($0.subscriptionPeriod) }) else {
            return nil
        }
        let length = Self.periodDescription(offer.period, repeats: offer.periodCount)
        if offer.paymentMode == .freeTrial {
            return "\(product.displayName) includes a free trial of \(length) if you are eligible. Then \(product.displayPrice) per \(renewal)."
        }
        if offer.paymentMode == .payAsYouGo || offer.paymentMode == .payUpFront {
            return "\(product.displayName) has an introductory offer of \(offer.displayPrice) for \(length) if you are eligible. Then \(product.displayPrice) per \(renewal)."
        }
        return nil
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

/// Paywall wording in one place, so the copy can be reviewed without reading layout code.
enum PaywallCopy {
    static let intro = "Pro unlocks access: keyboard in every app, including Fix. Choose a monthly or yearly plan, or pay once for Lifetime."
    static let whyPaid = "When you tap Fix, the paragraph you are typing in is sent to an AI service (OpenAI) to correct it. We pay for every Fix. That is why Pro is paid."
    static let terms = "Payment is charged to your Apple Account. Monthly and yearly plans renew automatically at the price shown unless you cancel at least 24 hours before the end of the current period. Cancel in Settings or with Manage Subscriptions. Lifetime is one payment and never renews. Any free trial or offer is shown on the plan only when Apple offers it to your account."
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager())
}
