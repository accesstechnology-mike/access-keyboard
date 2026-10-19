import AccessKeyboardCore
import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var record: SubscriptionEntitlementRecord = .inactive
    @Published private(set) var presentation: PaywallPresentation = .codeDefault
    @Published private(set) var introEligibleProductIDs: Set<String> = []
    @Published private(set) var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { await observeTransactions() }
        Task { await refresh() }
    }

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
        await refreshIntroEligibility()
        await loadPresentation()
    }

    func purchase(_ product: Product) async {
        statusMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                statusMessage = record.isActive(at: Date()) ? "Pro is active." : nil
            case .userCancelled:
                break
            case .pending:
                statusMessage = "This purchase is waiting for approval."
            @unknown default:
                statusMessage = "The purchase did not go through. You can try again."
            }
        } catch {
            statusMessage = "The purchase did not go through. You can try again."
        }
    }

    func restore() async {
        statusMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            statusMessage = "Restore did not finish. You can try again."
            return
        }
        await refreshEntitlements()
        statusMessage = record.isActive(at: Date())
            ? "Pro is active."
            : "No Pro purchase was found for this Apple Account."
    }

    func introductoryOffer(for product: Product) -> Product.SubscriptionOffer? {
        guard presentation.showTrialHeadline else { return nil }
        guard introEligibleProductIDs.contains(product.id) else { return nil }
        return product.subscription?.introductoryOffer
    }

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: SubscriptionConfig.productIDs)
            products = SubscriptionConfig.displayOrder.compactMap { id in
                loaded.first { $0.id == id }
            }
            if products.isEmpty {
                statusMessage = "Pro options are not available right now. Check your connection and try again."
            }
        } catch {
            products = []
            statusMessage = "Pro options are not available right now. Check your connection and try again."
        }
    }

    private func refreshEntitlements() async {
        let now = Date()
        var best: SubscriptionEntitlementRecord = .inactive
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            if let candidate = SubscriptionEntitlementRecord.granted(
                productID: transaction.productID,
                expirationDate: transaction.expirationDate,
                revocationDate: transaction.revocationDate,
                at: now
            ) {
                best = SubscriptionEntitlementRecord.preferred(best, candidate, at: now)
            }
            await transaction.finish()
        }
        SubscriptionEntitlementStore.writeShared(best)
        record = SubscriptionEntitlementStore.readShared(at: now)
    }

    private func refreshIntroEligibility() async {
        var eligible: Set<String> = []
        for product in products {
            guard let subscription = product.subscription, subscription.introductoryOffer != nil else { continue }
            if await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        introEligibleProductIDs = eligible
    }

    private func loadPresentation() async {
        var request = URLRequest(url: SubscriptionConfig.remoteConfigURL)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return
            }
            presentation = PaywallPresentation.resolved(json: data)
        } catch {
            return
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? verified(result) else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionStoreError.unverified
        case .verified(let value):
            return value
        }
    }

    /// Called when the offer code sheet closes. A redeemed code arrives as a
    /// transaction (also seen by `Transaction.updates`), so refresh either way.
    func finishCodeRedemption(_ result: Result<Void, Error>) async {
        statusMessage = nil
        if case .failure = result {
            statusMessage = "The code was not redeemed. Check it and try again."
            return
        }
        await refreshEntitlements()
        if record.isActive(at: Date()) {
            statusMessage = record.isLifetime ? "Pro Lifetime is active." : "Pro is active."
        }
    }
}

private enum SubscriptionStoreError: Error {
    case unverified
}
