import Foundation

/// Original pixel avatar options. All parts are drawn in code (see App/Game/PixelArt.swift).
public struct AvatarConfig: Codable, Hashable, Sendable {
    public var body: Int = 0        // body/skin tone index
    public var hair: Int = 0        // hair style index
    public var hairColor: Int = 0
    public var outfit: Int = 0      // outfit color index
    public var hat: String? = nil   // cosmetic id
    public var accessory: String? = nil

    public init(body: Int = 0, hair: Int = 0, hairColor: Int = 0, outfit: Int = 0, hat: String? = nil, accessory: String? = nil) {
        self.body = body; self.hair = hair; self.hairColor = hairColor; self.outfit = outfit
        self.hat = hat; self.accessory = accessory
    }

    public static let bodyCount = 6
    public static let hairCount = 5
    public static let hairColorCount = 6
    public static let outfitCount = 8
}

public enum ThemeKind: String, Codable, CaseIterable, Sendable {
    /// Bright and rounded (default for 10–12).
    case playful
    /// Dusk palette, sleeker UI, denser text (default for 13+).
    case explorer
}

public enum SpeechPracticeMode: String, Codable, CaseIterable, Sendable {
    /// Say it aloud, then tap how it went. No microphone used.
    case selfCheck
    /// On-device speech recognition only. Audio never leaves the device and is not stored.
    case onDevice
    /// Speaking activities are skipped (still offered as listen-and-repeat).
    case off
}

public struct LearnerSettings: Codable, Hashable, Sendable {
    public var reducedMotion = false
    public var soundEffects = true
    public var music = true
    public var voiceVolume = 1.0
    public var speechRate = 0.42
    public var subtitles = true
    public var readAloudInstructions = false
    public var textScale = 1.0
    public var colorBlindSymbols = true
    public var sessionReminderMinutes: Int? = 25
    /// Show romaji under Japanese text. nil (older saves) = on.
    public var showRomanization: Bool? = nil
    /// Background music level 0…1. nil (older saves) = the quiet default.
    public var musicVolume: Double? = nil

    public static let defaultMusicVolume = 0.35
    public var musicLevel: Double { musicVolume ?? Self.defaultMusicVolume }

    public var romanizationOn: Bool { showRomanization ?? true }

    public init() {}
}

public struct ActivityRecord: Codable, Hashable, Sendable {
    public var firstTryCorrect: Bool
    public var bestAttempts: Int
    public var completions: Int
    public var lastCompleted: Date
}

public struct CourseProgress: Codable, Hashable, Sendable {
    public var startedQuests: Set<String> = []
    public var completedQuests: Set<String> = []
    public var completedActivities: [String: ActivityRecord] = [:]
    public var passedMasteryChecks: Set<String> = []
    public var placedOutUnits: Set<String> = []
    public var flags: Set<String> = []
    public init() {}
}

public struct RewardState: Codable, Hashable, Sendable {
    public var xp = 0
    public var ownedCosmetics: Set<String> = []
    public var badges: Set<String> = []
    public init() {}
}

public enum AssessmentKind: String, Codable, Sendable { case baseline, retention, masteryCheck }

public struct SkillScore: Codable, Hashable, Sendable {
    public var correct = 0
    public var total = 0
    public init(correct: Int = 0, total: Int = 0) { self.correct = correct; self.total = total }
    public var percent: Int { total == 0 ? 0 : Int((Double(correct) / Double(total) * 100).rounded()) }
}

public struct AssessmentResult: Codable, Hashable, Sendable {
    public var kind: AssessmentKind
    public var date: Date
    public var unitId: String?
    public var bySkill: [Skill: SkillScore]
    public var passed: Bool?

    public init(kind: AssessmentKind, date: Date, unitId: String?, bySkill: [Skill: SkillScore], passed: Bool?) {
        self.kind = kind; self.date = date; self.unitId = unitId; self.bySkill = bySkill; self.passed = passed
    }

    public var overall: SkillScore {
        bySkill.values.reduce(SkillScore()) { SkillScore(correct: $0.correct + $1.correct, total: $0.total + $1.total) }
    }
}

/// Minutes played per day. Kept on device for `ActivityLog.retentionDays` only.
public struct ActivityLog: Codable, Hashable, Sendable {
    public static let retentionDays = 60
    /// Key: "yyyy-MM-dd" in the device calendar.
    public var minutesByDay: [String: Double] = [:]
    public var activitiesByDay: [String: Int] = [:]
    public init() {}

    public mutating func prune(now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        let cutoffKey = Self.dayKey(cutoff, calendar: calendar)
        minutesByDay = minutesByDay.filter { $0.key >= cutoffKey }
        activitiesByDay = activitiesByDay.filter { $0.key >= cutoffKey }
    }

    public static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// One learner. Stored only on this device. There is deliberately no birthdate,
/// email, real name, or location: a nickname is optional and never leaves the device.
public struct PlayerProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var nickname: String
    public var ageBand: AgeBand
    public var avatar: AvatarConfig
    public var courseId: String
    public var variant: String
    public var theme: ThemeKind
    public var createdAt: Date
    public var settings: LearnerSettings
    public var progress: CourseProgress
    public var knowledge: [String: ItemKnowledge]
    public var assessments: [AssessmentResult]
    public var rewards: RewardState
    public var log: ActivityLog
    public var lastScene: String?
    public var lastPosition: GridPoint?
    /// Side games and exploration (optional so older saves still load).
    public var extras: ExtrasProgress?
    /// Progress in courses other than the active one, by course id.
    public var otherCourses: [String: CourseSnapshot]?
    /// The last quest practiced, in any language (for the menu's Recent lesson card).
    public var recentLesson: RecentLesson?

    public init(id: UUID = UUID(), nickname: String, ageBand: AgeBand, avatar: AvatarConfig = .init(),
                courseId: String = "en-es", variant: String, now: Date = Date()) {
        self.id = id
        self.nickname = String(nickname.prefix(PlayerProfile.maxNicknameLength))
        self.ageBand = ageBand
        self.avatar = avatar
        self.courseId = courseId
        self.variant = variant
        self.theme = ageBand.defaultTheme
        self.createdAt = now
        var s = LearnerSettings()
        s.readAloudInstructions = ageBand.readAloudByDefault
        s.textScale = 1.0
        self.settings = s
        self.progress = CourseProgress()
        self.knowledge = [:]
        self.assessments = []
        self.rewards = RewardState()
        self.log = ActivityLog()
    }

    public static let maxNicknameLength = 16

    /// Trims and limits a nickname; strips anything that looks like contact info.
    public static func sanitizeNickname(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = String(s.filter { $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" })
        s = s.split(separator: " ").joined(separator: " ")
        return String(s.prefix(maxNicknameLength))
    }
}

/// Everything that belongs to one course, so a learner can switch languages
/// and come back later without losing progress. XP, cosmetics, badges, the
/// avatar and settings are shared across languages.
public struct CourseSnapshot: Codable, Hashable, Sendable {
    public var variant: String
    public var progress: CourseProgress
    public var knowledge: [String: ItemKnowledge]
    public var assessments: [AssessmentResult]
    public var extras: ExtrasProgress?
}

extension PlayerProfile {
    /// Ids of courses this learner has started (including the active one).
    public var startedCourses: [String] { [courseId] + (otherCourses ?? [:]).keys.sorted() }

    /// Switches the active course, parking the current one. Returning to a course restores it.
    public mutating func switchCourse(to id: String, defaultVariant: String) {
        guard id != courseId else { return }
        var others = otherCourses ?? [:]
        others[courseId] = CourseSnapshot(variant: variant, progress: progress, knowledge: knowledge,
                                          assessments: assessments, extras: extras)
        if let back = others.removeValue(forKey: id) {
            variant = back.variant; progress = back.progress; knowledge = back.knowledge
            assessments = back.assessments; extras = back.extras
        } else {
            variant = defaultVariant; progress = CourseProgress(); knowledge = [:]; assessments = []; extras = nil
        }
        courseId = id
        otherCourses = others.isEmpty ? nil : others
        lastPosition = nil
    }
}
