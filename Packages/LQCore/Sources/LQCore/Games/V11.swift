import Foundation

// v1.1: twenty improvements. Everything stays on the device.

extension MetaEvent {
    static let warmUpDone = "warmUpDone"
    static let hookWritten = "hookWritten"
}

// MARK: - 1. Today's path: three steps a day

public enum PathStepKind: String, Codable, Sendable { case memoryCheck, quest, review }

public struct PathStep: Hashable, Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public var kind: PathStepKind
    public var title: String
    public var detail: String
    public var done: Bool
}

public enum TodayPath {
    /// A short daily plan: warm up memory, learn something new, then review. Each step ticks off when done today.
    public static func steps(_ p: PlayerProfile, library: ContentLibrary, progression: Progression, plan: Plan,
                             now: Date, calendar: Calendar = .current) -> [PathStep] {
        let today = ActivityLog.dayKey(now, calendar: calendar)
        let done = Set(p.metaOrEmpty.pathDay == today ? (p.metaOrEmpty.pathDone ?? []) : [])
        let hist = p.extrasOrEmpty.quizHistory ?? []
        let checkedToday = hist.contains { !$0.isLesson && ActivityLog.dayKey($0.date, calendar: calendar) == today }
        let lessonToday = hist.contains { $0.isLesson && ActivityLog.dayKey($0.date, calendar: calendar) == today }
        let due = ReviewPlanner.dueItems(p.knowledge, now: now).count
        let next = progression.nextQuest(p.progress, plan: plan)
        return [
            PathStep(kind: .memoryCheck, title: "Warm up your memory", detail: "A 5-question memory check",
                     done: checkedToday || done.contains(PathStepKind.memoryCheck.rawValue) || p.knowledge.isEmpty),
            PathStep(kind: .quest, title: next.map { "Learn: \($0.title)" } ?? "Replay a favorite quest",
                     detail: "Ends with a 5-question lesson quiz",
                     done: lessonToday || done.contains(PathStepKind.quest.rawValue)),
            PathStep(kind: .review, title: "Review", detail: due == 0 ? "Nothing due right now" : "\(due) word\(due == 1 ? "" : "s") ready",
                     done: due == 0 || done.contains(PathStepKind.review.rawValue)),
        ]
    }

    public static func mark(_ step: PathStepKind, profile p: inout PlayerProfile, now: Date, calendar: Calendar = .current) {
        let today = ActivityLog.dayKey(now, calendar: calendar)
        p.updateMeta { m in
            if m.pathDay != today { m.pathDay = today; m.pathDone = [] }
            if !(m.pathDone ?? []).contains(step.rawValue) { m.pathDone = (m.pathDone ?? []) + [step.rawValue] }
        }
    }
}

// MARK: - 2. Warm-up guesses before a new quest (the pretesting effect)

public enum WarmUp {
    public static let count = 3

    /// Up to 3 guesses about words the quest is about to teach. Guessing first, even wrongly, helps the real
    /// answer stick when it comes. Guesses are NOT recorded as mistakes in the memory model.
    public static func questions(_ quest: Quest, profile p: PlayerProfile, library: ContentLibrary, seed: UInt64) -> [RetentionQuestion] {
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        let fresh = RetentionQuiz.lessonItems(quest).filter { p.knowledge[$0] == nil }.compactMap { library.item($0) }
            .filter { let t = $0.target.text(for: v); return !t.contains("…") && !t.contains("{") }
        return fresh.shuffled(using: &rng).prefix(count).map {
            RetentionQuiz.question($0, kind: .meaning, variant: v, distractors: library.allItems, reason: "Have a guess!", rng: &rng)
        }
    }

    public static func isOffered(_ quest: Quest, profile p: PlayerProfile) -> Bool {
        !p.progress.completedQuests.contains(quest.id) && RetentionQuiz.lessonItems(quest).contains { p.knowledge[$0] == nil }
    }

    public static func finished(profile p: inout PlayerProfile) {
        p.updateMeta { $0.counters[MetaEvent.warmUpDone, default: 0] += 1 }
    }
}

// MARK: - 4. When a word comes back

extension RetentionQuiz {
    /// Days until the word's next review (0 = later today), from the scheduler.
    public static func nextReviewDays(_ itemId: String, profile p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Int? {
        guard let k = p.knowledge[itemId] else { return nil }
        return max(0, Streak.daysBetween(now, k.nextDue, calendar: calendar))
    }

    public static func nextReviewText(_ days: Int?) -> String? {
        guard let d = days else { return nil }
        switch d {
        case 0: return "You'll see this again later today."
        case 1: return "You'll see this again tomorrow."
        default: return "You'll see this again in \(d) days."
        }
    }
}

// MARK: - 5. Memory hooks (a note written right after a miss)

extension WordNotes {
    /// Saves a memory hook from the quiz feedback and counts it.
    public static func addHook(_ text: String, for id: String, profile p: inout PlayerProfile) {
        let had = note(id, in: p) != nil
        set(text, for: id, profile: &p)
        if !had && note(id, in: p) != nil { p.updateMeta { $0.counters[MetaEvent.hookWritten, default: 0] += 1 } }
    }
}

// MARK: - 6. Fill-in-the-blank sentences

public enum Cloze {
    public static let blank = "____"

    /// A sentence that uses the word, with the word blanked out: the word's example first, then lines from quests the
    /// player has reached. Retrieval in context helps the word come back in real conversations.
    public static func sentence(for item: LexItem, profile p: PlayerProfile, library: ContentLibrary) -> (text: String, english: String)? {
        let v = p.variant(for: library)
        let word = item.target.text(for: v)
        guard word.count >= 2, !word.contains(" ") || word.split(separator: " ").count <= 3 else { return nil }
        var candidates: [(String, String)] = []
        if let ex = item.example { candidates.append((ex.target.text(for: v), ex.english)) }
        let quests = library.units.flatMap(\.quests).filter { p.progress.startedQuests.contains($0.id) || p.progress.completedQuests.contains($0.id) }
        for q in quests { for n in q.dialogue.nodes { candidates.append((n.line.text(for: v), n.gloss)) } }
        for (text, english) in candidates where !text.contains("{") && !english.isEmpty && text != word {
            if let r = text.range(of: word, options: [.caseInsensitive]) {
                // Whole word only, where the language uses spaces.
                let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
                let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
                let spaced = text.contains(" ")
                if spaced && ((before?.isLetter ?? false) || (after?.isLetter ?? false)) { continue }
                return (text.replacingCharacters(in: r, with: blank), english)
            }
        }
        return nil
    }
}

// MARK: - 7. Memory check length

public enum MemoryCheckLength: Int, CaseIterable, Sendable { case short = 5, long = 10 }

// MARK: - 8. Streak calendar

public enum DayMark: String, Sendable { case practiced, frozen, none }

public struct StreakDay: Hashable, Identifiable, Sendable {
    public var id: String { day }
    public var day: String
    public var date: Date
    public var mark: DayMark
}

extension Streak {
    /// The last 28 days: practiced, covered by a streak freeze, or neither.
    public static func calendarDays(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> [StreakDay] {
        let frozen = Set(state(p).frozenDays)
        let quizDays = Set((p.extrasOrEmpty.quizHistory ?? []).map { ActivityLog.dayKey($0.date, calendar: calendar) })
        return (0..<28).reversed().map { back in
            let d = calendar.date(byAdding: .day, value: -back, to: now) ?? now
            let k = ActivityLog.dayKey(d, calendar: calendar)
            let practiced = (p.log.activitiesByDay[k] ?? 0) > 0 || quizDays.contains(k) || state(p).lastDay == k
            return StreakDay(day: k, date: d, mark: practiced ? .practiced : frozen.contains(k) ? .frozen : .none)
        }
    }
}

// MARK: - 9. Streak reward outfits (cosmetic only)

public enum StreakRewards {
    public static let byMilestone: [Int: String] = [7: "scarf-flame", 30: "laurel-gold"]

    /// Gives the outfit for a milestone. Returns its id if it's new.
    @discardableResult
    public static func grant(_ milestone: Int, profile p: inout PlayerProfile) -> String? {
        guard let id = byMilestone[milestone], p.rewards.ownedCosmetics.insert(id).inserted else { return nil }
        return id
    }
}

// MARK: - 10. Weekly recap (Monday to Wednesday)

public struct WeeklyRecap: Hashable, Sendable {
    public var weekKey: String
    public var daysPracticed: Int
    public var quizzes: Int
    public var averagePercent: Int?
    public var newWords: Int
    public var line: String

    public static func make(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> WeeklyRecap? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) else { return nil }
        // Shown only in the first 3 days of the week, until dismissed.
        guard Streak.daysBetween(thisWeek, now, calendar: calendar) < 3 else { return nil }
        let key = ActivityLog.dayKey(lastWeek, calendar: calendar)
        guard p.metaOrEmpty.recapDismissed != key else { return nil }
        let days = (0..<7).filter { i in
            guard let d = calendar.date(byAdding: .day, value: i, to: lastWeek) else { return false }
            let k = ActivityLog.dayKey(d, calendar: calendar)
            return (p.log.activitiesByDay[k] ?? 0) > 0 || (p.log.minutesByDay[k] ?? 0) >= 1
        }.count
        let qs = (p.extrasOrEmpty.quizHistory ?? []).filter { $0.date >= lastWeek && $0.date < thisWeek && $0.total > 0 }
        let newWords = p.knowledge.values.filter { ($0.firstSeen ?? .distantPast) >= lastWeek && ($0.firstSeen ?? .distantPast) < thisWeek }.count
        guard days > 0 || !qs.isEmpty else { return nil }
        let avg = qs.isEmpty ? nil : Int((Double(qs.map(\.percent).reduce(0, +)) / Double(qs.count)).rounded())
        var line = "Last week: \(days) day\(days == 1 ? "" : "s") of practice"
        if newWords > 0 { line += ", \(newWords) new word\(newWords == 1 ? "" : "s")" }
        if let a = avg { line += ", quizzes \(a)% on average" }
        return WeeklyRecap(weekKey: key, daysPracticed: days, quizzes: qs.count, averagePercent: avg, newWords: newWords, line: line + ".")
    }

    public static func dismiss(_ r: WeeklyRecap, profile p: inout PlayerProfile) { p.updateMeta { $0.recapDismissed = r.weekKey } }
}

// MARK: - 11. Personal bests

public struct PersonalBests: Hashable, Sendable {
    public var longestStreak: Int
    public var perfectRun: Int
    public var bestWeekAverage: Int?
    public var mostWordsInADay: Int

    public static func make(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> PersonalBests {
        let hist = (p.extrasOrEmpty.quizHistory ?? []).filter { $0.total > 0 }
        var run = 0, best = 0
        for r in hist { run = r.correct == r.total ? run + 1 : 0; best = max(best, run) }
        let weeks = RetentionReport.make(p, now: now, calendar: calendar, weeks: 52).weeks.compactMap(\.averagePercent)
        var perDay: [String: Int] = [:]
        for k in p.knowledge.values { if let f = k.firstSeen { perDay[ActivityLog.dayKey(f, calendar: calendar), default: 0] += 1 } }
        return PersonalBests(longestStreak: Streak.state(p).longest, perfectRun: best,
                             bestWeekAverage: weeks.max(), mostWordsInADay: perDay.values.max() ?? 0)
    }
}

// MARK: - 12. Learning summary for parents

public struct LearningSummary: Hashable, Sendable {
    public var quizzesThisWeek: Int
    public var averageThisWeek: Int?
    public var streak: Int
    public var rememberedNow: Int?
    public var lockedIn: Int

    public static func make(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> LearningSummary {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        let qs = p.allCourseStates.flatMap { $0.extras?.quizHistory ?? [] }.filter { $0.date >= weekAgo && $0.total > 0 }
        let ks = p.allCourseStates.flatMap { Array($0.knowledge.values) }
        let probs = ks.compactMap { RecallModel.probability($0, now: now) }
        return LearningSummary(
            quizzesThisWeek: qs.count,
            averageThisWeek: qs.isEmpty ? nil : Int((Double(qs.map(\.percent).reduce(0, +)) / Double(qs.count)).rounded()),
            streak: Streak.current(p, now: now, calendar: calendar),
            rememberedNow: probs.isEmpty ? nil : Int((probs.reduce(0, +) / Double(probs.count) * 100).rounded()),
            lockedIn: ks.filter { RecallModel.isLockedIn($0, now: now) }.count)
    }
}

// MARK: - 13. Free-trial heads-up (for parents)

public enum TrialNotice {
    public static let daysBefore = 2

    /// When to remind a parent that the free trial is about to end (nil if too late or not a trial).
    public static func reminderDate(trialEnds: Date?, isTrial: Bool, now: Date) -> Date? {
        guard isTrial, let end = trialEnds else { return nil }
        let at = end.addingTimeInterval(-Double(daysBefore) * 86400)
        return at > now.addingTimeInterval(3600) ? at : nil
    }

    public static let body = "The Language Quest Family Plus free trial ends in 2 days. Keep it, or cancel any time in Settings › your name › Subscriptions."
}

// MARK: - 16. Accent keys for typing

public enum AccentKeys {
    /// Letters that are hard to type on an English keyboard, by language. Others use the normal keyboard.
    public static func keys(for courseId: String) -> [String] {
        switch courseId {
        case "en-es": return ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡"]
        case "en-fr": return ["à", "â", "ç", "é", "è", "ê", "ë", "î", "ï", "ô", "ù", "û", "œ"]
        case "en-de": return ["ä", "ö", "ü", "ß"]
        case "en-it": return ["à", "è", "é", "ì", "ò", "ù"]
        case "en-yo": return ["ẹ", "ọ", "ṣ", "á", "à", "é", "è", "ó", "ò"]
        case "en-zh": return ["ā", "á", "ǎ", "à", "ē", "é", "ě", "è", "ī", "ǐ", "ō", "ǒ", "ū", "ǔ", "ǚ"]
        case "en-la": return ["ā", "ē", "ī", "ō", "ū"]
        default: return []
        }
    }
}

// MARK: - 17. First-letter hint

extension RetentionQuiz {
    /// The first letter (or first character) of the answer, for a typed question.
    public static func firstLetterHint(_ q: RetentionQuestion, variant: String) -> String {
        let w = q.word.text(for: variant)
        guard let c = w.first else { return "" }
        return String(c) + String(repeating: " _", count: max(0, min(w.count - 1, 12)))
    }

    /// Marks a hint on the current question: if answered right it won't count as a first-try point.
    public mutating func useHint() { if let q = current, index < questions.count { hinted.insert(q.itemId) } }
}

// MARK: - 19. Achievements

extension Achievement {
    static let v11: [Achievement] = [
        Achievement(id: "a-warmup", title: "Warm-Up Wizard", detail: "Do 5 warm-up guesses before quests.", icon: "flame.circle.fill"),
        Achievement(id: "a-hooks", title: "Hook Maker", detail: "Write 3 memory hooks after a miss.", icon: "link.circle.fill"),
        Achievement(id: "a-streak30", title: "Month of Learning", detail: "Reach a 30-day streak.", icon: "calendar.circle.fill"),
        Achievement(id: "a-perfect3", title: "Perfect Three", detail: "Get 3 perfect quizzes in a row.", icon: "star.circle.fill"),
    ]

    func isMetV11(_ p: PlayerProfile, now: Date) -> Bool? {
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-warmup": return (c[MetaEvent.warmUpDone] ?? 0) >= 5
        case "a-hooks": return (c[MetaEvent.hookWritten] ?? 0) >= 3
        case "a-streak30": return Streak.state(p).longest >= 30
        case "a-perfect3": return PersonalBests.make(p, now: now).perfectRun >= 3
        default: return nil
        }
    }

    func progressV11(_ p: PlayerProfile, now: Date) -> AchievementProgress? {
        let c = p.metaOrEmpty.counters
        func prog(_ n: Int, _ t: Int) -> AchievementProgress { AchievementProgress(current: min(n, t), target: t) }
        switch id {
        case "a-warmup": return prog(c[MetaEvent.warmUpDone] ?? 0, 5)
        case "a-hooks": return prog(c[MetaEvent.hookWritten] ?? 0, 3)
        case "a-streak30": return prog(Streak.state(p).longest, 30)
        case "a-perfect3": return prog(PersonalBests.make(p, now: now).perfectRun, 3)
        default: return nil
        }
    }
}
