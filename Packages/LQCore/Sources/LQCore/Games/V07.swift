import Foundation

// MARK: - Profile-wide progress (shared across languages)

/// Things that belong to the explorer rather than to one language: daily challenges,
/// achievements and lifetime counters. Optional on the profile so older saves load.
public struct MetaProgress: Codable, Hashable, Sendable {
    public var challengeDay: String = ""
    public var challengeCounts: [String: Int] = [:]
    public var claimedChallenges: [String] = []
    public var achievements: [String: Date] = [:]
    public var counters: [String: Int] = [:]
    public var lastLevelSeen: Int = 1
    public init() {}
}

/// Something the learner did that challenges and achievements count.
public enum MetaEvent: String, CaseIterable, Sendable {
    case activity, flashcardRight, wordWritten, duelWon, speedDuelWon, gamePlayed, bonusDone, allChallengesDone
}

extension PlayerProfile {
    public var metaOrEmpty: MetaProgress { meta ?? MetaProgress() }

    public mutating func updateMeta(_ change: (inout MetaProgress) -> Void) {
        var m = meta ?? MetaProgress()
        change(&m)
        meta = m
    }

    /// Counts an event for today's challenges and lifetime achievements.
    public mutating func record(_ e: MetaEvent, now: Date = Date(), calendar: Calendar = .current) {
        let day = ActivityLog.dayKey(now, calendar: calendar)
        updateMeta { m in
            if m.challengeDay != day { m.challengeDay = day; m.challengeCounts = [:]; m.claimedChallenges = [] }
            m.challengeCounts[e.rawValue, default: 0] += 1
            m.counters[e.rawValue, default: 0] += 1
        }
    }

    /// Every course's progress, the active one included.
    var allCourseStates: [(courseId: String, progress: CourseProgress, knowledge: [String: ItemKnowledge], extras: ExtrasProgress?)] {
        var out = [(courseId, progress, knowledge, extras)]
        for (id, s) in otherCourses ?? [:] where id != courseId { out.append((id, s.progress, s.knowledge, s.extras)) }
        return out
    }
}

// MARK: - 1. Levels

public enum ExplorerLevel {
    public static let titles = ["Newcomer", "Explorer", "Pathfinder", "Voyager", "Wayfinder", "Linguist",
                                "Polyglot", "Scholar", "Sage", "Legend"]

    /// XP needed to go from `level` to `level + 1`: 100, 150, 200…
    public static func xpForNext(_ level: Int) -> Int { 100 + 50 * (level - 1) }

    public static func level(forXP xp: Int) -> Int {
        var lvl = 1, need = xpForNext(1), left = xp
        while left >= need { left -= need; lvl += 1; need = xpForNext(lvl) }
        return lvl
    }

    /// XP into the current level and the size of the level.
    public static func progress(forXP xp: Int) -> (into: Int, needed: Int) {
        var lvl = 1, left = xp
        while left >= xpForNext(lvl) { left -= xpForNext(lvl); lvl += 1 }
        return (left, xpForNext(lvl))
    }

    public static func title(_ level: Int) -> String { titles[min(max(level, 1), titles.count) - 1] }

    /// A level reached since the player last saw the celebration (nil = none).
    public static func pendingLevelUp(_ p: PlayerProfile) -> Int? {
        let lvl = level(forXP: p.rewards.xp)
        return lvl > p.metaOrEmpty.lastLevelSeen ? lvl : nil
    }
}

// MARK: - 2. Daily challenges

public struct DailyChallenge: Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var icon: String
    public var event: MetaEvent
    public var goal: Int
    public static let xp = 15

    public static let pool: [DailyChallenge] = [
        DailyChallenge(id: "c-flash", title: "Get 8 flashcards right", icon: "rectangle.on.rectangle.angled", event: .flashcardRight, goal: 8),
        DailyChallenge(id: "c-acts", title: "Finish 6 activities", icon: "checkmark.circle", event: .activity, goal: 6),
        DailyChallenge(id: "c-write", title: "Write out 2 words", icon: "pencil.and.scribble", event: .wordWritten, goal: 2),
        DailyChallenge(id: "c-game", title: "Play 2 mini-games", icon: "gamecontroller", event: .gamePlayed, goal: 2),
        DailyChallenge(id: "c-duel", title: "Win a word duel", icon: "bolt", event: .duelWon, goal: 1),
        DailyChallenge(id: "c-bonus", title: "Finish the bonus lesson", icon: "gift", event: .bonusDone, goal: 1),
    ]

    /// Three challenges for the day, the same all day on every launch.
    public static func today(_ now: Date, calendar: Calendar = .current) -> [DailyChallenge] {
        let day = ActivityLog.dayKey(now, calendar: calendar)
        var rng = SeededRandom(seed: day.hashValueStable)
        return Array(pool.shuffled(using: &rng).prefix(3))
    }

    public func count(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        let m = p.metaOrEmpty
        guard m.challengeDay == ActivityLog.dayKey(now, calendar: calendar) else { return 0 }
        return min(m.challengeCounts[event.rawValue] ?? 0, goal)
    }

    public func isDone(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool { count(p, now: now, calendar: calendar) >= goal }

    public func isClaimed(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        let m = p.metaOrEmpty
        return m.challengeDay == ActivityLog.dayKey(now, calendar: calendar) && m.claimedChallenges.contains(id)
    }

    /// Gives the XP once when the goal is met; returns the XP given.
    @discardableResult
    public func claim(_ p: inout PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        guard isDone(p, now: now, calendar: calendar), !isClaimed(p, now: now, calendar: calendar) else { return 0 }
        p.updateMeta { $0.claimedChallenges.append(id) }
        p.rewards.xp += Self.xp
        let all = Self.today(now, calendar: calendar)
        if all.allSatisfy({ $0.isClaimed(p, now: now, calendar: calendar) }) {
            p.updateMeta { $0.counters[MetaEvent.allChallengesDone.rawValue, default: 0] += 1 }
        }
        return Self.xp
    }
}

// MARK: - 3. Achievements

public struct Achievement: Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var icon: String

    public static let all: [Achievement] = [
        Achievement(id: "a-first-quest", title: "First Steps", detail: "Finish your first quest.", icon: "figure.walk"),
        Achievement(id: "a-three-langs", title: "World Traveler", detail: "Start 3 languages.", icon: "globe"),
        Achievement(id: "a-50-words", title: "Word Collector", detail: "Meet 50 words in any languages.", icon: "books.vertical"),
        Achievement(id: "a-scribe", title: "Scribe", detail: "Write out 10 words.", icon: "pencil.and.scribble"),
        Achievement(id: "a-speedster", title: "Speedster", detail: "Win a speed duel.", icon: "bolt.fill"),
        Achievement(id: "a-treasure", title: "Treasure Hunter", detail: "Find all 10 lost words in one language.", icon: "sparkles"),
        Achievement(id: "a-daily", title: "Challenge Champ", detail: "Complete all 3 daily challenges in a day.", icon: "star.circle"),
        Achievement(id: "a-level5", title: "Voyager", detail: "Reach level 5.", icon: "arrow.up.circle"),
        Achievement(id: "a-unit", title: "Unit Master", detail: "Finish every quest in a unit.", icon: "rosette"),
        Achievement(id: "a-flash100", title: "Card Shark", detail: "Get 100 flashcards right.", icon: "rectangle.stack.fill"),
    ]

    func isMet(_ p: PlayerProfile, libraries: [String: ContentLibrary]) -> Bool {
        let states = p.allCourseStates
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-first-quest": return states.contains { !$0.progress.completedQuests.isEmpty }
        case "a-three-langs": return p.startedCourses.count >= 3
        case "a-50-words": return states.reduce(0) { $0 + $1.knowledge.count } >= 50
        case "a-scribe": return (c[MetaEvent.wordWritten.rawValue] ?? 0) >= 10
        case "a-speedster": return (c[MetaEvent.speedDuelWon.rawValue] ?? 0) >= 1
        case "a-treasure": return states.contains { ($0.extras?.treasuresFound.count ?? 0) >= StarterVillage.treasures.count }
        case "a-daily": return (c[MetaEvent.allChallengesDone.rawValue] ?? 0) >= 1
        case "a-level5": return ExplorerLevel.level(forXP: p.rewards.xp) >= 5
        case "a-unit":
            return states.contains { s in
                libraries[s.courseId]?.units.contains { u in u.quests.allSatisfy { s.progress.completedQuests.contains($0.id) } } ?? false
            }
        case "a-flash100": return (c[MetaEvent.flashcardRight.rawValue] ?? 0) >= 100
        default: return false
        }
    }

    /// Unlocks anything newly earned and returns it (for a celebration).
    @discardableResult
    public static func evaluate(_ p: inout PlayerProfile, libraries: [String: ContentLibrary], now: Date = Date()) -> [Achievement] {
        let have = p.metaOrEmpty.achievements
        let new = all.filter { have[$0.id] == nil && $0.isMet(p, libraries: libraries) }
        if !new.isEmpty { p.updateMeta { m in for a in new { m.achievements[a.id] = now } } }
        return new
    }
}

// MARK: - 4–6. Mini-games built from the words you know

/// The word pool for mini-games: met words first, then the first unit; single words and short phrases.
enum MiniGamePool {
    static func items(_ p: PlayerProfile, library: ContentLibrary, maxLength: Int = 18) -> [LexItem] {
        let v = p.courseId == library.course.id ? p.variant : library.course.defaultVariant
        let ok: (LexItem) -> Bool = { $0.target.text(for: v).count <= maxLength && !$0.target.text(for: v).contains("…") }
        let met = library.allItems.filter { p.knowledge[$0.id] != nil && ok($0) }
        let first = (library.units.first?.allItems ?? []).filter { p.knowledge[$0.id] == nil && ok($0) }
        return met + first
    }
}

/// Echo: hear a word, pick how it's written.
public struct EchoQuestion: Hashable, Sendable {
    public var itemId: String
    public var spoken: VText
    public var english: String
    public var options: [VText]
    public var answerIndex: Int
}

public struct EchoGame: Sendable {
    public static let rounds = 8
    public let questions: [EchoQuestion]
    public private(set) var index = 0
    public private(set) var correct = 0

    public init(profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let v = profile.courseId == library.course.id ? profile.variant : library.course.defaultVariant
        let pool = MiniGamePool.items(profile, library: library)
        var seen = Set<String>()
        let picks = pool.filter { seen.insert(AnswerChecker.normalize($0.target.text(for: v))).inserted }
        questions = Array(picks.prefix(30).shuffled(using: &rng).prefix(Self.rounds)).map { item in
            let form = AnswerChecker.normalize(item.target.text(for: v))
            var used: Set<String> = [form]
            let others = library.allItems.shuffled(using: &rng).filter {
                used.insert(AnswerChecker.normalize($0.target.text(for: v))).inserted
            }.prefix(3)
            var opts = [item.target] + others.map(\.target)
            opts.shuffle(using: &rng)
            return EchoQuestion(itemId: item.id, spoken: item.target, english: item.english, options: opts,
                                answerIndex: opts.firstIndex(of: item.target) ?? 0)
        }
    }

    public var current: EchoQuestion? { index < questions.count ? questions[index] : nil }
    public var stars: Int { GameHelpers.stars(correct: correct, of: questions.count) }

    @discardableResult
    public mutating func answer(_ i: Int) -> Bool {
        guard let q = current else { return false }
        let ok = i == q.answerIndex
        if ok { correct += 1 }
        index += 1
        return ok
    }
}

/// Memory Match: pairs of a word and its meaning, face down.
public struct MemoryCard: Hashable, Identifiable, Sendable {
    public var id: Int
    public var pairId: String
    public var text: VText
    public var isTarget: Bool
}

public enum FlipResult: Equatable, Sendable { case first, match, mismatch, ignored }

public struct MemoryMatch: Sendable {
    public static let pairs = 6
    public private(set) var cards: [MemoryCard]
    public private(set) var matched: Set<String> = []
    public private(set) var faceUp: [Int] = []
    public private(set) var moves = 0

    public init(profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let v = profile.courseId == library.course.id ? profile.variant : library.course.defaultVariant
        var seenT = Set<String>(), seenE = Set<String>()
        let pool = MiniGamePool.items(profile, library: library, maxLength: 14).filter {
            seenT.insert(AnswerChecker.normalize($0.target.text(for: v))).inserted && seenE.insert(AnswerChecker.normalize($0.english)).inserted
        }
        let picks = Array(pool.prefix(20).shuffled(using: &rng).prefix(Self.pairs))
        var cs: [MemoryCard] = []
        for item in picks {
            cs.append(MemoryCard(id: 0, pairId: item.id, text: item.target, isTarget: true))
            cs.append(MemoryCard(id: 0, pairId: item.id, text: VText(item.english), isTarget: false))
        }
        cs.shuffle(using: &rng)
        cards = cs.enumerated().map { var c = $0.element; c.id = $0.offset; return c }
    }

    public var finished: Bool { !cards.isEmpty && matched.count * 2 == cards.count }
    /// 3 stars for a near-perfect memory (≤ pairs + 2 moves), down to 1.
    public var stars: Int { moves <= Self.pairs + 2 ? 3 : moves <= Self.pairs * 2 ? 2 : 1 }

    public func isFaceUp(_ id: Int) -> Bool { faceUp.contains(id) || matched.contains(cards[id].pairId) }

    /// Turns a mismatched pair back face down.
    public mutating func hideMismatch() { if faceUp.count == 2 { faceUp.removeAll() } }

    /// Turns a card. A third flip after a mismatch first turns the two back down.
    public mutating func flip(_ id: Int) -> FlipResult {
        guard cards.indices.contains(id), !matched.contains(cards[id].pairId), !faceUp.contains(id) else { return .ignored }
        if faceUp.count == 2 { faceUp.removeAll() }
        faceUp.append(id)
        guard faceUp.count == 2 else { return .first }
        moves += 1
        let a = cards[faceUp[0]], b = cards[faceUp[1]]
        if a.pairId == b.pairId && a.isTarget != b.isTarget {
            matched.insert(a.pairId)
            faceUp.removeAll()
            return .match
        }
        return .mismatch
    }
}

/// Spelling Bee: hear a word (and see its meaning), type it.
public struct SpellingBee: Sendable {
    public static let rounds = 8
    public let words: [LexItem]
    let context: CheckContext
    public private(set) var index = 0
    public private(set) var correct = 0

    public init(profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        context = library.checkContext
        let v = profile.courseId == library.course.id ? profile.variant : library.course.defaultVariant
        var seen = Set<String>()
        let pool = MiniGamePool.items(profile, library: library, maxLength: 14)
            .filter { $0.kind == .word && seen.insert(AnswerChecker.normalize($0.target.text(for: v))).inserted }
        words = Array(pool.prefix(24).shuffled(using: &rng).prefix(Self.rounds))
    }

    public var current: LexItem? { index < words.count ? words[index] : nil }
    public var stars: Int { GameHelpers.stars(correct: correct, of: words.count) }

    /// Checks the typed word (script or romanization; missing accents allowed) and moves on.
    public mutating func submit(_ typed: String, variant: String, library: ContentLibrary) -> AnswerVerdict {
        guard let w = current else { return .incorrect(expected: "") }
        var accepted = [w.target]
        if let r = library.course.romanize(w.target.text(for: variant)) { accepted.append(VText(r)) }
        let verdict = AnswerChecker.check(typed, accepted: accepted, variant: variant, context: context)
        if verdict.isCorrect { correct += 1 }
        index += 1
        return verdict
    }
}

// MARK: - 7. Mistakes notebook

public struct MistakeEntry: Hashable, Identifiable, Sendable {
    public var id: String { itemId }
    public var itemId: String
    public var target: VText
    public var english: String
    public var misses: Int
    public var accuracy: Double
}

public enum MistakesNotebook {
    /// Words with at least one miss, most-missed (then least accurate) first.
    public static func entries(_ p: PlayerProfile, library: ContentLibrary, limit: Int = 30) -> [MistakeEntry] {
        guard p.courseId == library.course.id else { return [] }
        return p.knowledge.compactMap { id, k -> MistakeEntry? in
            let misses = k.comprehension.lapses + k.production.lapses
                + (k.comprehension.reviewCount - k.comprehension.correctCount) + (k.production.reviewCount - k.production.correctCount)
            guard misses > 0, let item = library.item(id) else { return nil }
            let total = k.comprehension.reviewCount + k.production.reviewCount
            let right = k.comprehension.correctCount + k.production.correctCount
            return MistakeEntry(itemId: id, target: item.target, english: item.english, misses: misses,
                                accuracy: total == 0 ? 0 : Double(right) / Double(total))
        }
        .sorted { ($0.misses, -$0.accuracy, $1.itemId) > ($1.misses, -$1.accuracy, $0.itemId) }
        .prefix(limit).map { $0 }
    }
}

// MARK: - 8. Stats

public struct LanguageStats: Hashable, Identifiable, Sendable {
    public var id: String { courseId }
    public var courseId: String
    public var language: String
    public var byLevel: [MasteryLevel: Int]
    public var total: Int { byLevel.values.reduce(0, +) }
}

public enum PlayerStats {
    public static func languages(_ p: PlayerProfile, libraries: [String: ContentLibrary]) -> [LanguageStats] {
        p.allCourseStates.compactMap { s in
            guard let lib = libraries[s.courseId], !s.knowledge.isEmpty else { return nil }
            var by: [MasteryLevel: Int] = [:]
            for k in s.knowledge.values { by[k.level, default: 0] += 1 }
            return LanguageStats(courseId: s.courseId, language: lib.course.displayLanguage, byLevel: by)
        }
        .sorted { ($0.total, $1.courseId) > ($1.total, $0.courseId) }
    }

    public struct DayCount: Hashable, Identifiable, Sendable {
        public var id: String { day }
        public var day: String
        public var label: String
        public var activities: Int
    }

    /// Activities per day for the last 7 days, oldest first.
    public static func lastWeek(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> [DayCount] {
        let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "EEE"; f.locale = Locale(identifier: "en_US")
        return (0..<7).reversed().map { back in
            let d = calendar.date(byAdding: .day, value: -back, to: now) ?? now
            let key = ActivityLog.dayKey(d, calendar: calendar)
            return DayCount(day: key, label: f.string(from: d), activities: p.log.activitiesByDay[key] ?? 0)
        }
    }
}
