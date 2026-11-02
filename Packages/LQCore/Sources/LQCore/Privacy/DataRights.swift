import Foundation

/// The current privacy notice version shown in parent setup. Bump it when the
/// notice changes so adults see and acknowledge the new one.
public enum PrivacyNotice {
    public static let version = 1

    /// What data exists, where it lives, and how long it is kept. Shown in the
    /// parent area and mirrored in docs/PRIVACY_AND_CHILD_SAFETY.md.
    public static let dataInventory: [(data: String, whereKept: String, retention: String)] = [
        ("Optional nickname, age band, avatar, chosen Spanish variant", "This device only", "Until the profile is deleted"),
        ("Lesson progress, review schedule, assessment results", "This device only", "Until the profile is deleted"),
        ("Minutes and activities per day", "This device only", "\(ActivityLog.retentionDays) days, then pruned automatically"),
        ("Purchase status (if paid plans are ever enabled)", "This device + Apple", "Apple's records; the app keeps only plan and expiry"),
        ("Speech audio (on-device recognition, only if a grown-up allows it)", "Processed in memory on this device", "Never stored or sent"),
    ]
}

public enum FamilyError: Error, Equatable {
    case profileLimitReached(max: Int)
    case notFound
}

/// Family profile management and the parent's data rights (export, delete).
public enum FamilyManager {
    public static func addProfile(_ p: PlayerProfile, to save: inout FamilySave, config: StoreConfig = .default, now: Date = Date()) throws {
        let plan = EntitlementResolver.effectivePlan(save.entitlement, config: config, now: now)
        guard FeatureGate.isAvailable(.profileSlot(index: save.profiles.count), plan: plan, config: config) else {
            throw FamilyError.profileLimitReached(max: plan == .familyPlus ? config.maxProfilesPlus : config.maxProfilesFree)
        }
        save.profiles.append(p)
        if save.activeProfileId == nil { save.activeProfileId = p.id }
    }

    public static func deleteProfile(_ id: UUID, from save: inout FamilySave) throws {
        guard let i = save.profiles.firstIndex(where: { $0.id == id }) else { throw FamilyError.notFound }
        save.profiles.remove(at: i)
        if save.activeProfileId == id { save.activeProfileId = save.profiles.first?.id }
    }

    /// Human-readable JSON export of one profile, for a parent's records.
    public static func export(_ p: PlayerProfile) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(ExportFile(exportedAt: Date(), app: "Language Quest", formatVersion: 1, profile: p))
    }

    /// Erases every profile, parent setting, and cached entitlement on the device.
    public static func deleteEverything(store: SaveStore) throws -> FamilySave {
        try store.deleteAll()
        return FamilySave()
    }

    struct ExportFile: Codable {
        var exportedAt: Date
        var app: String
        var formatVersion: Int
        var profile: PlayerProfile
    }
}
