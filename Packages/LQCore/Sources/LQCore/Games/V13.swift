import Foundation

// v1.3: twenty-five improvements. Everything stays on the device; nothing new is sent anywhere.

extension MetaEvent {
    static let lightningPlayed = "lightningPlayed"
    static let lightningBest = "lightningBest"
    static let lookAlikeDrill = "lookAlikeDrill"
    static let bedtimeReview = "bedtimeReview"
    static let quickDone = "quickDone"
    static let listeningDone = "listeningDone"
}

// MARK: - 1 + 2. Honest confidence and answer speed

/// A right answer that was a guess, or that took a long time, is weaker evidence of memory than a quick, sure one
/// (metacognition and retrieval fluency). It still counts in the score; it just comes back a little sooner.
public enum AnswerTiming {
    /// Seconds after which a multiple-choice answer counts as slow. Typed answers get twice as long.
    public static let defaultSeconds: Double = 4

    public static func effectiveSeconds(_ seconds: Double?, kind: RetentionQuestionKind) -> Double {
        guard let s = seconds, s.isFinite else { return defaultSeconds }
        let clamped = min(max(s, 0), 120)
        return kind == .typeIt ? clamped / 2 : clamped
    }
}

// MARK: - 3. Review forecast, day by day

public struct ForecastDay: Hashable, Identifiable, Sendable {
    public var id: String { day }
    public var day: String
    public var date: Date
    public var count: Int
}

public enum DailyForecast {
    /// How many words come up for review on each of the next `days` days. Today includes anything overdue.
    public static func days(_ p: PlayerProfile, now: Date, days n: Int = 7, calendar: Calendar = .current) -> [ForecastDay] {
        let start = calendar.startOfDay(for: now)
        var counts = Array(repeating: 0, count: n)
        for k in p.knowledge.values where k.comprehension.lastReviewed != nil || k.production.lastReviewed != nil {
            let d = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: k.nextDue)).day ?? 0
            let i = max(0, d)
            if i < n { counts[i] += 1 }
        }
        return (0..<n).map { i in
            let date = calendar.date(byAdding: .day, value: i, to: start) ?? start
            return ForecastDay(day: ActivityLog.dayKey(date, calendar: calendar), date: date, count: counts[i])
        }
    }
}

// MARK: - 4. Unit mastery rings

public struct UnitMasteryRow: Hashable, Identifiable, Sendable {
    public var id: String
    public var order: Int
    public var title: String
    public var total: Int
    public var strong: Int
    public var fraction: Double { total == 0 ? 0 : Double(strong) / Double(total) }
}

public enum UnitMastery {
    /// A word counts as strong once it is understood (or better) by the spaced-review measure.
    public static func rows(_ p: PlayerProfile, library: ContentLibrary) -> [UnitMasteryRow] {
        library.units.map { u in
            let items = u.allItems
            let strong = items.filter { (p.knowledge[$0.id]?.level ?? .new) >= .understood }.count
            return UnitMasteryRow(id: u.id, order: u.order, title: u.title, total: items.count, strong: strong)
        }
    }
}

// MARK: - 5. Look-alike words

public struct LookAlikePair: Hashable, Identifiable, Sendable {
    public var a: String
    public var b: String
    public var id: String { a + "|" + b }
}

public enum LookAlikes {
    static func distance(_ s: [Character], _ t: [Character]) -> Int {
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        for i in 1...s.count {
            var cur = [i] + Array(repeating: 0, count: t.count)
            for j in 1...t.count {
                let cost: Int = s[i - 1] == t[j - 1] ? 0 : 1
                let best: Int = Swift.min(prev[j] + 1, cur[j - 1] + 1)
                cur[j] = Swift.min(best, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[t.count]
    }

    /// Pairs of words the player has met that are spelled almost the same (pero / perro) but mean different things.
    /// Practising them side by side helps tell them apart (discrimination learning).
    public static func pairs(_ p: PlayerProfile, library: ContentLibrary, limit: Int = 6) -> [LookAlikePair] {
        let v = p.variant(for: library)
        let words: [(id: String, text: [Character], english: String)] = p.knowledge.keys.sorted().compactMap { id in
            guard let item = library.item(id) else { return nil }
            let t = AnswerChecker.normalize(item.target.text(for: v))
            guard t.count >= 3, !t.contains(" ") else { return nil }
            return (id, Array(t), AnswerChecker.normalize(item.english))
        }
        var out: [LookAlikePair] = []
        for i in words.indices {
            for j in words.indices where j > i {
                let (x, y) = (words[i], words[j])
                guard x.english != y.english, x.text != y.text, abs(x.text.count - y.text.count) <= 2 else { continue }
                let d = distance(x.text, y.text)
                if d <= 1 || (d == 2 && min(x.text.count, y.text.count) >= 5) { out.append(LookAlikePair(a: x.id, b: y.id)) }
            }
        }
        return Array(out.prefix(limit))
    }

    public static func drillIds(_ pairs: [LookAlikePair]) -> [String] {
        var seen = Set<String>()
        return pairs.flatMap { [$0.a, $0.b] }.filter { seen.insert($0).inserted }
    }

    public static func markDrillDone(_ p: inout PlayerProfile) {
        p.updateMeta { $0.counters[MetaEvent.lookAlikeDrill, default: 0] += 1 }
    }
}

// MARK: - 6. Lightning round (a 60-second speed game; it doesn't change the review schedule)

public struct LightningRound: Sendable {
    public static let seconds: Double = 60
    public private(set) var score = 0
    public private(set) var answered = 0
    public private(set) var current: RetentionQuestion?
    private var pool: [String]
    private var used: Set<String> = []
    private var rng: SeededRandom
    private let library: ContentLibrary
    private let variant: String

    public init(profile p: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        self.library = library
        variant = p.variant(for: library)
        rng = SeededRandom(seed: seed)
        var ids = p.knowledge.keys.sorted().filter { library.item($0) != nil }
        if ids.count < 4 { ids = p.reachedUnits(library).flatMap(\.allItems).map(\.id) }
        pool = ids
        advance()
    }

    private mutating func advance() {
        if used.count >= pool.count { used.removeAll() }
        let fresh = pool.filter { !used.contains($0) }
        guard let id = fresh.randomElement(using: &rng), let item = library.item(id) else { current = nil; return }
        used.insert(id)
        let q = RetentionQuiz.question(item, kind: .meaning, variant: variant, distractors: library.allItems, reason: "", rng: &rng)
        current = Set(q.options).count >= 2 ? q : nil
    }

    @discardableResult
    public mutating func answer(choice: Int) -> Bool {
        guard let q = current else { return false }
        let ok = choice == q.answerIndex
        answered += 1
        if ok { score += 1 }
        advance()
        return ok
    }

    /// Saves the best score. Returns true for a new personal best.
    @discardableResult
    public static func finish(_ r: LightningRound, profile p: inout PlayerProfile) -> Bool {
        let best = best(p)
        p.updateMeta { m in
            m.counters[MetaEvent.lightningPlayed, default: 0] += 1
            if r.score > best { m.counters[MetaEvent.lightningBest] = r.score }
        }
        return r.score > best && r.score > 0
    }

    public static func best(_ p: PlayerProfile) -> Int { p.metaOrEmpty.counters[MetaEvent.lightningBest] ?? 0 }
}

// MARK: - 9. Sentence of the day

public enum SentenceOfTheDay {
    /// A sentence using today's word of the day, so it is seen in context.
    public static func make(_ p: PlayerProfile, library: ContentLibrary, now: Date, calendar: Calendar = .current) -> (word: LexItem, text: String, english: String)? {
        guard let w = WordOfTheDay.pick(p, library: library, now: now, calendar: calendar),
              let s = ExampleSentence.sentence(for: w, profile: p, library: library) else { return nil }
        return (w, s.text, s.english)
    }
}

// MARK: - 10. Bedtime review (sleep helps new memories settle)

public enum BedtimeReview {
    public static let startHour = 18
    public static let size = 5

    /// In the evening, up to 5 words practised today, weakest first.
    public static func ids(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> [String] {
        guard calendar.component(.hour, from: now) >= startHour else { return [] }
        let today = ActivityLog.dayKey(now, calendar: calendar)
        let practised = p.knowledge.filter { _, k in
            [k.comprehension.lastReviewed, k.production.lastReviewed].compactMap { $0 }
                .contains { ActivityLog.dayKey($0, calendar: calendar) == today }
        }
        let tomorrow = now.addingTimeInterval(86400)
        var scored: [(id: String, recall: Double)] = []
        for (id, k) in practised {
            let r: Double = RecallModel.probability(k, now: tomorrow) ?? 0
            scored.append((id: id, recall: r))
        }
        scored.sort { (x: (id: String, recall: Double), y: (id: String, recall: Double)) -> Bool in
            if x.recall != y.recall { return x.recall < y.recall }
            return x.id < y.id
        }
        return scored.prefix(size).map { $0.id }
    }

    public static func isAvailable(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        p.metaOrEmpty.bedtimeDay != ActivityLog.dayKey(now, calendar: calendar) && ids(p, now: now, calendar: calendar).count >= 3
    }

    public static func markDone(_ p: inout PlayerProfile, now: Date, calendar: Calendar = .current) {
        p.updateMeta { m in
            m.bedtimeDay = ActivityLog.dayKey(now, calendar: calendar)
            m.counters[MetaEvent.bedtimeReview, default: 0] += 1
        }
    }
}

// MARK: - 11. "Review soon"

public enum ReviewSoon {
    /// Brings a word into the next review without counting anything as a mistake.
    public static func pin(_ id: String, profile p: inout PlayerProfile, now: Date) {
        var k = p.knowledge[id] ?? ItemKnowledge(now: now)
        if k.comprehension.lastReviewed == nil && k.production.lastReviewed == nil {
            k.comprehension.lastReviewed = now.addingTimeInterval(-86400)
        }
        if k.comprehension.lastReviewed != nil { k.comprehension.due = min(k.comprehension.due, now) }
        if k.production.lastReviewed != nil { k.production.due = min(k.production.due, now) }
        p.knowledge[id] = k
    }

    public static func isDue(_ id: String, profile p: PlayerProfile, now: Date) -> Bool {
        guard let k = p.knowledge[id] else { return false }
        return k.nextDue <= now
    }
}

// MARK: - 12. Look back over a quiz

public struct QuizReviewRow: Hashable, Identifiable, Sendable {
    public var id: String { itemId }
    public var itemId: String
    public var word: VText
    public var meaning: String
    public var correct: Bool
    public var hinted: Bool
}

extension RetentionQuiz {
    public var reviewRows: [QuizReviewRow] {
        questions.map { q in
            QuizReviewRow(itemId: q.itemId, word: q.word, meaning: q.meaning, correct: firstTry[q.itemId] == true, hinted: hinted.contains(q.itemId))
        }
    }
}

// MARK: - 14. Daily minutes goal

public enum DailyGoal {
    public static let choices = [5, 10, 15, 20]

    public static func goal(_ s: LearnerSettings) -> Int? { s.dailyGoalMinutes.flatMap { choices.contains($0) ? $0 : nil } }

    public static func progress(minutesToday: Double, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        let f: Double = Swift.max(0, minutesToday) / Double(goal)
        return Swift.min(1, f)
    }
}

// MARK: - 15. Weekly question goal

public enum WeeklyQuestions {
    public static let goal = 50

    public static func answered(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        let week = WeeklyGoal.weekKey(now, calendar: calendar)
        return (p.extrasOrEmpty.quizHistory ?? []).filter { WeeklyGoal.weekKey($0.date, calendar: calendar) == week }.reduce(0) { $0 + $1.total }
    }

    /// The most questions answered in any one week so far.
    public static func bestWeek(_ p: PlayerProfile, calendar: Calendar = .current) -> Int {
        var by: [String: Int] = [:]
        for r in p.extrasOrEmpty.quizHistory ?? [] { by[WeeklyGoal.weekKey(r.date, calendar: calendar), default: 0] += r.total }
        return by.values.max() ?? 0
    }
}

// MARK: - 17. Parent bedtime

public enum Bedtime {
    public static let choices = [19, 20, 21, 22]
    /// Early-morning hours before this also count as "after bedtime".
    public static let morningHour = 5

    public static func isPast(parent: ParentSettings, profile p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        guard let h = parent.bedtimeHour, choices.contains(h) else { return false }
        if p.metaOrEmpty.limitOverrideDay == ActivityLog.dayKey(now, calendar: calendar) { return false }
        let hour = calendar.component(.hour, from: now)
        return hour >= h || hour < morningHour
    }
}

// MARK: - 18. Word list a parent can share

public enum WordListExport {
    public static func text(_ p: PlayerProfile, library: ContentLibrary) -> String {
        let v = p.variant(for: library)
        let metCount: Int = p.knowledge.keys.filter { library.item($0) != nil }.count
        let header: String = "Language Quest · " + library.course.displayLanguage + " words met (" + String(metCount) + ")"
        var lines: [String] = [header, ""]
        for u in library.units {
            let met = u.allItems.filter { p.knowledge[$0.id] != nil }
            guard !met.isEmpty else { continue }
            lines.append("Unit \(u.order): \(u.title)")
            for item in met { lines.append("• " + item.target.text(for: v) + " — " + item.english) }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 19. Example sentence

public enum ExampleSentence {
    /// A sentence that uses the word (its own example first, then lines from quests the player reached).
    public static func sentence(for item: LexItem, profile p: PlayerProfile, library: ContentLibrary) -> (text: String, english: String)? {
        guard let c = Cloze.sentence(for: item, profile: p, library: library) else { return nil }
        return (c.text.replacingOccurrences(of: Cloze.blank, with: item.target.text(for: p.variant(for: library))), c.english)
    }
}

// MARK: - 20. Today's report

public struct TodayReport: Equatable, Sendable {
    public var minutes: Int
    public var activities: Int
    public var quizzes: Int
    public var questions: Int
    public var correct: Int
    public var wordsPractised: Int
    public var accuracy: Int? { questions == 0 ? nil : Int((Double(correct) / Double(questions) * 100).rounded()) }

    public static func compute(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> TodayReport {
        let today = ActivityLog.dayKey(now, calendar: calendar)
        let quizzes = (p.extrasOrEmpty.quizHistory ?? []).filter { ActivityLog.dayKey($0.date, calendar: calendar) == today }
        let words = p.knowledge.values.filter { k in
            [k.comprehension.lastReviewed, k.production.lastReviewed].compactMap { $0 }.contains { ActivityLog.dayKey($0, calendar: calendar) == today }
        }.count
        return TodayReport(minutes: Int((p.log.minutesByDay[today] ?? 0).rounded()), activities: p.log.activitiesByDay[today] ?? 0,
                           quizzes: quizzes.count, questions: quizzes.reduce(0) { $0 + $1.total },
                           correct: quizzes.reduce(0) { $0 + $1.correct }, wordsPractised: words)
    }
}

// MARK: - 21. Answer combo

public struct ComboCounter: Sendable {
    public static let milestones = [3, 5, 10]
    public private(set) var run = 0
    public private(set) var best = 0
    public init() {}

    /// Returns a milestone (3, 5, 10) when one is reached.
    public mutating func record(_ ok: Bool) -> Int? {
        if ok { run += 1; best = max(best, run) } else { run = 0 }
        return ok && Self.milestones.contains(run) ? run : nil
    }
}

// MARK: - Settings added in 1.3

extension LearnerSettings {
    public var hapticsOn: Bool { haptics ?? true }
    public var bigButtonsOn: Bool { bigButtons ?? false }
}

// MARK: - 23. Achievements

extension Achievement {
    static let v13: [Achievement] = [
        Achievement(id: "a-lightning", title: "Lightning Fast", detail: "Score 15 in a Lightning round.", icon: "bolt.fill"),
        Achievement(id: "a-lookalike", title: "Sharp Eyes", detail: "Finish a look-alike words drill.", icon: "eye.fill"),
        Achievement(id: "a-bedtime", title: "Sleep On It", detail: "Do 3 bedtime reviews.", icon: "moon.zzz.fill"),
        Achievement(id: "a-week50", title: "Question Crusher", detail: "Answer 50 quiz questions in one week.", icon: "checklist"),
    ]

    func isMetV13(_ p: PlayerProfile) -> Bool? {
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-lightning": return (c[MetaEvent.lightningBest] ?? 0) >= 15
        case "a-lookalike": return (c[MetaEvent.lookAlikeDrill] ?? 0) >= 1
        case "a-bedtime": return (c[MetaEvent.bedtimeReview] ?? 0) >= 3
        case "a-week50": return WeeklyQuestions.bestWeek(p) >= WeeklyQuestions.goal
        default: return isMetV14(p)
        }
    }

    func progressV13(_ p: PlayerProfile) -> AchievementProgress? {
        let c = p.metaOrEmpty.counters
        func prog(_ n: Int, _ t: Int) -> AchievementProgress { AchievementProgress(current: min(n, t), target: t) }
        switch id {
        case "a-lightning": return prog(c[MetaEvent.lightningBest] ?? 0, 15)
        case "a-bedtime": return prog(c[MetaEvent.bedtimeReview] ?? 0, 3)
        case "a-week50": return prog(WeeklyQuestions.bestWeek(p), WeeklyQuestions.goal)
        default: return progressV14(p)
        }
    }
}
