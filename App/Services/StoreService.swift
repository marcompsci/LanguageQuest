import StoreKit
import LQCore

/// StoreKit 2 wrapper. Paid plans are OFF (StoreConfig.paidPlansEnabled == false)
/// until legal, technical, and unit-economics review, so in this build nothing
/// here is reachable from the child-facing UI. Prices always come from the App
/// Store (`displayPrice`), never from code.
@MainActor
final class StoreService: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var lastError: String?
    let config: StoreConfig

    init(config: StoreConfig) { self.config = config }

    func loadProducts() async {
        guard config.paidPlansEnabled else { products = []; return }
        do {
            products = try await Product.products(for: config.productIds).sorted { $0.price < $1.price }
        } catch {
            lastError = "The App Store isn't reachable right now."
        }
    }

    enum PurchaseResult { case purchased, pending, cancelled, failed }

    /// Call only after `PurchaseGate.decide` returns `.allowed`.
    func purchase(_ product: Product) async -> PurchaseResult {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let tx) = verification else { return .failed }
                await tx.finish()
                return .purchased
            case .pending:
                return .pending   // e.g. Ask to Buy waiting for a parent
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            lastError = error.localizedDescription
            return .failed
        }
    }

    /// Restore: asks the App Store to sync, then entitlements are re-read.
    func restore() async {
        do { try await AppStore.sync() } catch { lastError = "Restore didn't finish. Please try again." }
    }

    /// Only cryptographically verified transactions are mapped; unverified ones are dropped.
    func currentVerifiedTransactions() async -> [VerifiedTransaction] {
        guard config.paidPlansEnabled else { return [] }
        var out: [VerifiedTransaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            out.append(VerifiedTransaction(productId: t.productID, purchaseDate: t.purchaseDate,
                                           expirationDate: t.expirationDate, revocationDate: t.revocationDate,
                                           isUpgraded: t.isUpgraded, familyShared: t.ownershipType == .familyShared))
        }
        return out
    }

    /// Listens for renewals, refunds, and Ask to Buy approvals for the app's lifetime.
    func listenForTransactions(onChange: @escaping () async -> Void) async {
        await onChange()
        guard config.paidPlansEnabled else { return }
        for await result in Transaction.updates {
            if case .verified(let t) = result { await t.finish() }
            await onChange()
        }
    }
}
