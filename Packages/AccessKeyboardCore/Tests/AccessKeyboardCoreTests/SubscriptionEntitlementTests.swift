import XCTest
@testable import AccessKeyboardCore

final class SubscriptionEntitlementTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.access.keyboard.subscription.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testMissingRecordIsNotSubscribed() {
        let record = SubscriptionEntitlementStore.read(from: defaults, at: Date())
        XCTAssertFalse(record.isActive(at: Date()))
        XCTAssertNil(record.productID)
        XCTAssertNil(record.expiresAt)
    }

    func testInactiveFlagIsNotSubscribed() {
        let record = SubscriptionEntitlementRecord(
            active: false,
            productID: SubscriptionConfig.monthlyProductID,
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(record.isActive(at: Date()))
    }

    func testExpiredRecordIsNotSubscribed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = SubscriptionEntitlementRecord(
            active: true,
            productID: SubscriptionConfig.yearlyProductID,
            expiresAt: now.addingTimeInterval(-1)
        )
        XCTAssertFalse(record.isActive(at: now))
    }

    func testMissingExpiryIsNotSubscribed() {
        let record = SubscriptionEntitlementRecord(
            active: true,
            productID: SubscriptionConfig.monthlyProductID,
            expiresAt: nil
        )
        XCTAssertFalse(record.isActive(at: Date()))
    }

    func testUnknownProductIsNotSubscribed() {
        let record = SubscriptionEntitlementRecord(
            active: true,
            productID: "other.app.pro.monthly",
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(record.isActive(at: Date()))
    }

    func testFutureExpiryOfAKnownProductIsSubscribed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = SubscriptionEntitlementRecord(
            active: true,
            productID: SubscriptionConfig.monthlyProductID,
            expiresAt: now.addingTimeInterval(60)
        )
        XCTAssertTrue(record.isActive(at: now))
        XCTAssertFalse(record.isActive(at: now.addingTimeInterval(61)))
    }

    func testAppGroupRoundTripKeepsAnActiveRecord() {
        let expires = Date(timeIntervalSince1970: 1_800_000_000)
        let written = SubscriptionEntitlementRecord(
            active: true,
            productID: SubscriptionConfig.yearlyProductID,
            expiresAt: expires
        )
        SubscriptionEntitlementStore.write(written, to: defaults)

        guard let reader = UserDefaults(suiteName: suiteName) else {
            XCTFail("expected a defaults suite")
            return
        }
        let loaded = SubscriptionEntitlementStore.read(from: reader, at: expires.addingTimeInterval(-10))
        XCTAssertTrue(loaded.isActive(at: expires.addingTimeInterval(-10)))
        XCTAssertEqual(loaded.productID, SubscriptionConfig.yearlyProductID)
        XCTAssertEqual(loaded.expiresAt, expires)
    }

    func testStoredExpiryIsReportedInactive() {
        let expires = Date(timeIntervalSince1970: 1_800_000_000)
        SubscriptionEntitlementStore.write(
            SubscriptionEntitlementRecord(
                active: true,
                productID: SubscriptionConfig.monthlyProductID,
                expiresAt: expires
            ),
            to: defaults
        )
        let loaded = SubscriptionEntitlementStore.read(from: defaults, at: expires.addingTimeInterval(1))
        XCTAssertFalse(loaded.active)
        XCTAssertEqual(loaded.productID, SubscriptionConfig.monthlyProductID)
        XCTAssertEqual(loaded.expiresAt, expires)
    }

    func testMalformedJSONIsNotSubscribed() {
        defaults.set(Data("not-json".utf8), forKey: SubscriptionEntitlementStore.storageKey)
        let loaded = SubscriptionEntitlementStore.read(from: defaults)
        XCTAssertFalse(loaded.isActive(at: Date()))
    }

    func testProductIDsUseTheAppBundlePrefix() {
        XCTAssertEqual(SubscriptionConfig.monetization, .allFeaturesSubscribed)
        XCTAssertTrue(SubscriptionConfig.keyboardRequiresSubscription)
        XCTAssertTrue(SubscriptionConfig.fixRequiresSubscription)
        XCTAssertFalse(
            KeyboardLock.isLocked(
                requiresSubscription: false,
                canReadEntitlement: true,
                entitled: false
            )
        )
        XCTAssertEqual(
            SubscriptionConfig.monthlyProductID,
            "app.access.keyboard.6M3Z27M69P.pro.monthly"
        )
        XCTAssertEqual(
            SubscriptionConfig.yearlyProductID,
            "app.access.keyboard.6M3Z27M69P.pro.yearly"
        )
        XCTAssertTrue(SubscriptionConfig.showTrialHeadlineDefault)
    }

    func testPaywallJSONOnlyChangesTheHeadline() {
        XCTAssertEqual(PaywallPresentation.resolved(json: nil), .codeDefault)
        XCTAssertEqual(PaywallPresentation.resolved(json: Data("{}".utf8)), .codeDefault)
        XCTAssertEqual(
            PaywallPresentation.resolved(json: Data("{\"showTrialHeadline\":\"yes\"}".utf8)),
            .codeDefault
        )
        let hidden = PaywallPresentation.resolved(
            json: Data("{\"showTrialHeadline\":false,\"active\":true,\"trialDays\":14}".utf8)
        )
        XCTAssertFalse(hidden.showTrialHeadline)
        let shown = PaywallPresentation.resolved(json: Data("{\"showTrialHeadline\":true}".utf8))
        XCTAssertTrue(shown.showTrialHeadline)
    }

    // MARK: Lifetime

    func testLifetimeHasNoExpiryAndIsActive() {
        let record = SubscriptionEntitlementRecord(
            active: true,
            productID: SubscriptionConfig.lifetimeProductID,
            expiresAt: nil
        )
        XCTAssertTrue(record.isActive(at: Date.distantFuture))
        XCTAssertTrue(record.isLifetime)
    }

    func testInactiveLifetimeIsNotSubscribed() {
        let record = SubscriptionEntitlementRecord(
            active: false,
            productID: SubscriptionConfig.lifetimeProductID,
            expiresAt: nil
        )
        XCTAssertFalse(record.isActive(at: Date()))
        XCTAssertFalse(record.isLifetime)
    }

    func testLifetimeIsAKnownProductButNotASubscription() {
        XCTAssertTrue(SubscriptionConfig.productIDs.contains(SubscriptionConfig.lifetimeProductID))
        XCTAssertFalse(SubscriptionConfig.subscriptionProductIDs.contains(SubscriptionConfig.lifetimeProductID))
        XCTAssertEqual(SubscriptionConfig.lifetimeProductID, "app.access.keyboard.6M3Z27M69P.pro.lifetime")
        XCTAssertEqual(SubscriptionConfig.displayOrder.last, SubscriptionConfig.lifetimeProductID)
        XCTAssertEqual(Set(SubscriptionConfig.displayOrder), SubscriptionConfig.productIDs)
    }

    func testGrantedLifetimeTransactionNeedsNoExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = SubscriptionEntitlementRecord.granted(
            productID: SubscriptionConfig.lifetimeProductID,
            expirationDate: nil,
            revocationDate: nil,
            at: now
        )
        XCTAssertEqual(record?.isActive(at: now), true)
        XCTAssertNil(record?.expiresAt)
    }

    func testGrantedRevokedLifetimeGivesNothing() {
        XCTAssertNil(SubscriptionEntitlementRecord.granted(
            productID: SubscriptionConfig.lifetimeProductID,
            expirationDate: nil,
            revocationDate: Date(),
            at: Date()
        ))
    }

    func testGrantedPlanStillNeedsAFutureExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(SubscriptionEntitlementRecord.granted(
            productID: SubscriptionConfig.monthlyProductID, expirationDate: nil, revocationDate: nil, at: now
        ))
        XCTAssertNil(SubscriptionEntitlementRecord.granted(
            productID: SubscriptionConfig.monthlyProductID, expirationDate: now.addingTimeInterval(-1), revocationDate: nil, at: now
        ))
        XCTAssertNil(SubscriptionEntitlementRecord.granted(
            productID: "other.app.pro.lifetime", expirationDate: nil, revocationDate: nil, at: now
        ))
        XCTAssertNotNil(SubscriptionEntitlementRecord.granted(
            productID: SubscriptionConfig.yearlyProductID, expirationDate: now.addingTimeInterval(60), revocationDate: nil, at: now
        ))
    }

    func testPreferredPicksLifetimeOverAnyPlan() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = SubscriptionEntitlementRecord(
            active: true, productID: SubscriptionConfig.yearlyProductID, expiresAt: now.addingTimeInterval(86_400 * 300)
        )
        let lifetime = SubscriptionEntitlementRecord(
            active: true, productID: SubscriptionConfig.lifetimeProductID, expiresAt: nil
        )
        XCTAssertEqual(SubscriptionEntitlementRecord.preferred(plan, lifetime, at: now), lifetime)
        XCTAssertEqual(SubscriptionEntitlementRecord.preferred(lifetime, plan, at: now), lifetime)
        XCTAssertEqual(SubscriptionEntitlementRecord.preferred(.inactive, plan, at: now), plan)
        XCTAssertEqual(SubscriptionEntitlementRecord.preferred(.inactive, .inactive, at: now), .inactive)
    }

    func testPreferredPicksTheLaterPlanExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = SubscriptionEntitlementRecord(
            active: true, productID: SubscriptionConfig.monthlyProductID, expiresAt: now.addingTimeInterval(60)
        )
        let later = SubscriptionEntitlementRecord(
            active: true, productID: SubscriptionConfig.yearlyProductID, expiresAt: now.addingTimeInterval(6_000)
        )
        XCTAssertEqual(SubscriptionEntitlementRecord.preferred(soon, later, at: now), later)
        XCTAssertEqual(SubscriptionEntitlementRecord.preferred(later, soon, at: now), later)
    }

    func testLifetimeRoundTripsThroughTheSharedStore() {
        let record = SubscriptionEntitlementRecord(
            active: true, productID: SubscriptionConfig.lifetimeProductID, expiresAt: nil
        )
        SubscriptionEntitlementStore.write(record, to: defaults)
        let read = SubscriptionEntitlementStore.read(from: defaults, at: Date.distantFuture)
        XCTAssertTrue(read.isActive(at: Date.distantFuture))
        XCTAssertTrue(read.isLifetime)
    }

    func testLockedMessageDoesNotPromiseATrial() {
        XCTAssertFalse(KeyboardLock.trialMessage.localizedCaseInsensitiveContains("trial"))
        XCTAssertFalse(FixNotice.consent.message.contains("—"))
        XCTAssertTrue(FixNotice.consent.message.contains("paragraph"))
    }
}
