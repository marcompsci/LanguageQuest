import Foundation

// v1.2: twenty-five improvements. Everything stays on the device.

extension MetaEvent {
    static let trickyDrill = "trickyDrill"
    static let dictationPerfect = "dictationPerfect"
    static let pathComplete = "pathComplete"
    static let freezeEarned = "freezeEarned"
}

// MARK: - 1. Tricky words ("leeches": words that keep slipping away)

public enum TrickyWords {
    public static let lapseThreshold = 3

    /// Words missed again and again: 3+ lapses, or missed in 2+ recent quizzes. They get a drill of their own.
    public static func ids(_ p: PlayerProfile) -> [String] {
        var missedInQuizzes: [String: Int] = [:]
        for r in (p.extrasOrEmpty.quizHistory ?? []).suffix(30) { for m in r.missed { missedInQuizzes[m, default: 0] += 1 } }
        return p.knowledge.compactMap { id, k in
            let lapses = k.comprehension.lapses + k.production.lapses
            return lapses >= lapseThreshold || (missedInQuizzes[id] ?? 0) >= 2 ? id : nil
        }.sorted { a, b in
            let la = (p.knowledge[a]?.comprehension.lapses ?? 0) + (p.knowledge[a]?.production.lapses ?? 0)
            let lb = (p.knowledge[b]?.comprehension.lapses ?? 0) + (p.knowledge[b]?.production.lapses ?? 0)
            return la == lb ? a < b : la > lb
        }
    }

    public static func isTricky(_ id: String, in p: PlayerProfile) -> Bool { ids(p).contains(id) }
}

// MARK: - 2. "Almost!": show exactly what was different

public struct DiffChar: Hashable, Sendable {
    public var char: Character
    /// true = matches the right answer; false = extra or wrong in what was typed.
    public var ok: Bool
}

public enum TypoDiff {
    /// Marks each typed character as matching or not, by the longest common subsequence with the answer
    /// (accents and capitals ignored, like the answer checker).
    public static func marks(typed: String, expected: String) -> [DiffChar] {
        let a = Array(typed), b = Array(expected)
        func norm(_ c: Character) -> String { String(c).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        guard !a.isEmpty else { return [] }
        guard !b.isEmpty else { return a.map { DiffChar(char: $0, ok: false) } }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = norm(a[i]) == norm(b[j]) ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [DiffChar] = []
        var i = 0, j = 0
        while i < a.count {
            if j < b.count && norm(a[i]) == norm(b[j]) { out.append(DiffChar(char: a[i], ok: true)); i += 1; j += 1 }
            else if j < b.count && dp[i][j + 1] >= dp[i + 1][j] { j += 1 }
            else { out.append(DiffChar(char: a[i], ok: false)); i += 1 }
        }
        return out
    }
}

// MARK: - 4. Sentence dictation (Listen & Type, sentence mode)

public struct DictationGame: Sendable {
    public static let rounds = 5
    public let sentences: [(text: String, english: String)]
    public private(set) var index = 0
    public private(set) var correct = 0

    public init(profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        sentences = Array(SentenceBuilder.candidates(profile, library: library).shuffled(using: &rng).prefix(Self.rounds))
    }

    public var current: (text: String, english: String)? { index < sentences.count ? sentences[index] : nil }
    public var isFinished: Bool { index >= sentences.count }

    /// Punctuation and capitals don't matter; small typos are forgiven like everywhere else.
    @discardableResult
    public mutating func submit(_ typed: String, variant: String, context: CheckContext) -> AnswerVerdict {
        guard let s = current else { return .incorrect(expected: "") }
        let strip: (String) -> String = { $0.filter { !".,!?¿¡;:…。，！？、「」\"'".contains($0) } }
        let v = AnswerChecker.check(strip(typed), accepted: [VText(strip(s.text))], variant: variant, context: context)
        if v.isCorrect { correct += 1 }
        index += 1
        return v
    }

    public static func finish(_ g: DictationGame, profile p: inout PlayerProfile) {
        if g.correct == g.sentences.count && !g.sentences.isEmpty { p.updateMeta { $0.counters[MetaEvent.dictationPerfect, default: 0] += 1 } }
    }
}

// MARK: - 5. Review size

public enum ReviewSize {
    public static let choices = [8, 12, 20]
    public static let defaultSize = 10
    public static func size(_ s: LearnerSettings) -> Int { s.reviewSize.flatMap { choices.contains($0) ? $0 : nil } ?? defaultSize }
}

// MARK: - 6. Today's path chest

extension TodayPath {
    public static let chestXP = 30

    public static func canOpenChest(_ steps: [PathStep], profile p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        steps.allSatisfy(\.done) && p.metaOrEmpty.pathChestDay != ActivityLog.dayKey(now, calendar: calendar)
    }

    /// +30 XP once a day when all three steps are done.
    @discardableResult
    public static func openChest(_ steps: [PathStep], profile p: inout PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        guard canOpenChest(steps, profile: p, now: now, calendar: calendar) else { return 0 }
        let day = ActivityLog.dayKey(now, calendar: calendar)
        p.updateMeta { $0.pathChestDay = day; $0.counters[MetaEvent.pathComplete, default: 0] += 1 }
        p.rewards.xp += chestXP
        return chestXP
    }
}

// MARK: - 9. Daily time limit (set by a parent)

public enum TimeLimit {
    public static let choices = [15, 30, 45, 60, 90]

    /// True when today's play time has reached the parent's limit (and a parent hasn't allowed more today).
    public static func isReached(minutesToday: Double, parent: ParentSettings, profile p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        guard let limit = parent.dailyLimitMinutes, limit > 0 else { return false }
        if p.metaOrEmpty.limitOverrideDay == ActivityLog.dayKey(now, calendar: calendar) { return false }
        return minutesToday >= Double(limit)
    }

    public static func allowMoreToday(profile p: inout PlayerProfile, now: Date, calendar: Calendar = .current) {
        let day = ActivityLog.dayKey(now, calendar: calendar)
        p.updateMeta { $0.limitOverrideDay = day }
    }
}

// MARK: - 10. Words learned this week

public enum WordsThisWeek {
    public static func ids(_ p: PlayerProfile, now: Date) -> [String] {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        return p.knowledge.filter { ($0.value.firstSeen ?? .distantPast) >= weekAgo }
            .sorted { ($0.value.firstSeen ?? .distantPast) > ($1.value.firstSeen ?? .distantPast) }.map(\.key)
    }
}

// MARK: - 13 + 14. How memory works: a word's forgetting curve

public struct CurvePoint: Hashable, Identifiable, Sendable {
    public var id: Double { day }
    public var day: Double
    public var recall: Double
}

extension RecallModel {
    /// Predicted recall over the next days with no practice (p = 2^(−Δ/h)).
    public static func curve(_ k: ItemKnowledge, now: Date, days: Int = 14) -> [CurvePoint] {
        (0...days * 2).map { i in
            let d = Double(i) / 2
            return CurvePoint(day: d, recall: probability(k, now: now.addingTimeInterval(d * 86400)) ?? 0)
        }
    }

    /// A made-up word for the explainer: the half-life doubles with each good review.
    public static func exampleCurves(days: Int = 30) -> [(label: String, points: [CurvePoint])] {
        [("After 1 review", 1.0), ("After 3 reviews", 4.0), ("After 5 reviews", 16.0)].map { label, h in
            (label, (0...days).map { CurvePoint(day: Double($0), recall: pow(2, -Double($0) / h)) })
        }
    }
}

// MARK: - 15. Level rewards (cosmetic only)

public enum LevelRewards {
    public static let byLevel: [Int: String] = [5: "goggles-explorer", 10: "cloak-polyglot"]

    /// Gives every level reward up to the current level that isn't owned yet. Returns what was new.
    @discardableResult
    public static func grant(profile p: inout PlayerProfile) -> [String] {
        let lvl = ExplorerLevel.level(forXP: p.rewards.xp)
        var new: [String] = []
        for (l, id) in byLevel.sorted(by: { $0.key < $1.key }) where lvl >= l {
            if p.rewards.ownedCosmetics.insert(id).inserted { new.append(id) }
        }
        return new
    }
}

// MARK: - 16. Reminder days off

extension SmartReminders {
    /// Removes reminders that fall on the player's days off (weekday numbers, 1 = Sunday).
    public static func respectingDaysOff(_ plan: [PlannedReminder], daysOff: [Int], calendar: Calendar = .current) -> [PlannedReminder] {
        guard !daysOff.isEmpty else { return plan }
        return plan.filter { !daysOff.contains(calendar.component(.weekday, from: $0.date)) }
    }
}

// MARK: - 17. Earn a streak freeze

extension Streak {
    public static let maxFreezes = 3

    /// A 10-question memory check earns one extra freeze, once a week, up to 3 in hand. Returns whether one was earned.
    @discardableResult
    public static func earnFreeze(_ p: inout PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        var s = state(p)
        refill(&s, now: now, calendar: calendar)
        let week = WeeklyGoal.weekKey(now, calendar: calendar)
        guard p.metaOrEmpty.freezeEarnedWeek != week, s.freezesLeft < maxFreezes else { return false }
        s.freezesLeft += 1
        let final = s
        p.updateMeta { $0.streak = final; $0.freezeEarnedWeek = week; $0.counters[MetaEvent.freezeEarned, default: 0] += 1 }
        return true
    }
}

// MARK: - 18. When the explorer usually practices

public struct HourCount: Hashable, Identifiable, Sendable {
    public var id: Int { hour }
    public var hour: Int
    public var sessions: Int
}

public enum PracticeTimes {
    public static func byHour(_ p: PlayerProfile, calendar: Calendar = .current) -> [HourCount] {
        var counts = Array(repeating: 0, count: 24)
        for d in p.metaOrEmpty.sessionStarts ?? [] { counts[calendar.component(.hour, from: d)] += 1 }
        return counts.enumerated().map { HourCount(hour: $0.offset, sessions: $0.element) }
    }

    public static func summary(_ p: PlayerProfile, calendar: Calendar = .current) -> String? {
        let h = byHour(p, calendar: calendar)
        guard h.map(\.sessions).reduce(0, +) >= 3, let top = h.max(by: { $0.sessions < $1.sessions }) else { return nil }
        let label: String
        switch top.hour {
        case 5..<12: label = "in the morning"
        case 12..<17: label = "in the afternoon"
        case 17..<21: label = "in the evening"
        default: label = "late"
        }
        return "Usually practices \(label)."
    }
}

// MARK: - 20 + 21. Tips and what's new (shown once)

public enum OnceMessages {
    public static let currentVersion = "1.3"

    public static let whatsNew: [String] = [
        "\"I guessed\": tell the quiz when a right answer was a guess, and the word comes back sooner.",
        "Lightning round: 60 seconds, as many words as you can.",
        "Look-alike words: practise words that are spelled almost the same.",
        "Quick 3 for busy days, and a listening-only memory check.",
        "Bedtime review in the evening: sleep helps new words stick.",
        "Word of the day, a 7-day review forecast and unit mastery rings.",
        "Mistake journal, today's report and a daily minutes goal.",
        "Haptics and big answer buttons in Settings.",
    ]

    public static func shouldShowWhatsNew(_ p: PlayerProfile) -> Bool {
        p.metaOrEmpty.whatsNewSeen != currentVersion && !p.knowledge.isEmpty
    }

    public static func markWhatsNew(_ p: inout PlayerProfile) { p.updateMeta { $0.whatsNewSeen = currentVersion } }

    public static func tipSeen(_ id: String, in p: PlayerProfile) -> Bool { (p.metaOrEmpty.tipsSeen ?? []).contains(id) }
    public static func markTip(_ id: String, profile p: inout PlayerProfile) {
        p.updateMeta { m in if !(m.tipsSeen ?? []).contains(id) { m.tipsSeen = (m.tipsSeen ?? []) + [id] } }
    }
}

// MARK: - Settings added in 1.2

extension LearnerSettings {
    public var quietModeOn: Bool { quietMode ?? false }
}

// MARK: - 23. Achievements

extension Achievement {
    static let v12: [Achievement] = [
        Achievement(id: "a-tricky", title: "Tricky Tamer", detail: "Do 3 tricky-word drills.", icon: "tortoise.fill"),
        Achievement(id: "a-dictation", title: "Dictation Star", detail: "Get every sentence right in a dictation.", icon: "waveform.and.mic"),
        Achievement(id: "a-path7", title: "Path Finder", detail: "Finish Today's path 7 times.", icon: "map.fill"),
        Achievement(id: "a-freeze", title: "Ice Maker", detail: "Earn a streak freeze.", icon: "snowflake"),
    ]

    func isMetV12(_ p: PlayerProfile) -> Bool? {
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-tricky": return (c[MetaEvent.trickyDrill] ?? 0) >= 3
        case "a-dictation": return (c[MetaEvent.dictationPerfect] ?? 0) >= 1
        case "a-path7": return (c[MetaEvent.pathComplete] ?? 0) >= 7
        case "a-freeze": return (c[MetaEvent.freezeEarned] ?? 0) >= 1
        default: return isMetV13(p)
        }
    }

    func progressV12(_ p: PlayerProfile) -> AchievementProgress? {
        let c = p.metaOrEmpty.counters
        func prog(_ n: Int, _ t: Int) -> AchievementProgress { AchievementProgress(current: min(n, t), target: t) }
        switch id {
        case "a-tricky": return prog(c[MetaEvent.trickyDrill] ?? 0, 3)
        case "a-path7": return prog(c[MetaEvent.pathComplete] ?? 0, 7)
        default: return progressV13(p)
        }
    }
}
