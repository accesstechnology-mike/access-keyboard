import Foundation

/// Subscription catalogue and the free/paid split.
///
/// Product IDs use the app bundle ID `app.access.keyboard.6M3Z27M69P` as their
/// prefix. Mike creates exactly these IDs in App Store Connect. Prices and the
/// introductory-offer length are entered there, not here. The paywall reads
/// localized `Product` values. This file never grants access.
public enum SubscriptionConfig {
    public static let bundleID = "app.access.keyboard.6M3Z27M69P"

    /// Name of the single auto-renewing subscription group.
    public static let subscriptionGroupName = "access: keyboard Pro"

    public static let monthlyProductID = "\(bundleID).pro.monthly"
    public static let yearlyProductID = "\(bundleID).pro.yearly"

    public static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]

    /// What is free and what requires Pro. One switch for the whole app.
    /// The core keyboard stays usable without a subscription. Fix does not.
    public static let monetization: KeyboardMonetization = .coreKeyboardFreeFixSubscribed

    public static var fixRequiresSubscription: Bool {
        switch monetization {
        case .coreKeyboardFreeFixSubscribed:
            return true
        }
    }

    /// Paywall presentation only. `true` lets the paywall show a trial headline
    /// when StoreKit reports an introductory offer the user is eligible for.
    /// It does not create a trial and it does not unlock Fix.
    public static let showTrialHeadlineDefault = true

    /// Optional JSON on the existing site. Only `showTrialHeadline` is read.
    public static let remoteConfigURL = URL(string: "https://access-keyboard.vercel.app/config.json")!

    public static let privacyPolicyURL = URL(string: "https://access-keyboard.vercel.app/privacy.html")!
    public static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    public static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
}

public enum KeyboardMonetization: String, Sendable {
    /// Typing, layouts, colours, and on-device predictions stay free. Fix requires an active subscription.
    case coreKeyboardFreeFixSubscribed
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
        knownProductIDs: Set<String> = SubscriptionConfig.productIDs
    ) -> Bool {
        guard active, let productID, knownProductIDs.contains(productID), let expiresAt else {
            return false
        }
        return expiresAt > date
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
