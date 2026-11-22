import Foundation

// v1.4: thirty improvements. Everything stays on the device; nothing new is sent anywhere.

extension MetaEvent {
    public static let articleDrill = "articleDrill"
    public static let pictureMatch = "pictureMatch"
    public static let oddOneOut = "oddOneOut"
    public static let freeRecallBest = "freeRecallBest"
    public static let familyQuiz = "familyQuiz"
    public static let wordChain = "wordChain"
    public static let wordReset = "wordReset"
    static func skillRight(_ k: RetentionQuestionKind) -> String { "skill-ok-" + k.rawValue }
    static func skillAsked(_ k: RetentionQuestionKind) -> String { "skill-n-" + k.rawValue }
}

/// A small multiple-choice round used by several v1.4 games. Games never change the review schedule.
public struct ChoiceQuestion: Hashable, Identifiable, Sendable {
    public var id: String
    public var prompt: String
    public var promptAudio: VText?
    public var options: [String]
    public var answerIndex: Int
    public var explanation: String
}

public struct ChoiceRound: Sendable {
    public private(set) var questions: [ChoiceQuestion]
    public private(set) var index = 0
    public private(set) var correct = 0
    public init(_ q: [ChoiceQuestion]) { questions = q }
    public var current: ChoiceQuestion? { index < questions.count ? questions[index] : nil }
    public var isFinished: Bool { index >= questions.count }
    @discardableResult
    public mutating func answer(_ choice: Int) -> Bool {
        guard let q = current else { return false }
        let ok = choice == q.answerIndex
        if ok { correct += 1 }
        index += 1
        return ok
    }
}

private func shuffledOptions(right: String, wrong: [String], rng: inout SeededRandom) -> (options: [String], answer: Int) {
    var opts = Array(Set(wrong.filter { $0 != right })).sorted().shuffled(using: &rng).prefix(3).map { $0 }
    opts.append(right)
    opts.shuffle(using: &rng)
    return (opts, opts.firstIndex(of: right) ?? 0)
}

private func metItems(_ p: PlayerProfile, _ lib: ContentLibrary) -> [LexItem] {
    var items = p.knowledge.keys.sorted().compactMap { lib.item($0) }
    if items.count < 4 { items = p.reachedUnits(lib).flatMap(\.allItems) }
    return items
}

// MARK: - 1. Article drill (el / la, le / la, il / la, o / a)

public enum ArticleDrill {
    /// Masculine and feminine definite articles for courses whose nouns carry a gender.
    public static func articles(_ course: Course) -> (m: String, f: String)? {
        switch course.targetLanguage.prefix(2).lowercased() {
        case "es": return ("el", "la")
        case "fr": return ("le", "la")
        case "it": return ("il", "la")
        case "pt": return ("o", "a")
        default: return nil
        }
    }

    public static func nouns(_ p: PlayerProfile, library: ContentLibrary) -> [LexItem] {
        metItems(p, library).filter { $0.gender == "m" || $0.gender == "f" }
    }

    public static func isAvailable(_ p: PlayerProfile, library: ContentLibrary) -> Bool {
        articles(library.course) != nil && nouns(p, library: library).count >= 3
    }

    public static func round(_ p: PlayerProfile, library: ContentLibrary, seed: UInt64, count: Int = 10) -> ChoiceRound {
        guard let a = articles(library.course) else { return ChoiceRound([]) }
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        let picks = nouns(p, library: library).shuffled(using: &rng).prefix(count)
        return ChoiceRound(picks.map { item in
            let word = bareNoun(item.target.text(for: v), articles: a)
            let right = item.gender == "m" ? a.m : a.f
            return ChoiceQuestion(id: item.id, prompt: word, promptAudio: item.target, options: [a.m, a.f],
                                  answerIndex: right == a.m ? 0 : 1, explanation: "\(right) \(word) = \(item.english)")
        })
    }

    /// Strips a leading article so the question doesn't give the answer away.
    static func bareNoun(_ text: String, articles a: (m: String, f: String)) -> String {
        for art in [a.m, a.f, "l'", "un", "una", "une", "uno"] {
            let lower = text.lowercased()
            if lower.hasPrefix(art + " ") { return String(text.dropFirst(art.count + 1)) }
            if art.hasSuffix("'"), lower.hasPrefix(art) { return String(text.dropFirst(art.count)) }
        }
        return text
    }
}

// MARK: - 2. Picture match

public enum PictureMatch {
    public static func pictured(_ p: PlayerProfile, library: ContentLibrary) -> [LexItem] {
        metItems(p, library).filter { ($0.picture ?? "").isEmpty == false }
    }

    public static func round(_ p: PlayerProfile, library: ContentLibrary, seed: UInt64, count: Int = 8) -> ChoiceRound {
        var rng = SeededRandom(seed: seed)
        let pool = pictured(p, library: library)
        guard Set(pool.compactMap(\.picture)).count >= 4 else { return ChoiceRound([]) }
        let v = p.variant(for: library)
        return ChoiceRound(pool.shuffled(using: &rng).prefix(count).map { item in
            let o = shuffledOptions(right: item.picture!, wrong: pool.compactMap(\.picture), rng: &rng)
            return ChoiceQuestion(id: item.id, prompt: item.target.text(for: v), promptAudio: item.target, options: o.options,
                                  answerIndex: o.answer, explanation: "\(item.target.text(for: v)) = \(item.english)")
        })
    }
}

// MARK: - 3. Odd one out (three words from one unit, one from another)

public enum OddOneOut {
    public static func round(_ p: PlayerProfile, library: ContentLibrary, seed: UInt64, count: Int = 6) -> ChoiceRound {
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        let met = Set(p.knowledge.keys)
        let groups = library.units.map { u in u.allItems.filter { met.contains($0.id) } }.filter { $0.count >= 3 }
        guard groups.count >= 2 else { return ChoiceRound([]) }
        var out: [ChoiceQuestion] = []
        for i in 0..<count {
            let gi = Int.random(in: 0..<groups.count, using: &rng)
            var oi = Int.random(in: 0..<groups.count, using: &rng)
            if oi == gi { oi = (gi + 1) % groups.count }
            let three = groups[gi].shuffled(using: &rng).prefix(3)
            guard let odd = groups[oi].randomElement(using: &rng) else { continue }
            var opts = three.map { $0.target.text(for: v) }
            let oddText = odd.target.text(for: v)
            guard !opts.contains(oddText) else { continue }
            opts.append(oddText)
            opts.shuffle(using: &rng)
            let unitTitle = library.units[library.units.firstIndex { $0.allItems.contains(odd) } ?? 0].title
            let mainTitle = library.units.first { u in three.allSatisfy { u.allItems.contains($0) } }?.title ?? ""
            out.append(ChoiceQuestion(id: "odd\(i)-\(odd.id)", prompt: "Which word doesn't belong?", promptAudio: nil, options: opts,
                                      answerIndex: opts.firstIndex(of: oddText) ?? 0,
                                      explanation: "\(oddText) (\(odd.english)) is from \(unitTitle); the others are from \(mainTitle)."))
        }
        return ChoiceRound(out)
    }
}

// MARK: - 4. Free recall ("brain dump")

public struct FreeRecall: Sendable {
    public static let seconds: Double = 90
    public let unitTitle: String
    private let targets: [String: String]   // normalized target -> item id
    public private(set) var found: [String] = []

    public init(unit: LessonUnit, profile p: PlayerProfile, library: ContentLibrary) {
        unitTitle = unit.title
        let v = p.variant(for: library)
        var t: [String: String] = [:]
        for item in unit.allItems where p.knowledge[item.id] != nil {
            t[AnswerChecker.normalize(item.target.text(for: v))] = item.id
            if let alt = ArticleDrill.articles(library.course) {
                t[AnswerChecker.normalize(ArticleDrill.bareNoun(item.target.text(for: v), articles: alt))] = item.id
            }
        }
        targets = t
    }

    public var possible: Int { Set(targets.values).count }

    /// Returns the item id when the typed word is a new match.
    @discardableResult
    public mutating func submit(_ typed: String) -> String? {
        guard let id = targets[AnswerChecker.normalize(typed)], !found.contains(id) else { return nil }
        found.append(id)
        return id
    }

    /// The unit with the most words met (the best one to recall from).
    public static func bestUnit(_ p: PlayerProfile, library: ContentLibrary) -> LessonUnit? {
        library.units.max { a, b in
            a.allItems.filter { p.knowledge[$0.id] != nil }.count < b.allItems.filter { p.knowledge[$0.id] != nil }.count
        }.flatMap { u in u.allItems.contains { p.knowledge[$0.id] != nil } ? u : nil }
    }

    @discardableResult
    public static func finish(_ r: FreeRecall, profile p: inout PlayerProfile) -> Bool {
        let best = p.metaOrEmpty.counters[MetaEvent.freeRecallBest] ?? 0
        if r.found.count > best { p.updateMeta { $0.counters[MetaEvent.freeRecallBest] = r.found.count } }
        return r.found.count > best
    }
}

// MARK: - 5. Yesterday's words (a check after a night's sleep)

public enum YesterdayRecall {
    public static func ids(_ p: PlayerProfile, now: Date, calendar: Calendar = .current, limit: Int = 5) -> [String] {
        guard let y = calendar.date(byAdding: .day, value: -1, to: now) else { return [] }
        let yesterday = ActivityLog.dayKey(y, calendar: calendar), today = ActivityLog.dayKey(now, calendar: calendar)
        let ids = p.knowledge.filter { _, k in
            let days = [k.comprehension.lastReviewed, k.production.lastReviewed].compactMap { $0 }.map { ActivityLog.dayKey($0, calendar: calendar) }
            return days.contains(yesterday) && !days.contains(today)
        }.keys.sorted()
        return Array(ids.prefix(limit))
    }
}

// MARK: - 6. Mini story (reading in context)

public struct MiniStory: Hashable, Sendable {
    public var unitTitle: String
    public var lines: [(text: String, english: String)] { zip(texts, englishes).map { ($0, $1) } }
    public var texts: [String]
    public var englishes: [String]
    public var question: ChoiceQuestion

    public static func make(_ p: PlayerProfile, library: ContentLibrary, seed: UInt64) -> MiniStory? {
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        for u in p.reachedUnits(library).shuffled(using: &rng) {
            let withExamples = u.allItems.filter { $0.example != nil }
            guard withExamples.count >= 3 else { continue }
            let picks = Array(withExamples.shuffled(using: &rng).prefix(4))
            guard let ask = picks.randomElement(using: &rng) else { continue }
            let o = shuffledOptions(right: ask.english, wrong: u.allItems.map(\.english), rng: &rng)
            guard o.options.count >= 2 else { continue }
            let q = ChoiceQuestion(id: "story-" + ask.id, prompt: "In the story, what does \"\(ask.target.text(for: v))\" mean?",
                                   promptAudio: ask.target, options: o.options, answerIndex: o.answer,
                                   explanation: "\(ask.target.text(for: v)) = \(ask.english)")
            return MiniStory(unitTitle: u.title, texts: picks.map { $0.example!.target.text(for: v) },
                             englishes: picks.map { $0.example!.english }, question: q)
        }
        return nil
    }

    public static func == (a: MiniStory, b: MiniStory) -> Bool { a.texts == b.texts && a.question == b.question }
    public func hash(into h: inout Hasher) { h.combine(texts); h.combine(question) }
}

// MARK: - 7. Related words (same stem)

public enum RelatedWords {
    public static func ids(for item: LexItem, profile p: PlayerProfile, library: ContentLibrary, limit: Int = 4) -> [String] {
        let v = p.variant(for: library)
        let a = ArticleDrill.articles(library.course)
        func stem(_ i: LexItem) -> String {
            var t = i.target.text(for: v)
            if let a { t = ArticleDrill.bareNoun(t, articles: a) }
            return String(AnswerChecker.normalize(t).prefix(4))
        }
        let s = stem(item)
        guard s.count == 4 else { return [] }
        return library.allItems.filter { $0.id != item.id && p.knowledge[$0.id] != nil && stem($0) == s }.map(\.id).sorted().prefix(limit).map { $0 }
    }
}

// MARK: - 10. Words newly locked in

public enum LockIns {
    public static func newly(before: [String: ItemKnowledge], after: [String: ItemKnowledge], now: Date) -> [String] {
        after.compactMap { id, k in
            RecallModel.isLockedIn(k, now: now) && !(before[id].map { RecallModel.isLockedIn($0, now: now) } ?? false) ? id : nil
        }.sorted()
    }
}

// MARK: - 11. Fresh start for a word that keeps slipping

public enum WordReset {
    public static let lapsesNeeded = 6

    public static func canReset(_ k: ItemKnowledge) -> Bool { k.comprehension.lapses + k.production.lapses >= lapsesNeeded }

    /// Starts the word's schedule again from the beginning (its memory hook and notes stay).
    public static func freshStart(_ id: String, profile p: inout PlayerProfile, now: Date) {
        guard let old = p.knowledge[id], canReset(old) else { return }
        var k = ItemKnowledge(now: now)
        k.firstSeen = old.firstSeen
        k.comprehension.lastReviewed = now
        k.comprehension.due = now
        p.knowledge[id] = k
        p.updateMeta { $0.counters[MetaEvent.wordReset, default: 0] += 1 }
    }
}

// MARK: - 12. Why I'm learning

public enum LearningReason: String, CaseIterable, Codable, Sendable {
    case travel, family, school, friends, culture, fun
    public var title: String {
        switch self {
        case .travel: return "To travel"
        case .family: return "For family"
        case .school: return "For school"
        case .friends: return "To talk with friends"
        case .culture: return "For films, music and books"
        case .fun: return "Just for fun"
        }
    }
    public var icon: String {
        switch self {
        case .travel: return "airplane"
        case .family: return "house.fill"
        case .school: return "graduationcap.fill"
        case .friends: return "person.2.fill"
        case .culture: return "music.note"
        case .fun: return "sparkles"
        }
    }
    /// A short, encouraging line connecting practice to the reason.
    public var nudge: String {
        switch self {
        case .travel: return "Every word now is one you can use on the trip."
        case .family: return "Your family will hear the difference."
        case .school: return "A little each day beats cramming before a test."
        case .friends: return "Next time you talk, these words will be ready."
        case .culture: return "Soon you'll catch these words in songs and shows."
        case .fun: return "Have fun with it. That's the best reason."
        }
    }
}

// MARK: - 13. Practice plan ("When I…, I'll practise")

public enum PracticeCue: String, CaseIterable, Codable, Sendable {
    case morning, afterSchool, afterDinner, beforeBed, weekend
    public var title: String {
        switch self {
        case .morning: return "In the morning"
        case .afterSchool: return "After school"
        case .afterDinner: return "After dinner"
        case .beforeBed: return "Before bed"
        case .weekend: return "On weekends"
        }
    }
    public var plan: String { "\(title), I'll do a Quick 3." }
}

// MARK: - 14. You vs last week

public struct SelfRace: Equatable, Sendable {
    public var thisWeek: Int
    public var lastWeekSoFar: Int
    public var ahead: Bool { thisWeek >= lastWeekSoFar }

    /// Minutes this week so far, against the same days of last week.
    public static func compute(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> SelfRace {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let daysIn = (calendar.dateComponents([.day], from: startOfWeek, to: calendar.startOfDay(for: now)).day ?? 0) + 1
        func minutes(_ from: Date) -> Int {
            (0..<daysIn).reduce(0) { sum, d in
                guard let day = calendar.date(byAdding: .day, value: d, to: from) else { return sum }
                return sum + Int((p.log.minutesByDay[ActivityLog.dayKey(day, calendar: calendar)] ?? 0).rounded())
            }
        }
        let lastStart = calendar.date(byAdding: .day, value: -7, to: startOfWeek) ?? startOfWeek
        return SelfRace(thisWeek: minutes(startOfWeek), lastWeekSoFar: minutes(lastStart))
    }
}

// MARK: - 15. 12-week activity heatmap

public struct HeatCell: Hashable, Identifiable, Sendable {
    public var id: String { day }
    public var day: String
    public var week: Int
    public var weekday: Int
    public var minutes: Double
    /// 0 (none) to 4 (20+ minutes).
    public var level: Int
}

public enum ActivityHeatmap {
    public static func cells(_ p: PlayerProfile, now: Date, weeks: Int = 12, calendar: Calendar = .current) -> [HeatCell] {
        let today = calendar.startOfDay(for: now)
        let wd = calendar.component(.weekday, from: today) - 1
        guard let start = calendar.date(byAdding: .day, value: -(weeks - 1) * 7 - wd, to: today) else { return [] }
        var out: [HeatCell] = []
        for i in 0..<(weeks * 7) {
            guard let d = calendar.date(byAdding: .day, value: i, to: start), d <= today else { break }
            let key = ActivityLog.dayKey(d, calendar: calendar)
            let m = p.log.minutesByDay[key] ?? 0
            let level = m <= 0 ? 0 : m < 5 ? 1 : m < 10 ? 2 : m < 20 ? 3 : 4
            out.append(HeatCell(day: key, week: i / 7, weekday: i % 7, minutes: m, level: level))
        }
        return out
    }
}

// MARK: - 16. Word milestones

public enum WordMilestones {
    public static let all = [25, 50, 100, 250, 500, 1000]
    public static func crossed(before: Int, after: Int) -> Int? { all.last { before < $0 && after >= $0 } }
}

// MARK: - 17. Skills breakdown (by question type)

public struct SkillRow: Hashable, Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public var kind: RetentionQuestionKind
    public var title: String
    public var asked: Int
    public var right: Int
    public var percent: Int? { asked == 0 ? nil : Int((Double(right) / Double(asked) * 100).rounded()) }
}

public enum SkillBreakdown {
    static func count(_ q: RetentionQuestion, correct: Bool, profile p: inout PlayerProfile) {
        p.updateMeta { m in
            m.counters[MetaEvent.skillAsked(q.kind), default: 0] += 1
            if correct { m.counters[MetaEvent.skillRight(q.kind), default: 0] += 1 }
        }
    }

    public static func rows(_ p: PlayerProfile) -> [SkillRow] {
        let c = p.metaOrEmpty.counters
        let titles: [(RetentionQuestionKind, String)] = [(.meaning, "Reading"), (.listen, "Listening"), (.pickWord, "Choosing the word"),
                                                          (.typeIt, "Spelling from memory"), (.cloze, "Words in sentences")]
        return titles.map { k, t in SkillRow(kind: k, title: t, asked: c[MetaEvent.skillAsked(k)] ?? 0, right: c[MetaEvent.skillRight(k)] ?? 0) }
    }

    /// The weakest skill with enough answers to judge (at least 5).
    public static func weakest(_ p: PlayerProfile) -> SkillRow? {
        rows(p).filter { $0.asked >= 5 }.min { ($0.percent ?? 0) < ($1.percent ?? 0) }
    }
}

// MARK: - 19. Learning tips (one a day)

public enum LearningTips {
    public static let all = [
        "Try to remember before you look. The effort is what makes it stick.",
        "Short and often beats long and rare: 5 minutes a day is great.",
        "Say words out loud. Hearing yourself helps you remember.",
        "Mix things up: a few old words with the new ones works better than one at a time.",
        "Getting it wrong, then seeing the answer, is still learning.",
        "Sleep helps new words settle. A quick look before bed is a good idea.",
        "Make a silly picture in your head for a hard word.",
        "Use a new word in a sentence about your own life.",
        "Coming back after a few days is the best time to review.",
        "If two words look alike, practise them side by side.",
    ]
    public static func tip(now: Date, calendar: Calendar = .current) -> String {
        all[Int(ActivityLog.dayKey(now, calendar: calendar).hashValueStable % UInt64(all.count))]
    }
}

// MARK: - 21. Pause reminders (holidays)

public enum ReminderPause {
    public static let choices = [3, 7, 14]

    public static func isPaused(_ s: LearnerSettings, now: Date) -> Bool { (s.remindersPausedUntil ?? .distantPast) > now }

    public static func pause(days: Int, profile p: inout PlayerProfile, now: Date, calendar: Calendar = .current) {
        p.settings.remindersPausedUntil = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
    }

    public static func resume(_ p: inout PlayerProfile) { p.settings.remindersPausedUntil = nil }

    /// Drops reminders that fall inside the pause.
    public static func apply(_ plan: [PlannedReminder], settings s: LearnerSettings) -> [PlannedReminder] {
        guard let until = s.remindersPausedUntil else { return plan }
        return plan.filter { $0.date >= until }
    }
}

// MARK: - 23 + 25. Parent history and weekly target

public enum ParentHistory {
    public static func days(_ p: PlayerProfile, now: Date, count: Int = 30, calendar: Calendar = .current) -> [ForecastDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            guard let d = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let key = ActivityLog.dayKey(d, calendar: calendar)
            return ForecastDay(day: key, date: d, count: Int((p.log.minutesByDay[key] ?? 0).rounded()))
        }
    }
}

public enum ParentWeekly {
    public static let choices = [30, 60, 90, 120, 180]
    public static func minutesThisWeek(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        SelfRace.compute(p, now: now, calendar: calendar).thisWeek
    }
}

// MARK: - 24. Practice sheet (paper practice)

public enum PracticeSheet {
    public static func text(_ p: PlayerProfile, library: ContentLibrary, seed: UInt64, count: Int = 12) -> String {
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        let picks = metItems(p, library).shuffled(using: &rng).prefix(count)
        var lines = ["Language Quest · \(library.course.displayLanguage) practice sheet", "Write the word for each one.", ""]
        for (i, item) in picks.enumerated() { lines.append("\(i + 1). \(item.english)  ____________________") }
        lines.append(""); lines.append("Answers (fold the page here)")
        for (i, item) in picks.enumerated() { lines.append("\(i + 1). " + item.target.text(for: v)) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 27. Family quiz (the explorer quizzes a grown-up)

public enum FamilyQuiz {
    public static func round(_ p: PlayerProfile, library: ContentLibrary, seed: UInt64, count: Int = 5) -> ChoiceRound {
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        let pool = metItems(p, library)
        guard Set(pool.map(\.english)).count >= 4 else { return ChoiceRound([]) }
        return ChoiceRound(pool.shuffled(using: &rng).prefix(count).map { item in
            let o = shuffledOptions(right: item.english, wrong: pool.map(\.english), rng: &rng)
            return ChoiceQuestion(id: item.id, prompt: item.target.text(for: v), promptAudio: item.target, options: o.options,
                                  answerIndex: o.answer, explanation: "\(item.target.text(for: v)) = \(item.english)")
        })
    }
}

// MARK: - 28. Word chain (the next word starts with the last letter)

public enum WordChain {
    public static func round(_ p: PlayerProfile, library: ContentLibrary, seed: UInt64, links: Int = 6) -> ChoiceRound {
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        let words = metItems(p, library).filter { $0.kind == .word }.map { AnswerChecker.normalize($0.target.text(for: v)) }
            .filter { $0.count >= 2 && !$0.contains(" ") }
        let unique = Array(Set(words)).sorted()
        guard unique.count >= 4 else { return ChoiceRound([]) }
        var out: [ChoiceQuestion] = []
        var used = Set<String>()
        var cur = unique.randomElement(using: &rng)!
        used.insert(cur)
        for i in 0..<links {
            guard let last = cur.last else { break }
            let next = unique.filter { $0.first == last && !used.contains($0) }
            guard let right = next.randomElement(using: &rng) else { break }
            let wrong = unique.filter { $0.first != last }
            guard wrong.count >= 2 else { break }
            let o = shuffledOptions(right: right, wrong: wrong, rng: &rng)
            out.append(ChoiceQuestion(id: "chain\(i)-\(right)", prompt: cur, promptAudio: nil, options: o.options, answerIndex: o.answer,
                                      explanation: "\(cur) ends in \"\(last)\", and \(right) starts with it."))
            used.insert(right)
            cur = right
        }
        return ChoiceRound(out)
    }
}

// MARK: - Settings added in 1.4

extension LearnerSettings {
    public var challengeModeOn: Bool { challengeMode ?? false }
    public var reason: LearningReason? { learningReason.flatMap(LearningReason.init(rawValue:)) }
    public var cue: PracticeCue? { practiceCue.flatMap(PracticeCue.init(rawValue:)) }
}

/// Games record that they were played (for achievements). They don't change the review schedule.
public enum GameCounters {
    public static func played(_ key: String, profile p: inout PlayerProfile) {
        p.updateMeta { $0.counters[key, default: 0] += 1 }
    }
}

// MARK: - 29. Achievements

extension Achievement {
    static let v14: [Achievement] = [
        Achievement(id: "a-recall10", title: "Brain Dump", detail: "Recall 10 words in a free recall round.", icon: "brain"),
        Achievement(id: "a-articles", title: "Article Ace", detail: "Play the article drill 3 times.", icon: "textformat"),
        Achievement(id: "a-words100", title: "Hundred Words", detail: "Meet 100 words.", icon: "books.vertical.fill"),
        Achievement(id: "a-family", title: "Family Teacher", detail: "Quiz a grown-up.", icon: "figure.2.and.child.holdinghands"),
    ]

    func isMetV14(_ p: PlayerProfile) -> Bool? {
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-recall10": return (c[MetaEvent.freeRecallBest] ?? 0) >= 10
        case "a-articles": return (c[MetaEvent.articleDrill] ?? 0) >= 3
        case "a-words100": return p.knowledge.count >= 100
        case "a-family": return (c[MetaEvent.familyQuiz] ?? 0) >= 1
        default: return nil
        }
    }

    func progressV14(_ p: PlayerProfile) -> AchievementProgress? {
        let c = p.metaOrEmpty.counters
        func prog(_ n: Int, _ t: Int) -> AchievementProgress { AchievementProgress(current: min(n, t), target: t) }
        switch id {
        case "a-recall10": return prog(c[MetaEvent.freeRecallBest] ?? 0, 10)
        case "a-articles": return prog(c[MetaEvent.articleDrill] ?? 0, 3)
        case "a-words100": return prog(p.knowledge.count, 100)
        default: return nil
        }
    }
}
