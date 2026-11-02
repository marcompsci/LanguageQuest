import Foundation

public enum Plan: String, Codable, Sendable { case explorer, familyPlus }

/// Store configuration. Prices are NOT here: they come from the App Store
/// (StoreKit `Product.displayPrice`) so they can change without an app update.
public struct StoreConfig: Codable, Hashable, Sendable {
    /// Paid plans stay off until legal, technical, and unit-economics review.
    public var paidPlansEnabled: Bool
    public var monthlyProductId: String
    public var yearlyProductId: String
    public var subscriptionGroupId: String
    public var maxProfilesFree: Int
    public var maxProfilesPlus: Int
    /// How long a passed parental gate stays valid for a purchase flow.
    public var parentGateValiditySeconds: Double

    public static let `default` = StoreConfig(
        paidPlansEnabled: false,
        monthlyProductId: "com.phoronomics.languagequest.familyplus.monthly",
        yearlyProductId: "com.phoronomics.languagequest.familyplus.yearly",
        subscriptionGroupId: "familyplus",
        maxProfilesFree: 2,
        maxProfilesPlus: 4,
        parentGateValiditySeconds: 120
    )

    public var productIds: [String] { [monthlyProductId, yearlyProductId] }
}

public enum Feature: Hashable, Sendable {
    // Essential: never behind payment.
    case lessons(unitOrder: Int)
    case review
    case correctionFeedback
    case hints
    case placementTest
    case retentionChecks
    case parentDashboard
    case dataExportAndDeletion
    case accessibilitySettings
    // Optional extras.
    case advancedWorld
    case extraCosmetics
    case profileSlot(index: Int)

    /// Units 1–3 (the Starter Village curriculum) are always free.
    public static let freeUnitCount = 3

    public var isEssential: Bool {
        switch self {
        case .lessons(let n): return n <= Feature.freeUnitCount
        case .review, .correctionFeedback, .hints, .placementTest, .retentionChecks,
             .parentDashboard, .dataExportAndDeletion, .accessibilitySettings:
            return true
        case .advancedWorld, .extraCosmetics, .profileSlot:
            return false
        }
    }
}

public enum FeatureGate {
    public static func isAvailable(_ f: Feature, plan: Plan, config: StoreConfig = .default) -> Bool {
        if f.isEssential { return true }
        switch f {
        case .profileSlot(let i):
            let max = plan == .familyPlus ? config.maxProfilesPlus : config.maxProfilesFree
            return i < max
        case .lessons, .advancedWorld, .extraCosmetics:
            return plan == .familyPlus
        default:
            return true
        }
    }
}

/// A verified transaction, reduced to what entitlement logic needs.
/// The app maps StoreKit 2 `VerificationResult<Transaction>` to this; unverified
/// transactions must never be mapped (they are dropped before this point).
public struct VerifiedTransaction: Codable, Hashable, Sendable {
    public var productId: String
    public var purchaseDate: Date
    public var expirationDate: Date?
    public var revocationDate: Date?
    public var isUpgraded: Bool
    public var familyShared: Bool

    public init(productId: String, purchaseDate: Date, expirationDate: Date?, revocationDate: Date? = nil,
                isUpgraded: Bool = false, familyShared: Bool = false) {
        self.productId = productId; self.purchaseDate = purchaseDate; self.expirationDate = expirationDate
        self.revocationDate = revocationDate; self.isUpgraded = isUpgraded; self.familyShared = familyShared
    }
}

public struct EntitlementSnapshot: Codable, Hashable, Sendable {
    public var plan: Plan = .explorer
    public var expiresAt: Date? = nil
    public var familyShared = false
    public var lastVerified: Date? = nil
    public init() {}
}

public enum EntitlementResolver {
    /// Grace allowance for clock skew only. Billing grace periods are reflected
    /// by StoreKit in the transaction's expiration date.
    public static let clockSkew: TimeInterval = 5 * 60

    public static func resolve(_ txs: [VerifiedTransaction], config: StoreConfig, now: Date) -> EntitlementSnapshot {
        var snap = EntitlementSnapshot()
        snap.lastVerified = now
        guard config.paidPlansEnabled else { return snap }
        let active = txs.filter { t in
            config.productIds.contains(t.productId)
                && t.revocationDate == nil
                && !t.isUpgraded
                && t.purchaseDate <= now.addingTimeInterval(clockSkew)
                && (t.expirationDate.map { $0.addingTimeInterval(clockSkew) > now } ?? false)
        }
        guard let best = active.max(by: { ($0.expirationDate ?? .distantPast) < ($1.expirationDate ?? .distantPast) }) else { return snap }
        snap.plan = .familyPlus
        snap.expiresAt = best.expirationDate
        snap.familyShared = best.familyShared
        return snap
    }

    /// Offline use of the cached snapshot: trust it until it expires.
    public static func effectivePlan(_ s: EntitlementSnapshot, config: StoreConfig, now: Date) -> Plan {
        guard config.paidPlansEnabled, s.plan == .familyPlus, let exp = s.expiresAt else { return .explorer }
        return exp.addingTimeInterval(clockSkew) > now ? .familyPlus : .explorer
    }
}

public enum PurchaseGateDecision: Equatable, Sendable {
    case plansDisabled
    case purchasesNotAllowedByParent
    case needsParentGate
    case allowed
}

/// Whether the purchase sheet may be shown. Every purchase, restore-with-
/// purchase, or external link requires a fresh parental gate.
public enum PurchaseGate {
    public static func decide(config: StoreConfig, parent: ParentSettings, gatePassedAt: Date?, now: Date) -> PurchaseGateDecision {
        guard config.paidPlansEnabled else { return .plansDisabled }
        guard let passed = gatePassedAt, now.timeIntervalSince(passed) >= 0,
              now.timeIntervalSince(passed) <= config.parentGateValiditySeconds else { return .needsParentGate }
        guard parent.purchasesAllowed else { return .purchasesNotAllowedByParent }
        return .allowed
    }
}
