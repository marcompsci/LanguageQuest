import Foundation

// v1.0: memory science + coming back + Family Plus.
// Everything here runs on the device. Sources for each technique are in docs/learning-science.md.

extension MetaEvent {
    static let lessonQuizPerfect = "lessonQuizPerfect"
    static let memoryCheckDone = "memoryCheckDone"
}

// MARK: - 1. Predicted recall (half-life model, after Settles & Meeder 2016)

public enum RecallModel {
    /// Recall probability p = 2^(-Δ/h): Δ = days since last practice, h = the word's half-life in days.
    /// The scheduler's interval is used as the half-life, so a word comes due when recall has fallen to about one half.
    public static func probability(_ m: MemoryState, now: Date) -> Double? {
        guard let last = m.lastReviewed else { return nil }
        let h = max(0.25, m.intervalDays)
        let delta = max(0, now.timeIntervalSince(last) / 86400)
        return pow(2, -delta / h)
    }

    /// For a word: the weaker of understanding and producing (producing usually fades first).
    public static func probability(_ k: ItemKnowledge, now: Date) -> Double? {
        let c = probability(k.comprehension, now: now), p = probability(k.production, now: now)
        switch (c, p) {
        case let (c?, p?): return min(c, p)
        case let (c?, nil): return c
        case let (nil, p?): return p
        default: return nil
        }
    }

    /// "Locked in": retrieved correctly after a delay at least 3 times (successive relearning, Rawson & Dunlosky)
    /// and still more likely than not to be remembered now.
    public static func isLockedIn(_ k: ItemKnowledge, now: Date) -> Bool {
        (k.comprehension.delayedCorrect + k.production.delayedCorrect) >= 3 && (probability(k, now: now) ?? 0) >= 0.5
    }
}

// MARK: - 2. Priority 5-question quiz (end of every lesson, and the memory check)

public enum RetentionQuestionKind: String, Codable, Sendable {
    /// See the word, pick the meaning (recognition).
    case meaning
    /// Hear the word, pick the meaning (listening).
    case listen
    /// See the meaning, pick the word.
    case pickWord
    /// See the meaning, type the word (production: the strongest memory boost).
    case typeIt
}

public struct RetentionQuestion: Hashable, Sendable, Identifiable {
    public var id: String { itemId + kind.rawValue }
    public var itemId: String
    public var kind: RetentionQuestionKind
    public var word: VText
    public var meaning: String
    /// Multiple-choice options (empty for typeIt).
    public var options: [String]
    public var optionTexts: [VText]?
    public var answerIndex: Int
    /// Why this word was chosen, shown after answering.
    public var reason: String

    public var track: PracticeTrack {
        switch kind {
        case .meaning, .listen: return .comprehension
        case .pickWord: return .guidedProduction
        case .typeIt: return .spontaneousProduction
        }
    }
}

public enum RetentionQuizKind: Hashable, Sendable {
    case lesson(questId: String)
    case memoryCheck
}

public struct RetentionQuiz: Sendable {
    public static let size = 5
    public let kind: RetentionQuizKind
    public private(set) var questions: [RetentionQuestion]
    public private(set) var index = 0
    /// First-try results only (the score).
    public private(set) var firstTry: [String: Bool] = [:]
    /// Missed questions come back at the end until answered right (successive relearning in miniature).
    public private(set) var relearnQueue: [RetentionQuestion] = []
    public private(set) var relearned: Set<String> = []

    /// Priority = how close a word is to being forgotten (half-life model), how often it was missed,
    /// and, for a lesson, whether the lesson just taught it. New words in the lesson always come first.
    public static func priority(_ id: String, profile p: PlayerProfile, lessonItems: Set<String>, now: Date) -> Double {
        let k = p.knowledge[id]
        let risk = 1 - (k.flatMap { RecallModel.probability($0, now: now) } ?? 0.5)
        let lapses = Double((k?.comprehension.lapses ?? 0) + (k?.production.lapses ?? 0))
        let inLesson = lessonItems.contains(id) ? 1.0 : 0
        let missedInLesson = lessonItems.contains(id) && (k?.comprehension.accuracy ?? 1) < 1 ? 0.5 : 0
        return risk * 2 + min(lapses, 3) * 0.4 + inLesson * 1.5 + missedInLesson
    }

    public static func lessonItems(_ quest: Quest) -> [String] {
        var seen = Set<String>()
        return quest.activities.flatMap(\.items).filter { seen.insert($0).inserted }
    }

    public init(kind: RetentionQuizKind, profile p: PlayerProfile, library: ContentLibrary, now: Date, seed: UInt64) {
        self.kind = kind
        var rng = SeededRandom(seed: seed)
        let v = p.variant(for: library)
        let lesson: [String]
        switch kind {
        case .lesson(let qid): lesson = library.quest(qid).map { Self.lessonItems($0.quest) } ?? []
        case .memoryCheck: lesson = []
        }
        let lessonSet = Set(lesson)
        // The pool: this lesson's words plus every word met so far (a lesson quiz can mix in a fading older word).
        var pool = lesson + p.knowledge.keys.sorted()
        if pool.isEmpty { pool = p.reachedUnits(library).flatMap(\.allItems).map(\.id) }
        var seen = Set<String>()
        let usable = pool.filter { id in
            guard seen.insert(id).inserted, let item = library.item(id) else { return false }
            let t = item.target.text(for: v)
            return !t.contains("…") && !t.contains("{") && t.count <= 40
        }
        // Small courses: top up from the units reached so there are always 5 questions when possible.
        var usableAll = usable
        if usableAll.count < Self.size {
            for item in p.reachedUnits(library).flatMap(\.allItems) where usableAll.count < Self.size && !usableAll.contains(item.id) {
                let t = item.target.text(for: v)
                if !t.contains("…") && !t.contains("{") && t.count <= 40 { usableAll.append(item.id) }
            }
        }
        let ranked = usableAll.map { ($0, Self.priority($0, profile: p, lessonItems: lessonSet, now: now) + Double.random(in: 0..<0.05, using: &rng)) }
            .sorted { $0.1 > $1.1 }.map(\.0)
        var picks = Array(ranked.prefix(Self.size))
        // A lesson quiz is mostly about the lesson: at least 3 of its words when it has them.
        if case .lesson = kind {
            let fromLesson = picks.filter { lessonSet.contains($0) }.count
            if fromLesson < 3 {
                let extra = ranked.filter { lessonSet.contains($0) && !picks.contains($0) }.prefix(3 - fromLesson)
                picks = picks.filter { lessonSet.contains($0) } + Array(extra) + picks.filter { !lessonSet.contains($0) }
                picks = Array(picks.prefix(Self.size))
            }
        }
        // Easier to harder (recognition, listening, then producing the word), mixed across words (interleaving).
        let kinds: [RetentionQuestionKind] = [.meaning, .listen, .pickWord, .typeIt, .typeIt]
        let distractorPool = library.allItems
        questions = picks.enumerated().compactMap { (n, id) -> RetentionQuestion? in
            guard let item = library.item(id) else { return nil }
            let k = p.knowledge[id]
            let r = k.flatMap { RecallModel.probability($0, now: now) }
            let reason: String
            if lessonSet.contains(id) && ((k?.comprehension.reviewCount ?? 0) + (k?.production.reviewCount ?? 0)) <= 4 { reason = "New in this lesson" }
            else if let r, r < 0.5 { reason = "Starting to fade" }
            else if (k?.comprehension.lapses ?? 0) + (k?.production.lapses ?? 0) > 0 { reason = "Missed before" }
            else { reason = "Keep it fresh" }
            return Self.question(item, kind: kinds[n % kinds.count], variant: v, distractors: distractorPool, reason: reason, rng: &rng)
        }
    }

    static func question(_ item: LexItem, kind: RetentionQuestionKind, variant v: String, distractors: [LexItem],
                         reason: String, rng: inout SeededRandom) -> RetentionQuestion {
        let others = distractors.filter { $0.id != item.id }.shuffled(using: &rng)
        switch kind {
        case .meaning, .listen:
            var opts = [item.english]
            for o in others where opts.count < 4 && !opts.contains(where: { AnswerChecker.normalize($0) == AnswerChecker.normalize(o.english) }) {
                opts.append(o.english)
            }
            opts.shuffle(using: &rng)
            return RetentionQuestion(itemId: item.id, kind: kind, word: item.target, meaning: item.english, options: opts,
                                     optionTexts: nil, answerIndex: opts.firstIndex(of: item.english) ?? 0, reason: reason)
        case .pickWord:
            var words = [item.target]
            for o in others where words.count < 4 && !words.contains(where: { AnswerChecker.normalize($0.text(for: v)) == AnswerChecker.normalize(o.target.text(for: v)) }) {
                words.append(o.target)
            }
            words.shuffle(using: &rng)
            return RetentionQuestion(itemId: item.id, kind: kind, word: item.target, meaning: item.english,
                                     options: words.map { $0.text(for: v) }, optionTexts: words,
                                     answerIndex: words.firstIndex(of: item.target) ?? 0, reason: reason)
        case .typeIt:
            return RetentionQuestion(itemId: item.id, kind: .typeIt, word: item.target, meaning: item.english, options: [],
                                     optionTexts: nil, answerIndex: 0, reason: reason)
        }
    }

    public var current: RetentionQuestion? {
        if index < questions.count { return questions[index] }
        return relearnQueue.first
    }
    public var isRelearning: Bool { index >= questions.count && !relearnQueue.isEmpty }
    public var isFinished: Bool { index >= questions.count && relearnQueue.isEmpty }
    public var correctCount: Int { firstTry.values.filter { $0 }.count }
    public var total: Int { questions.count }
    public var missedIds: [String] { questions.filter { firstTry[$0.itemId] == false }.map(\.itemId) }

    /// Answers the current question (choice index, or typed text for typeIt). Returns whether it was right.
    @discardableResult
    public mutating func answer(choice: Int? = nil, typed: String? = nil, variant: String, context: CheckContext) -> Bool {
        guard let q = current else { return false }
        let ok: Bool
        if q.kind == .typeIt {
            ok = AnswerChecker.check(typed ?? "", accepted: [q.word], variant: variant, context: context).isCorrect
        } else {
            ok = choice == q.answerIndex
        }
        if index < questions.count {
            firstTry[q.itemId] = ok
            index += 1
            // A missed word comes back at the end as a multiple-choice retry (easier, with the answer fresh from feedback).
            if !ok {
                var retry = q
                if retry.kind == .typeIt || retry.kind == .listen {
                    var rng = SeededRandom(seed: q.itemId.hashValueStable)
                    let opts = ([q.meaning] + questions.map(\.meaning).filter { $0 != q.meaning }).prefix(4).shuffled(using: &rng)
                    retry = RetentionQuestion(itemId: q.itemId, kind: .meaning, word: q.word, meaning: q.meaning,
                                              options: Array(opts), optionTexts: nil, answerIndex: opts.firstIndex(of: q.meaning) ?? 0,
                                              reason: "One more try")
                    if Set(opts).count < 2 { return ok }   // not enough options for a fair retry
                }
                relearnQueue.append(retry)
            }
        } else {
            relearnQueue.removeFirst()
            if ok { relearned.insert(q.itemId) } else if relearned.count + relearnQueue.count < 10 { relearnQueue.append(q) }
        }
        return ok
    }

    /// Records each answer in the memory model.
    public static func record(_ q: RetentionQuestion, correct ok: Bool, profile p: inout PlayerProfile, now: Date) {
        PracticeRecorder.record(itemId: q.itemId, outcome: ReviewOutcome(correct: ok), track: q.track, profile: &p, now: now)
    }

    /// Saves the result to the quiz history and counts it for the streak.
    @discardableResult
    public static func finish(_ quiz: RetentionQuiz, profile p: inout PlayerProfile, library: ContentLibrary, now: Date) -> QuizRecord {
        var questId: String? = nil
        if case .lesson(let q) = quiz.kind { questId = q }
        let rec = QuizRecord(date: now, courseId: library.course.id, isLesson: questId != nil, questId: questId,
                             correct: quiz.correctCount, total: quiz.total, missed: quiz.missedIds)
        p.updateExtras { e in
            var h = e.quizHistory ?? []
            h.append(rec)
            if h.count > QuizRecord.keep { h.removeFirst(h.count - QuizRecord.keep) }
            e.quizHistory = h
        }
        p.updateMeta { m in
            if questId != nil && quiz.total > 0 && quiz.correctCount == quiz.total { m.counters[MetaEvent.lessonQuizPerfect, default: 0] += 1 }
            if questId == nil { m.counters[MetaEvent.memoryCheckDone, default: 0] += 1 }
        }
        Streak.recordPractice(&p, now: now)
        return rec
    }
}

// MARK: - 3. Progress over time

public struct QuizRecord: Codable, Hashable, Sendable {
    public static let keep = 300
    public var date: Date
    public var courseId: String
    public var isLesson: Bool
    public var questId: String?
    public var correct: Int
    public var total: Int
    public var missed: [String]
    public var percent: Int { total == 0 ? 0 : Int((Double(correct) / Double(total) * 100).rounded()) }
}

public struct WeekScore: Hashable, Identifiable, Sendable {
    public var id: String { weekStart }
    public var weekStart: String
    public var date: Date
    public var quizzes: Int
    public var averagePercent: Int?
}

public struct RetentionReport: Sendable {
    public var wordsMet: Int
    public var lockedIn: Int
    public var fading: Int
    /// Average predicted recall of every word met, 0–100.
    public var predictedRetention: Int?
    public var lessonQuizzes: Int
    public var memoryChecks: Int
    public var averageLast10: Int?
    public var weeks: [WeekScore]
    public var mostMissed: [String]

    public static func make(_ p: PlayerProfile, now: Date, calendar: Calendar = .current, weeks n: Int = 8) -> RetentionReport {
        let ks = Array(p.knowledge.values)
        let probs = ks.compactMap { RecallModel.probability($0, now: now) }
        let hist = p.extrasOrEmpty.quizHistory ?? []
        var weeks: [WeekScore] = []
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        for back in (0..<n).reversed() {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            let inWeek = hist.filter { $0.date >= start && $0.date < end && $0.total > 0 }
            let avg = inWeek.isEmpty ? nil : Int((Double(inWeek.map(\.percent).reduce(0, +)) / Double(inWeek.count)).rounded())
            weeks.append(WeekScore(weekStart: ActivityLog.dayKey(start, calendar: calendar), date: start, quizzes: inWeek.count, averagePercent: avg))
        }
        var missCount: [String: Int] = [:]
        for r in hist.suffix(50) { for m in r.missed { missCount[m, default: 0] += 1 } }
        let last10 = hist.suffix(10).filter { $0.total > 0 }
        return RetentionReport(
            wordsMet: ks.count,
            lockedIn: ks.filter { RecallModel.isLockedIn($0, now: now) }.count,
            fading: probs.filter { $0 < 0.5 }.count,
            predictedRetention: probs.isEmpty ? nil : Int((probs.reduce(0, +) / Double(probs.count) * 100).rounded()),
            lessonQuizzes: hist.filter(\.isLesson).count,
            memoryChecks: hist.filter { !$0.isLesson }.count,
            averageLast10: last10.isEmpty ? nil : Int((Double(last10.map(\.percent).reduce(0, +)) / Double(last10.count)).rounded()),
            weeks: weeks,
            mostMissed: missCount.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(5).map(\.key))
    }
}

// MARK: - 4. Gentle streak (2 free freezes a week, kind restarts)

public struct StreakState: Codable, Hashable, Sendable {
    public var current = 0
    public var longest = 0
    public var lastDay: String? = nil
    public var freezesLeft = Streak.freezesPerWeek
    public var freezeWeek: String? = nil
    /// Days a freeze covered (for the calendar).
    public var frozenDays: [String] = []
    /// The last milestone celebrated.
    public var celebrated = 0
    public init() {}
}

public enum StreakStatus: Equatable, Sendable { case none, practicedToday, waitingToday }

public enum Streak {
    public static let freezesPerWeek = 2
    public static let milestones = [3, 7, 14, 30, 50, 100, 365]

    public static func state(_ p: PlayerProfile) -> StreakState { p.metaOrEmpty.streak ?? StreakState() }

    /// The streak as it stands now: a gap longer than the freezes can cover shows as 0 (it restarts next practice).
    public static func current(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> Int {
        var s = state(p)
        refill(&s, now: now, calendar: calendar)
        guard let last = s.lastDay, let lastDate = date(last, calendar: calendar) else { return 0 }
        let gap = daysBetween(lastDate, now, calendar: calendar)
        if gap <= 1 { return s.current }
        return gap - 1 <= s.freezesLeft ? s.current : 0
    }

    public static func status(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> StreakStatus {
        let s = state(p)
        if s.lastDay == ActivityLog.dayKey(now, calendar: calendar) { return .practicedToday }
        return current(p, now: now, calendar: calendar) > 0 ? .waitingToday : .none
    }

    /// Counts a real practice (a lesson, a quiz, a memory check or a review): opening the app doesn't count.
    /// Returns a milestone reached today, if any.
    @discardableResult
    public static func recordPractice(_ p: inout PlayerProfile, now: Date, calendar: Calendar = .current) -> Int? {
        var s = state(p)
        refill(&s, now: now, calendar: calendar)
        let today = ActivityLog.dayKey(now, calendar: calendar)
        guard s.lastDay != today else { return nil }
        if let last = s.lastDay, let lastDate = date(last, calendar: calendar) {
            let missed = daysBetween(lastDate, now, calendar: calendar) - 1
            if missed <= 0 {
                s.current += 1
            } else if missed <= s.freezesLeft {
                s.freezesLeft -= missed
                for i in 1...missed {
                    if let d = calendar.date(byAdding: .day, value: i, to: lastDate) { s.frozenDays.append(ActivityLog.dayKey(d, calendar: calendar)) }
                }
                s.frozenDays = Array(s.frozenDays.suffix(30))
                s.current += 1
            } else {
                s.current = 1
                s.celebrated = 0
            }
        } else {
            s.current = 1
        }
        s.lastDay = today
        s.longest = max(s.longest, s.current)
        var reached: Int? = nil
        if let m = milestones.last(where: { $0 <= s.current }), m > s.celebrated { s.celebrated = m; reached = m }
        let final = s
        p.updateMeta { $0.streak = final }
        return reached
    }

    /// A kind line about the streak. It never warns about losing anything.
    public static func message(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> String {
        let c = current(p, now: now, calendar: calendar)
        let s = state(p)
        switch status(p, now: now, calendar: calendar) {
        case .practicedToday: return c == 1 ? "Day 1. Every streak starts here!" : "\(c) days in a row. Nice work today!"
        case .waitingToday: return "\(c)-day streak. One lesson or a 5-question check keeps it going."
        case .none: return s.longest > 0 ? "Fresh start! Your best was \(s.longest) days." : "Do a lesson today to start a streak."
        }
    }

    static func refill(_ s: inout StreakState, now: Date, calendar: Calendar) {
        let week = WeeklyGoal.weekKey(now, calendar: calendar)
        if s.freezeWeek != week { s.freezeWeek = week; s.freezesLeft = freezesPerWeek }
    }

    static func date(_ key: String, calendar: Calendar) -> Date? {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    static func daysBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}

// MARK: - 5. Smart "come back" reminders (on-device, after Duolingo's recovering bandit, Yancey & Settles 2020)

public struct ReminderTemplate: Hashable, Sendable {
    public var id: String
    public var body: String
    /// When this template makes sense.
    public var needs: Need
    public enum Need: Hashable, Sendable { case any, streak, dueWords, newLesson, comeback }
}

public struct TemplateStats: Codable, Hashable, Sendable {
    public var sent = 0
    public var opened = 0
    public var lastSent: Date? = nil
    public init() {}
}

public struct PlannedReminder: Hashable, Sendable {
    public var date: Date
    public var templateId: String
    public var body: String
}

public enum SmartReminders {
    /// Friendly copy only: no names, no numbers about the child, nothing about losing anything.
    public static let templates: [ReminderTemplate] = [
        .init(id: "streak", body: "Your streak is waiting for today's lesson. A 5-question check counts!", needs: .streak),
        .init(id: "due", body: "Some words are ready for review. Catch them now, before they fade.", needs: .dueWords),
        .init(id: "lesson", body: "A new quest is waiting in the village.", needs: .newLesson),
        .init(id: "short", body: "Got 3 minutes? A quick memory check keeps your words fresh.", needs: .any),
        .init(id: "friend", body: "Your village friends are saying hello! Ready to practice?", needs: .any),
        .init(id: "comeback", body: "It's been a little while. Your words are still here: let's pick up where you left off.", needs: .comeback),
    ]

    public static let earliestHour = 8
    public static let latestHour = 20          // nothing after 8:30 pm: quiet hours for young players
    public static let defaultMinutes = 17 * 60 + 30
    /// Days after the last session that get a reminder; Duolingo-style backing off so silence follows a long break.
    public static let dayOffsets = [0, 1, 2, 3, 5, 7, 14]

    /// Learns the usual practice time: the median start time of recent sessions, kept inside 8:00–20:30.
    public static func preferredMinutes(_ p: PlayerProfile, calendar: Calendar = .current) -> Int {
        let starts = (p.metaOrEmpty.sessionStarts ?? []).suffix(14)
        guard starts.count >= 3 else { return defaultMinutes }
        let mins = starts.map { d -> Int in let c = calendar.dateComponents([.hour, .minute], from: d); return (c.hour ?? 17) * 60 + (c.minute ?? 0) }.sorted()
        let median = mins[mins.count / 2]
        return min(max(median, earliestHour * 60), latestHour * 60 + 30)
    }

    public static func noteSessionStart(_ p: inout PlayerProfile, now: Date) {
        p.updateMeta { m in
            var s = m.sessionStarts ?? []
            if let last = s.last, now.timeIntervalSince(last) < 30 * 60 { return }   // one per session
            s.append(now)
            m.sessionStarts = Array(s.suffix(30))
        }
    }

    /// Records that a reminder was opened (from the notification tap), so better messages are picked more often.
    public static func noteOpened(_ templateId: String, profile p: inout PlayerProfile) {
        p.updateMeta { m in var st = m.reminderStats ?? [:]; st[templateId, default: TemplateStats()].opened += 1; m.reminderStats = st }
    }

    public static func noteSent(_ planned: [PlannedReminder], profile p: inout PlayerProfile) {
        p.updateMeta { m in
            var st = m.reminderStats ?? [:]
            for r in planned { st[r.templateId, default: TemplateStats()].sent += 1; st[r.templateId]?.lastSent = r.date }
            m.reminderStats = st
        }
    }

    /// Picks a template: eligible ones only; the best open rate wins, but one used in the last 2 days rests
    /// (the "recovering" idea: a message works less well when it's seen too often).
    public static func pick(_ need: Set<ReminderTemplate.Need>, stats: [String: TemplateStats], at date: Date, used: [String]) -> ReminderTemplate {
        let eligible = templates.filter { need.contains($0.needs) || $0.needs == .any }
        func score(_ t: ReminderTemplate) -> Double {
            let s = stats[t.id] ?? TemplateStats()
            var v = Double(s.opened + 1) / Double(s.sent + 2)                    // smoothed open rate
            if used.suffix(2).contains(t.id) { v *= 0.2 }                       // resting
            if let last = s.lastSent, date.timeIntervalSince(last) < 2 * 86400 { v *= 0.6 }
            if t.needs != .any { v += 0.15 }                                     // a specific message beats a generic one
            return v
        }
        return eligible.max { a, b in score(a) == score(b) ? a.id > b.id : score(a) < score(b) } ?? templates[3]
    }

    /// Plans the next reminders from the player's activity. Today only if they haven't practiced yet.
    public static func plan(_ p: PlayerProfile, now: Date, dueWords: Int, hasNewLesson: Bool,
                            calendar: Calendar = .current) -> [PlannedReminder] {
        let minutes = preferredMinutes(p, calendar: calendar)
        let practicedToday = Streak.status(p, now: now, calendar: calendar) == .practicedToday
        let lastActive = (p.metaOrEmpty.sessionStarts ?? []).last ?? now
        var out: [PlannedReminder] = []
        var used: [String] = []
        let stats = p.metaOrEmpty.reminderStats ?? [:]
        for offset in dayOffsets {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let at = calendar.date(byAdding: .minute, value: minutes, to: day) else { continue }
            if offset == 0 && (practicedToday || at < now.addingTimeInterval(15 * 60)) { continue }
            let away = Streak.daysBetween(lastActive, at, calendar: calendar)
            var need: Set<ReminderTemplate.Need> = []
            if Streak.current(p, now: now, calendar: calendar) >= 2 && offset <= 1 { need.insert(.streak) }
            if dueWords > 0 { need.insert(.dueWords) }
            if hasNewLesson { need.insert(.newLesson) }
            if away >= 3 { need = [.comeback] }
            let t = pick(need, stats: stats, at: at, used: used)
            used.append(t.id)
            out.append(PlannedReminder(date: at, templateId: t.id, body: t.body))
        }
        return out
    }
}

extension LearnerSettings {
    public var smartRemindersOn: Bool { smartReminders ?? false }
}

// MARK: - 6. Family Plus: what's free and what's Plus

public enum PlusOffer {
    /// Shown on the paywall. Everything needed to learn and remember stays free.
    public static let benefits = [
        "Units 2 and 3 of Spanish, French and Japanese (and new units as they're added)",
        "Extra games: Memory Match, Market Rush and the Speed duel",
        "Up to 4 explorers on this device",
    ]
    public static let alwaysFree = [
        "Unit 1 of every language, and every starter course",
        "Reviews, lesson quizzes, memory checks and the Word Library",
        "Parent tools, privacy controls and accessibility settings",
    ]
    public static let trialDays = 7

    /// The disclosure Apple asks for next to the subscribe button (guideline 3.1.2): price, period, renewal, how to cancel.
    public static func disclosure(price: String, period: String, hasTrial: Bool) -> String {
        let trial = hasTrial ? "Free for \(trialDays) days, then \(price) per \(period). " : "\(price) per \(period). "
        return trial + "The subscription renews automatically unless it's cancelled at least 24 hours before the end of the current period. " +
            "Payment is charged to the Apple Account at confirmation of purchase (after the trial, if there is one). " +
            "Manage or cancel any time in Settings › your name › Subscriptions."
    }
}

extension Feature {
    /// Plus-only games.
    public static let plusGames: Set<String> = ["memory", "market", "speedDuel"]
}

extension FeatureGate {
    public static func isGameAvailable(_ id: String, plan: Plan, config: StoreConfig = .default) -> Bool {
        guard Feature.plusGames.contains(id) else { return true }
        return !config.paidPlansEnabled || plan == .familyPlus
    }
}

// MARK: - 7. Welcome back

public struct WelcomeBack: Sendable {
    public var daysAway: Int
    public var fadingWords: Int
    public var message: String

    /// Shown when the player returns after 2 or more days: what's fading and one easy step.
    public static func make(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> WelcomeBack? {
        guard let lastDay = Streak.state(p).lastDay ?? p.log.activitiesByDay.keys.max(),
              let last = Streak.date(lastDay, calendar: calendar) else { return nil }
        let away = Streak.daysBetween(last, now, calendar: calendar)
        guard away >= 2 else { return nil }
        let fading = p.knowledge.values.filter { (RecallModel.probability($0, now: now) ?? 1) < 0.5 }.count
        let msg = fading > 0
            ? "Welcome back! \(fading) word\(fading == 1 ? " is" : "s are") starting to fade. A 5-question memory check brings them back."
            : "Welcome back! A quick memory check is a great way to warm up."
        return WelcomeBack(daysAway: away, fadingWords: fading, message: msg)
    }
}

// MARK: - 8. Achievements

extension Achievement {
    static let v10: [Achievement] = [
        Achievement(id: "a-streak7", title: "Week Warrior", detail: "Reach a 7-day streak.", icon: "flame.fill"),
        Achievement(id: "a-quizace", title: "Lesson Ace", detail: "Get 5 of 5 on 5 lesson quizzes.", icon: "graduationcap.fill"),
        Achievement(id: "a-lockedin", title: "Memory Vault", detail: "Lock in 10 words (remembered 3 times after a break).", icon: "lock.shield.fill"),
        Achievement(id: "a-check5", title: "Fresh Mind", detail: "Do 5 memory checks.", icon: "brain.head.profile"),
    ]

    func isMetV10(_ p: PlayerProfile, now: Date) -> Bool? {
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-streak7": return Streak.state(p).longest >= 7
        case "a-quizace": return (c[MetaEvent.lessonQuizPerfect] ?? 0) >= 5
        case "a-lockedin": return p.allCourseStates.reduce(0) { $0 + $1.knowledge.values.filter { RecallModel.isLockedIn($0, now: now) }.count } >= 10
        case "a-check5": return (c[MetaEvent.memoryCheckDone] ?? 0) >= 5
        default: return nil
        }
    }

    func progressV10(_ p: PlayerProfile, now: Date) -> AchievementProgress? {
        let c = p.metaOrEmpty.counters
        func prog(_ n: Int, _ t: Int) -> AchievementProgress { AchievementProgress(current: min(n, t), target: t) }
        switch id {
        case "a-streak7": return prog(Streak.state(p).longest, 7)
        case "a-quizace": return prog(c[MetaEvent.lessonQuizPerfect] ?? 0, 5)
        case "a-lockedin": return prog(p.allCourseStates.reduce(0) { $0 + $1.knowledge.values.filter { RecallModel.isLockedIn($0, now: now) }.count }, 10)
        case "a-check5": return prog(c[MetaEvent.memoryCheckDone] ?? 0, 5)
        default: return nil
        }
    }
}
