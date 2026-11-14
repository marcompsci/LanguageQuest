import Foundation

// v0.8: ten improvements. Everything here stays on the device; nothing is sent anywhere.

// MARK: - Shared

extension PlayerProfile {
    /// The variant to use with a library (the learner's own for the active course, otherwise the default).
    func variant(for library: ContentLibrary) -> String {
        courseId == library.course.id ? variant : (otherCourses?[library.course.id]?.variant ?? library.course.defaultVariant)
    }

    /// Units the learner has reached: any quest started or finished, or placed out. Always at least the first unit.
    func reachedUnits(_ library: ContentLibrary) -> [LessonUnit] {
        let reached = library.units.filter { u in
            progress.placedOutUnits.contains(u.id) ||
            u.quests.contains { progress.startedQuests.contains($0.id) || progress.completedQuests.contains($0.id) }
        }
        return reached.isEmpty ? Array(library.units.prefix(1)) : reached
    }
}

extension MetaEvent {
    static let sentenceBuilt = "sentenceBuilt"
    static let quizPerfect = "quizPerfect"
    static let weeklyGoalMet = "weeklyGoalMet"
}

// MARK: - 1. Word Library

public enum WordFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", met = "Met", practice = "Practice", starred = "Starred"
    public var id: String { rawValue }
}

public struct WordEntry: Hashable, Identifiable, Sendable {
    public var item: LexItem
    public var unitOrder: Int
    public var level: MasteryLevel
    public var met: Bool
    public var starred: Bool
    public var id: String { item.id }
}

public enum WordLibrary {
    /// Every word and phrase in the course, in unit order, filtered and searched.
    /// The search matches the word (any regional form), its meaning, or its pronunciation line.
    public static func entries(_ p: PlayerProfile, library: ContentLibrary, filter: WordFilter = .all,
                               query: String = "", now: Date = Date()) -> [WordEntry] {
        let starred = Set(p.extrasOrEmpty.starredWords ?? [])
        let q = AnswerChecker.normalize(query)
        var seen = Set<String>()
        var out: [WordEntry] = []
        for u in library.units.sorted(by: { $0.order < $1.order }) {
            for item in u.allItems where seen.insert(item.id).inserted {
                let k = p.knowledge[item.id]
                let e = WordEntry(item: item, unitOrder: u.order, level: k?.level ?? .new, met: k != nil, starred: starred.contains(item.id))
                switch filter {
                case .all: break
                case .met: if !e.met { continue }
                case .practice:
                    guard let k else { continue }
                    if k.level > .familiar && k.nextDue > now { continue }
                case .starred: if !e.starred { continue }
                }
                if !q.isEmpty {
                    let forms = item.target.allForms + [item.english] + item.target.allForms.compactMap { library.course.romanize($0) }
                    if !forms.contains(where: { AnswerChecker.normalize($0).contains(q) }) { continue }
                }
                out.append(e)
            }
        }
        return out
    }
}

// MARK: - 2. Starred words

public enum StarredWords {
    public static let deckSize = 12

    public static func isStarred(_ id: String, in p: PlayerProfile) -> Bool { (p.extrasOrEmpty.starredWords ?? []).contains(id) }

    /// Stars or un-stars a word in the active course. Returns the new state.
    @discardableResult
    public static func toggle(_ id: String, profile p: inout PlayerProfile) -> Bool {
        var nowStarred = false
        p.updateExtras { e in
            var list = e.starredWords ?? []
            if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id); nowStarred = true }
            e.starredWords = list
        }
        return nowStarred
    }

    /// A flashcard deck of starred words (due ones first), for "Practice starred".
    public static func deck(_ p: PlayerProfile, library: ContentLibrary, now: Date, seed: UInt64) -> [Flashcard] {
        var rng = SeededRandom(seed: seed)
        let ids = (p.extrasOrEmpty.starredWords ?? []).filter { library.item($0) != nil }
        let due = ids.filter { (p.knowledge[$0]?.nextDue ?? now) <= now }.shuffled(using: &rng)
        let rest = ids.filter { !due.contains($0) }.shuffled(using: &rng)
        return (due + rest).prefix(deckSize).compactMap { id in
            library.item(id).map { Flashcard(itemId: id, front: $0.target, back: $0.english, picture: $0.picture) }
        }
    }

    /// Stars across every language (for the achievement).
    static func totalStarred(_ p: PlayerProfile) -> Int {
        p.allCourseStates.reduce(0) { $0 + ($1.extras?.starredWords?.count ?? 0) }
    }
}

// MARK: - 3. Word of the day

public enum WordOfTheDay {
    /// One word a day per language, the same all day, from the units the learner has reached.
    public static func pick(_ p: PlayerProfile, library: ContentLibrary, now: Date, calendar: Calendar = .current) -> LexItem? {
        let v = p.variant(for: library)
        let pool = p.reachedUnits(library).flatMap(\.allItems).filter {
            let t = $0.target.text(for: v)
            return !t.contains("…") && !t.contains("{") && t.count <= 30
        }
        guard !pool.isEmpty else { return nil }
        let key = ActivityLog.dayKey(now, calendar: calendar) + library.course.id
        return pool[Int(key.hashValueStable % UInt64(pool.count))]
    }
}

// MARK: - 4. Sentence Builder

public struct SentencePuzzle: Hashable, Sendable {
    public var english: String
    public var answer: [String]
    /// The answer's tiles, shuffled (never already in order).
    public var tiles: [String]
    public var full: String
}

public struct SentenceBuilder: Sendable {
    public static let rounds = 5
    public static let minTokens = 3
    public static let maxTokens = 8
    public let puzzles: [SentencePuzzle]
    public private(set) var index = 0
    public private(set) var firstTryCorrect = 0
    private var missedCurrent = false

    /// Splits a sentence into tiles: words where the language uses spaces, characters otherwise (Chinese).
    /// Punctuation stays stuck to the tile before it.
    public static func tokens(_ s: String) -> [String] {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains(" ") { return t.split(separator: " ").map(String.init) }
        let punct = CharacterSet(charactersIn: ".,!?;:…·。，！？、「」“”\"'()[]")
        var out: [String] = []
        for ch in t {
            if ch.unicodeScalars.allSatisfy({ punct.contains($0) }), !out.isEmpty { out[out.count - 1].append(ch) } else { out.append(String(ch)) }
        }
        return out
    }

    /// Lines from the quests the learner has reached: what villagers said and the right replies.
    public static func candidates(_ p: PlayerProfile, library: ContentLibrary) -> [(text: String, english: String)] {
        let v = p.variant(for: library)
        let quests = library.units.flatMap(\.quests).filter { p.progress.startedQuests.contains($0.id) || p.progress.completedQuests.contains($0.id) }
        let source = quests.isEmpty ? Array(library.units.first?.quests.prefix(1) ?? []) : quests
        let name = p.nickname.isEmpty ? "Alex" : p.nickname
        var out: [(String, String)] = []
        var seen = Set<String>()
        // Multi-word phrases from the units reached, then lines from the quests.
        for item in p.reachedUnits(library).flatMap(\.allItems) {
            let text = item.target.text(for: v)
            let n = tokens(text).count
            if n >= minTokens && n <= maxTokens && !text.contains("{") && !text.contains("…") && seen.insert(text).inserted {
                out.append((text, item.english))
            }
        }
        for q in source {
            for n in q.dialogue.nodes {
                var lines = [(n.line.text(for: v), n.gloss)]
                lines += (n.choices ?? []).filter { $0.correct != false }.map { ($0.text.text(for: v), $0.gloss) }
                for (raw, english) in lines where !raw.contains("…") && !english.isEmpty {
                    let text = raw.replacingOccurrences(of: "{name}", with: name)
                    guard !text.contains("{") else { continue }
                    let n = tokens(text).count
                    guard n >= minTokens && n <= maxTokens, seen.insert(text).inserted else { continue }
                    out.append((text, english))
                }
            }
        }
        return out
    }

    public static func isAvailable(_ p: PlayerProfile, library: ContentLibrary) -> Bool { !candidates(p, library: library).isEmpty }

    public init(profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let picks = Self.candidates(profile, library: library).shuffled(using: &rng).prefix(Self.rounds)
        puzzles = picks.map { c in
            let answer = Self.tokens(c.text)
            var tiles = answer
            if Set(answer).count > 1 { while tiles == answer { tiles.shuffle(using: &rng) } }
            return SentencePuzzle(english: c.english, answer: answer, tiles: tiles, full: c.text)
        }
    }

    public var current: SentencePuzzle? { index < puzzles.count ? puzzles[index] : nil }
    public var isFinished: Bool { index >= puzzles.count }
    public var stars: Int { GameHelpers.stars(correct: firstTryCorrect, of: puzzles.count) }

    /// Checks an arrangement. Right answers move on; a wrong one can be fixed and tried again.
    @discardableResult
    public mutating func check(_ arrangement: [String]) -> Bool {
        guard let p = current else { return false }
        if arrangement == p.answer {
            if !missedCurrent { firstTryCorrect += 1 }
            missedCurrent = false
            index += 1
            return true
        }
        missedCurrent = true
        return false
    }

    /// Skips a puzzle (counts as not first-try).
    public mutating func skip() { guard current != nil else { return }; missedCurrent = false; index += 1 }

    /// Saves the best stars (the app counts the game for challenges).
    public static func finish(_ game: SentenceBuilder, profile p: inout PlayerProfile, now: Date = Date()) {
        p.updateExtras { $0.builderBestStars = max($0.builderBestStars ?? 0, game.stars) }
        if game.stars == 3 { p.updateMeta { $0.counters[MetaEvent.sentenceBuilt, default: 0] += 1 } }
    }
}

// MARK: - 5. Unit quiz

public struct QuizQuestion: Hashable, Sendable {
    public var itemId: String
    /// true: shown the word, pick its meaning. false: shown the meaning, pick the word.
    public var showsTarget: Bool
    public var prompt: String
    public var promptText: VText?
    public var options: [String]
    public var optionTexts: [VText]?
    public var answerIndex: Int
}

public struct UnitQuiz: Sendable {
    public static let size = 10
    public let unitId: String
    public let questions: [QuizQuestion]
    public private(set) var index = 0
    public private(set) var correct = 0

    /// A unit's quiz opens once the learner finishes one of its quests (or placed out of it).
    public static func isOpen(_ unit: LessonUnit, progress: CourseProgress) -> Bool {
        progress.placedOutUnits.contains(unit.id) || unit.quests.contains { progress.completedQuests.contains($0.id) }
    }

    public init(unit: LessonUnit, profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let v = profile.variant(for: library)
        unitId = unit.id
        var seenWord = Set<String>(), seenMeaning = Set<String>()
        let pool = unit.allItems.filter {
            let t = $0.target.text(for: v)
            return !t.contains("…") && !t.contains("{")
                && seenWord.insert(AnswerChecker.normalize(t)).inserted && seenMeaning.insert(AnswerChecker.normalize($0.english)).inserted
        }
        let others = library.allItems.filter { o in !pool.contains { $0.id == o.id } }
        var qs: [QuizQuestion] = []
        for (n, item) in pool.shuffled(using: &rng).prefix(Self.size).enumerated() {
            let wrong = (pool.filter { $0.id != item.id } + others.shuffled(using: &rng))
            if n % 2 == 0 {
                var meanings = [item.english]
                for w in wrong where meanings.count < 4 && !meanings.contains(where: { AnswerChecker.normalize($0) == AnswerChecker.normalize(w.english) }) {
                    meanings.append(w.english)
                }
                let opts = meanings.shuffled(using: &rng)
                qs.append(QuizQuestion(itemId: item.id, showsTarget: true, prompt: item.target.text(for: v), promptText: item.target,
                                       options: opts, optionTexts: nil, answerIndex: opts.firstIndex(of: item.english) ?? 0))
            } else {
                var words = [item.target]
                for w in wrong where words.count < 4 && !words.contains(where: { AnswerChecker.normalize($0.text(for: v)) == AnswerChecker.normalize(w.target.text(for: v)) }) {
                    words.append(w.target)
                }
                let opts = words.shuffled(using: &rng)
                qs.append(QuizQuestion(itemId: item.id, showsTarget: false, prompt: item.english, promptText: nil,
                                       options: opts.map { $0.text(for: v) }, optionTexts: opts, answerIndex: opts.firstIndex(of: item.target) ?? 0))
            }
        }
        questions = qs
    }

    public var current: QuizQuestion? { index < questions.count ? questions[index] : nil }
    public var isFinished: Bool { index >= questions.count }
    public var percent: Int { questions.isEmpty ? 0 : Int((Double(correct) / Double(questions.count) * 100).rounded()) }

    @discardableResult
    public mutating func answer(_ i: Int) -> Bool {
        guard let q = current else { return false }
        let ok = i == q.answerIndex
        if ok { correct += 1 }
        index += 1
        return ok
    }

    /// Records each answer in the learner model (word → meaning is understanding; meaning → word is production).
    public static func record(_ q: QuizQuestion, correct ok: Bool, profile p: inout PlayerProfile, now: Date) {
        PracticeRecorder.record(itemId: q.itemId, outcome: ReviewOutcome(correct: ok), track: q.showsTarget ? .comprehension : .guidedProduction, profile: &p, now: now)
    }

    /// Saves the best score for the unit.
    public static func finish(_ quiz: UnitQuiz, profile p: inout PlayerProfile, now: Date = Date()) {
        p.updateExtras { e in
            var best = e.quizBest ?? [:]
            best[quiz.unitId] = max(best[quiz.unitId] ?? 0, quiz.percent)
            e.quizBest = best
        }
        if quiz.percent == 100 { p.updateMeta { $0.counters[MetaEvent.quizPerfect, default: 0] += 1 } }
    }
}

// MARK: - 6. Weekly goal (no streaks: a missed week just starts fresh)

public enum WeeklyGoal {
    public static let choices = [2, 3, 5, 7]
    public static let defaultDays = 3
    public static let xp = 40

    public static func goal(_ p: PlayerProfile) -> Int { p.metaOrEmpty.weeklyGoalDays ?? defaultDays }

    /// The first day of this week ("yyyy-MM-dd"), using the device's calendar.
    public static func weekKey(_ now: Date, calendar: Calendar = .current) -> String {
        ActivityLog.dayKey(calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now, calendar: calendar)
    }

    /// Days this week with at least one finished activity or some time played.
    public static func daysPracticed(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return (0..<7).filter { i in
            guard let d = calendar.date(byAdding: .day, value: i, to: start), d <= now else { return false }
            let k = ActivityLog.dayKey(d, calendar: calendar)
            return (p.log.activitiesByDay[k] ?? 0) > 0 || (p.log.minutesByDay[k] ?? 0) >= 1
        }.count
    }

    public static func isMet(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        daysPracticed(p, now: now, calendar: calendar) >= goal(p)
    }

    public static func isClaimed(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        p.metaOrEmpty.weeklyClaimedWeek == weekKey(now, calendar: calendar)
    }

    public static func setGoal(_ days: Int, profile p: inout PlayerProfile) {
        guard choices.contains(days) else { return }
        p.updateMeta { $0.weeklyGoalDays = days }
    }

    /// Gives the XP once a week when the goal is met; returns the XP given.
    @discardableResult
    public static func claim(_ p: inout PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        guard isMet(p, now: now, calendar: calendar), !isClaimed(p, now: now, calendar: calendar) else { return 0 }
        let week = weekKey(now, calendar: calendar)
        p.updateMeta { $0.weeklyClaimedWeek = week; $0.counters[MetaEvent.weeklyGoalMet, default: 0] += 1 }
        p.rewards.xp += xp
        return xp
    }

    /// A kind sentence about the week. Never mentions what was missed.
    public static func message(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> String {
        let done = daysPracticed(p, now: now, calendar: calendar), goal = goal(p)
        if isClaimed(p, now: now, calendar: calendar) { return "Goal reached this week. Anything more is a bonus!" }
        if done >= goal { return "You reached your goal! Claim +\(xp) XP." }
        if done == 0 { return "A new week. Practice on \(goal) days to reach your goal." }
        return "\(done) of \(goal) days so far this week."
    }
}

// MARK: - 7. Practice reminders (set by a parent; local notifications only)

public struct ReminderPlan: Codable, Hashable, Sendable {
    public var enabled = false
    public var hour = 17
    public var minute = 0
    /// Calendar weekdays: 1 = Sunday … 7 = Saturday.
    public var weekdays: [Int] = [2, 3, 4, 5, 6]
    public init() {}

    /// Friendly, generic text: no name, no progress details on the lock screen.
    public static let messages = [
        "Your village friends say hola! Ready for a few minutes of practice?",
        "A quick quest is waiting in Language Quest.",
        "Five minutes of words today? Your explorer is ready.",
        "New day, new words. Want to play a little?",
    ]

    public static func message(weekday: Int) -> String { messages[(max(weekday, 1) - 1) % messages.count] }

    public var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) && !weekdays.isEmpty && weekdays.allSatisfy { (1...7).contains($0) } }

    public var timeLabel: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
    }
}

extension ParentSettings {
    public var reminderPlan: ReminderPlan { reminders ?? ReminderPlan() }
}

// MARK: - 8. Weekly report for parents (stays on the device unless a parent shares it)

public struct WeeklyReport: Sendable {
    public var title: String
    public var lines: [String]
    public var text: String { ([title] + lines).joined(separator: "\n") }

    public static func make(_ p: PlayerProfile, libraries: [String: ContentLibrary], now: Date, calendar: Calendar = .current) -> WeeklyReport {
        var minutes = 0.0, activities = 0, days = 0
        for i in 0..<7 {
            guard let d = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            let k = ActivityLog.dayKey(d, calendar: calendar)
            let m = p.log.minutesByDay[k] ?? 0, a = p.log.activitiesByDay[k] ?? 0
            minutes += m; activities += a
            if m >= 1 || a > 0 { days += 1 }
        }
        let name = p.nickname.isEmpty ? "Your explorer" : p.nickname
        var lines = [
            "Days practiced: \(days) of 7",
            "Time played: about \(Int(minutes.rounded())) minutes",
            "Activities finished: \(activities)",
            "Level \(ExplorerLevel.level(forXP: p.rewards.xp)) (\(ExplorerLevel.title(ExplorerLevel.level(forXP: p.rewards.xp))))",
        ]
        for s in p.allCourseStates {
            guard let lib = libraries[s.courseId] else { continue }
            let quests = lib.units.flatMap(\.quests)
            let done = quests.filter { s.progress.completedQuests.contains($0.id) }.count
            let strong = s.knowledge.values.filter { $0.level >= .understood }.count
            lines.append("\(lib.course.displayLanguage): \(done)/\(quests.count) quests, \(s.knowledge.count) words met, \(strong) understood well")
        }
        lines.append("Made by Language Quest on this device. Nothing was sent anywhere.")
        return WeeklyReport(title: "\(name)'s week in Language Quest (last 7 days)", lines: lines)
    }
}

// MARK: - 10. New achievements

extension Achievement {
    static let v08: [Achievement] = [
        Achievement(id: "a-starred", title: "Word Keeper", detail: "Star 5 words to practice.", icon: "star.fill"),
        Achievement(id: "a-builder", title: "Sentence Smith", detail: "Get 3 stars in Sentence Builder.", icon: "text.word.spacing"),
        Achievement(id: "a-quiz", title: "Quiz Whiz", detail: "Score 100% on a unit quiz.", icon: "checkmark.seal.fill"),
        Achievement(id: "a-weekly", title: "Steady Explorer", detail: "Reach your weekly goal.", icon: "calendar.badge.checkmark"),
    ]

    func isMetV08(_ p: PlayerProfile) -> Bool? {
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-starred": return StarredWords.totalStarred(p) >= 5
        case "a-builder": return (c[MetaEvent.sentenceBuilt] ?? 0) >= 1
        case "a-quiz": return (c[MetaEvent.quizPerfect] ?? 0) >= 1
        case "a-weekly": return (c[MetaEvent.weeklyGoalMet] ?? 0) >= 1
        default: return nil
        }
    }
}
