import Foundation

/// Pro catalogue and the free/paid split.
///
/// Product IDs use the app bundle ID `app.access.keyboard.6M3Z27M69P` as their
/// prefix. `scripts/asc_create_products.py` creates exactly these IDs in App
/// Store Connect. Prices and any introductory offer are set there, not here.
/// The paywall reads localised `Product` values. This file never grants access.
public enum SubscriptionConfig {
    public static let bundleID = "app.access.keyboard.6M3Z27M69P"

    /// Name of the single auto-renewing subscription group. One offering, two prices.
    public static let subscriptionGroupName = "access: keyboard"

    public static let monthlyProductID = "\(bundleID).pro.monthly"
    public static let yearlyProductID = "\(bundleID).pro.yearly"
    /// Non-consumable. A one-off purchase (or a free offer code) that never expires.
    public static let lifetimeProductID = "\(bundleID).pro.lifetime"

    /// Auto-renewing plans. Access lasts until the transaction's expiry date.
    public static let subscriptionProductIDs: Set<String> = [monthlyProductID, yearlyProductID]
    /// One-off purchases. Access has no expiry while the purchase is not revoked.
    public static let lifetimeProductIDs: Set<String> = [lifetimeProductID]
    public static let productIDs: Set<String> = subscriptionProductIDs.union(lifetimeProductIDs)
    /// Paywall order: monthly, yearly, then Lifetime.
    public static let displayOrder: [String] = [monthlyProductID, yearlyProductID, lifetimeProductID]

    /// What the subscription covers. Change this case to switch the split; the
    /// gates below stay in place.
    public static let monetization: KeyboardMonetization = .allFeaturesSubscribed

    public static var keyboardRequiresSubscription: Bool {
        monetization.keyboardRequiresSubscription
    }

    public static var fixRequiresSubscription: Bool {
        monetization.fixRequiresSubscription
    }

    /// Opens the containing app on the paywall. Empty means the locked keyboard
    /// shows the message only. The keyboard extension has no purchase UI.
    public static let urlScheme = "accesskeyboard"

    public static var paywallURL: URL? {
        let scheme = urlScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty else { return nil }
        return URL(string: "\(scheme)://subscribe")
    }

    /// Paywall presentation only. `true` lets the paywall show a trial headline
    /// when StoreKit reports an introductory offer the user is eligible for.
    /// It does not create a trial and it does not unlock the keyboard.
    public static let showTrialHeadlineDefault = true

    /// Optional JSON on the existing site. Only `showTrialHeadline` is read.
    public static let remoteConfigURL = URL(string: "https://access-keyboard.vercel.app/config.json")!

    public static let privacyPolicyURL = URL(string: "https://access-keyboard.vercel.app/privacy.html")!
    public static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    public static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
}

public enum KeyboardMonetization: String, Sendable {
    /// The keyboard and Fix both require an active subscription or introductory offer.
    case allFeaturesSubscribed
    /// Same split as `.allFeaturesSubscribed`. Kept so the default can move without new gates.
    case allSubscribed
    /// Typing stays free. Fix requires an active subscription.
    case coreKeyboardFreeFixSubscribed

    public var keyboardRequiresSubscription: Bool {
        switch self {
        case .allFeaturesSubscribed, .allSubscribed:
            return true
        case .coreKeyboardFreeFixSubscribed:
            return false
        }
    }

    public var fixRequiresSubscription: Bool {
        switch self {
        case .allFeaturesSubscribed, .allSubscribed, .coreKeyboardFreeFixSubscribed:
            return true
        }
    }
}

public enum KeyboardLock {
    public static let trialMessage = "To type with access: keyboard, open the app and get Pro."
    public static let openAppButtonTitle = "Open access: keyboard"
    public static let nextKeyboardTitle = "Next Keyboard"

    public static var canOpenContainingApp: Bool {
        SubscriptionConfig.paywallURL != nil
    }

    public static func isLocked(requiresSubscription: Bool, canReadEntitlement: Bool, entitled: Bool) -> Bool {
        guard requiresSubscription else { return false }
        if !canReadEntitlement { return true }
        return !entitled
    }

    public static func message(canReadEntitlement _: Bool) -> String {
        trialMessage
    }
}

/// What the paywall may say. Never an entitlement.
public struct PaywallPresentation: Equatable, Sendable {
    public var showTrialHeadline: Bool

    public static let codeDefault = PaywallPresentation(
        showTrialHeadline: SubscriptionConfig.showTrialHeadlineDefault
    )

    /// Reads only `showTrialHeadline`. Missing JSON, a non-boolean value, or any
    /// other key (including fields that look like an entitlement or a trial length)
    /// falls back to the code default for the headline and grants nothing.
    public static func resolved(json: Data?) -> PaywallPresentation {
        guard let json,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              object.keys.contains("showTrialHeadline"),
              let show = object["showTrialHeadline"] as? Bool else {
            return codeDefault
        }
        return PaywallPresentation(showTrialHeadline: show)
    }
}

/// The record the containing app writes and the keyboard extension reads.
/// A missing record, `active == false`, an unknown product, or an expiry that
/// is not in the future all mean not subscribed.
public struct SubscriptionEntitlementRecord: Codable, Equatable, Sendable {
    public var active: Bool
    public var productID: String?
    public var expiresAt: Date?

    public init(active: Bool, productID: String?, expiresAt: Date?) {
        self.active = active
        self.productID = productID
        self.expiresAt = expiresAt
    }

    public static let inactive = SubscriptionEntitlementRecord(active: false, productID: nil, expiresAt: nil)

    public func isActive(
        at date: Date,
        knownProductIDs: Set<String> = SubscriptionConfig.productIDs,
        lifetimeProductIDs: Set<String> = SubscriptionConfig.lifetimeProductIDs
    ) -> Bool {
        guard active, let productID, knownProductIDs.contains(productID) else {
            return false
        }
        if lifetimeProductIDs.contains(productID) {
            return true
        }
        guard let expiresAt else { return false }
        return expiresAt > date
    }

    /// True for an active one-off Lifetime purchase.
    public var isLifetime: Bool {
        active && productID.map { SubscriptionConfig.lifetimeProductIDs.contains($0) } == true
    }

    /// The record one verified StoreKit transaction grants, or nil if it grants
    /// nothing: an unknown product, a revoked purchase, or an expired plan.
    /// A Lifetime purchase needs no expiry date.
    public static func granted(
        productID: String,
        expirationDate: Date?,
        revocationDate: Date?,
        at date: Date
    ) -> SubscriptionEntitlementRecord? {
        guard SubscriptionConfig.productIDs.contains(productID), revocationDate == nil else { return nil }
        if SubscriptionConfig.lifetimeProductIDs.contains(productID) {
            return SubscriptionEntitlementRecord(active: true, productID: productID, expiresAt: nil)
        }
        guard let expirationDate, expirationDate > date else { return nil }
        return SubscriptionEntitlementRecord(active: true, productID: productID, expiresAt: expirationDate)
    }

    /// Picks the better of two records: Lifetime beats any plan, and between
    /// plans the later expiry wins. Inactive records never win.
    public static func preferred(
        _ lhs: SubscriptionEntitlementRecord,
        _ rhs: SubscriptionEntitlementRecord,
        at date: Date
    ) -> SubscriptionEntitlementRecord {
        let lhsActive = lhs.isActive(at: date)
        let rhsActive = rhs.isActive(at: date)
        guard lhsActive || rhsActive else { return .inactive }
        guard lhsActive else { return rhs }
        guard rhsActive else { return lhs }
        if lhs.isLifetime { return lhs }
        if rhs.isLifetime { return rhs }
        return (rhs.expiresAt ?? .distantPast) > (lhs.expiresAt ?? .distantPast) ? rhs : lhs
    }
}

public enum SubscriptionEntitlementStore {
    public static let storageKey = "subscriptionEntitlement"

    public static func read(from defaults: UserDefaults, at date: Date = Date()) -> SubscriptionEntitlementRecord {
        guard let data = defaults.data(forKey: storageKey) else {
            return .inactive
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let record = try? decoder.decode(SubscriptionEntitlementRecord.self, from: data) else {
            return .inactive
        }
        if record.isActive(at: date) {
            return record
        }
        return SubscriptionEntitlementRecord(
            active: false,
            productID: record.productID,
            expiresAt: record.expiresAt
        )
    }

    public static func write(_ record: SubscriptionEntitlementRecord, to defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public static func readShared(at date: Date = Date()) -> SubscriptionEntitlementRecord {
        read(from: KeyboardPreferences.suite, at: date)
    }

    public static func writeShared(_ record: SubscriptionEntitlementRecord) {
        write(record, to: KeyboardPreferences.suite)
        KeyboardPreferences.notify()
    }
}
