import Foundation

/// Parent-level settings and consent. Stored on device only.
public struct ParentSettings: Codable, Hashable, Sendable {
    /// Set once an adult has completed parent setup behind the parental gate.
    public var setupCompleted = false
    /// Version of the privacy notice the adult acknowledged.
    public var privacyNoticeVersion: Int? = nil
    public var privacyNoticeAcknowledgedAt: Date? = nil
    /// The adult allowed on-device speech recognition (microphone). Off by default.
    public var allowOnDeviceSpeech = false
    /// Cloud sync is not implemented. Kept so the save format is ready; must stay false.
    public var allowCloudSync = false
    public var dailyLimitMinutes: Int? = nil
    public var purchasesAllowed = false
    /// Added in v0.8: practice reminders a parent set up (local notifications only). nil = never set.
    public var reminders: ReminderPlan? = nil
    public init() {}
}

/// Everything saved on the device.
public struct FamilySave: Codable, Hashable, Sendable {
    public static let currentVersion = 2
    public var version: Int = FamilySave.currentVersion
    public var profiles: [PlayerProfile] = []
    public var activeProfileId: UUID? = nil
    public var parent = ParentSettings()
    public var entitlement = EntitlementSnapshot()
    public init() {}

    public var activeProfile: PlayerProfile? {
        get { profiles.first { $0.id == activeProfileId } ?? profiles.first }
        set {
            guard let p = newValue else { return }
            if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p } else { profiles.append(p) }
        }
    }
}

public protocol SaveStore: AnyObject {
    func load() throws -> FamilySave?
    func save(_ s: FamilySave) throws
    func deleteAll() throws
}

public enum SaveError: Error, Equatable {
    case unsupportedVersion(Int)
    case corrupt
}

/// Versioned envelope so the format can migrate.
struct SaveEnvelope: Codable {
    var version: Int
    var savedAt: Date
    var save: FamilySave
}

/// Versioned JSON file with an atomic write and a backup copy.
/// If the main file is unreadable, the backup is used.
public final class FileSaveStore: SaveStore {
    public let directory: URL
    private let fm = FileManager.default
    private var mainURL: URL { directory.appendingPathComponent("family.json") }
    private var backupURL: URL { directory.appendingPathComponent("family.backup.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func load() throws -> FamilySave? {
        let hasMain = fm.fileExists(atPath: mainURL.path)
        let hasBackup = fm.fileExists(atPath: backupURL.path)
        if !hasMain && !hasBackup { return nil }
        if hasMain, let s = try? Self.read(mainURL) { return s }
        if hasBackup, let s = try? Self.read(backupURL) { return s }
        // Surface unsupported-version errors rather than silently discarding data.
        if hasMain { _ = try Self.read(mainURL) }
        throw SaveError.corrupt
    }

    static func read(_ url: URL) throws -> FamilySave {
        let data = try Data(contentsOf: url)
        return try SaveMigrator.decode(data)
    }

    public func save(_ s: FamilySave) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var copy = s
        copy.version = FamilySave.currentVersion
        let data = try Self.encoder.encode(SaveEnvelope(version: FamilySave.currentVersion, savedAt: Date(), save: copy))
        if fm.fileExists(atPath: mainURL.path) {
            _ = try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: mainURL, to: backupURL)
        }
        #if os(iOS)
        try data.write(to: mainURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: mainURL, options: [.atomic])
        #endif
    }

    /// Deletes every save file: main, backup and any quarantined unreadable copies.
    public func deleteAll() throws {
        for u in [mainURL, backupURL] where fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
        let others = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in others where name.hasPrefix("family.") && name.contains(".unreadable-") {
            try fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Removes the backup copy (used after deleting an explorer so the backup can't still hold them).
    public func purgeBackup() {
        if fm.fileExists(atPath: backupURL.path) { try? fm.removeItem(at: backupURL) }
    }

    /// Moves unreadable save files aside (never deletes them) so starting fresh can't
    /// overwrite progress a newer or repaired app version might still read.
    /// Returns the quarantined file URLs.
    @discardableResult
    public func quarantineUnreadable(now: Date = Date()) -> [URL] {
        let stamp = Int(now.timeIntervalSince1970)
        var moved: [URL] = []
        for (u, name) in [(mainURL, "family"), (backupURL, "family.backup")] where fm.fileExists(atPath: u.path) {
            let dest = directory.appendingPathComponent("\(name).unreadable-\(stamp).json")
            if (try? fm.moveItem(at: u, to: dest)) != nil { moved.append(dest) }
        }
        return moved
    }
}

public final class MemorySaveStore: SaveStore {
    public private(set) var data: Data?
    public init() {}
    public func load() throws -> FamilySave? {
        guard let d = data else { return nil }
        return try SaveMigrator.decode(d)
    }
    public func save(_ s: FamilySave) throws {
        data = try FileSaveStore.encoder.encode(SaveEnvelope(version: FamilySave.currentVersion, savedAt: Date(), save: s))
    }
    public func deleteAll() throws { data = nil }
    /// Test hook: store raw bytes (e.g. an old-format save).
    public func setRaw(_ d: Data) { data = d }
}

/// Upgrades old saves. v1 (prototype) stored a single profile at the top level
/// with no parent block or entitlement.
public enum SaveMigrator {
    struct Probe: Decodable { var version: Int }
    struct V1: Decodable {
        var version: Int
        var savedAt: Date
        var profile: PlayerProfile
    }

    public static func decode(_ data: Data) throws -> FamilySave {
        let d = FileSaveStore.decoder
        let probe: Probe
        do { probe = try d.decode(Probe.self, from: data) } catch { throw SaveError.corrupt }
        switch probe.version {
        case 1:
            guard let v1 = try? d.decode(V1.self, from: data) else { throw SaveError.corrupt }
            var s = FamilySave()
            s.profiles = [v1.profile]
            s.activeProfileId = v1.profile.id
            return s
        case FamilySave.currentVersion:
            guard let env = try? d.decode(SaveEnvelope.self, from: data) else { throw SaveError.corrupt }
            return env.save
        default:
            throw SaveError.unsupportedVersion(probe.version)
        }
    }
}
