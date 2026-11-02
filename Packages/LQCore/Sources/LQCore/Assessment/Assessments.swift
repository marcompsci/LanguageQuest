import Foundation

/// One answered question inside an assessment.
public struct AssessmentAnswer: Sendable {
    public var activity: Activity
    public var correct: Bool
    public init(activity: Activity, correct: Bool) { self.activity = activity; self.correct = correct }
}

public enum AssessmentScoring {
    public static func score(_ answers: [AssessmentAnswer]) -> [Skill: SkillScore] {
        var out: [Skill: SkillScore] = [:]
        for a in answers {
            var s = out[a.activity.skill] ?? SkillScore()
            s.total += 1
            if a.correct { s.correct += 1 }
            out[a.activity.skill] = s
        }
        return out
    }

    public static func percent(_ answers: [AssessmentAnswer]) -> Int {
        guard !answers.isEmpty else { return 0 }
        return Int((Double(answers.filter(\.correct).count) / Double(answers.count) * 100).rounded())
    }
}

/// Baseline placement. Age is never used: placement is by demonstrated skill.
///
/// For each unit in order, asks that unit's mastery-check questions (up to
/// `questionsPerUnit`). If the learner gets at least `passPercent`, the unit is
/// placed out and the next unit is tried; otherwise placement stops there.
/// Learners can always skip placement and start at Unit 1.
public struct PlacementSession: Sendable {
    public static let questionsPerUnit = 4
    public static let passPercent = 75

    public let library: ContentLibrary
    public private(set) var unitIndex = 0
    public private(set) var questionIndex = 0
    public private(set) var answers: [AssessmentAnswer] = []
    private var unitAnswers: [AssessmentAnswer] = []
    public private(set) var placedOut: [String] = []
    public private(set) var finished = false

    public init(library: ContentLibrary) {
        self.library = library
        if library.units.isEmpty { finished = true }
    }

    private func questions(for u: LessonUnit) -> [Activity] {
        Array(u.masteryCheck.activities.prefix(Self.questionsPerUnit))
    }

    public var currentUnit: LessonUnit? { finished ? nil : library.units[unitIndex] }

    public var currentQuestion: Activity? {
        guard let u = currentUnit else { return nil }
        let qs = questions(for: u)
        return questionIndex < qs.count ? qs[questionIndex] : nil
    }

    public mutating func answer(correct: Bool) {
        guard let q = currentQuestion, let u = currentUnit else { return }
        let a = AssessmentAnswer(activity: q, correct: correct)
        answers.append(a)
        unitAnswers.append(a)
        questionIndex += 1
        if questionIndex >= questions(for: u).count {
            if AssessmentScoring.percent(unitAnswers) >= Self.passPercent {
                placedOut.append(u.id)
                unitIndex += 1
                questionIndex = 0
                unitAnswers = []
                if unitIndex >= library.units.count { finished = true }
            } else {
                finished = true
            }
        }
    }

    /// "I'm new to Spanish": end now with nothing placed out.
    public mutating func skip() { finished = true }

    public func result(now: Date) -> AssessmentResult {
        AssessmentResult(kind: .baseline, date: now, unitId: nil, bySkill: AssessmentScoring.score(answers), passed: nil)
    }

    public func apply(to profile: inout PlayerProfile, now: Date) {
        profile.progress.placedOutUnits.formUnion(placedOut)
        profile.assessments.append(result(now: now))
    }
}

public enum MasteryCheckGrader {
    public static func grade(unit: LessonUnit, answers: [AssessmentAnswer], now: Date) -> AssessmentResult {
        let pct = AssessmentScoring.percent(answers)
        return AssessmentResult(kind: .masteryCheck, date: now, unitId: unit.id,
                                bySkill: AssessmentScoring.score(answers), passed: pct >= unit.masteryCheck.passPercent)
    }

    public static func apply(_ r: AssessmentResult, unit: LessonUnit, badge: String, profile: inout PlayerProfile) {
        profile.assessments.append(r)
        if r.passed == true {
            profile.progress.passedMasteryChecks.insert(unit.masteryCheck.id)
            profile.rewards.badges.insert(badge)
        }
    }
}

/// Periodic retention checks: short quizzes on items not seen for a week.
public enum RetentionCheck {
    public static let minDaysBetweenChecks: Double = 7

    public static func isDue(_ profile: PlayerProfile, now: Date) -> Bool {
        let last = profile.assessments.filter { $0.kind == .retention }.map(\.date).max()
        if let l = last, now.timeIntervalSince(l) < minDaysBetweenChecks * SpacedScheduler.day { return false }
        return !ReviewPlanner.retentionCandidates(profile.knowledge, now: now, limit: 3).isEmpty
    }

    /// Picks one comprehension activity per candidate item, deterministically.
    public static func build(_ profile: PlayerProfile, library: ContentLibrary, now: Date, limit: Int = 6) -> [Activity] {
        let ids = ReviewPlanner.retentionCandidates(profile.knowledge, now: now, limit: limit)
        let pool = library.units.flatMap(\.allActivities)
        var chosen: [Activity] = []
        var used = Set<String>()
        for id in ids {
            if let a = pool.first(where: { $0.items.contains(id) && PracticeTrack.of($0) == .comprehension && !used.contains($0.id) }) {
                chosen.append(a)
                used.insert(a.id)
            }
        }
        return chosen
    }
}

// MARK: - Parent report

/// What the parent dashboard shows. Activity (time, XP) is kept visibly
/// separate from demonstrated mastery.
public struct ParentReport: Sendable {
    public struct UnitLine: Sendable {
        public var unitId: String
        public var title: String
        public var questsDone: Int
        public var questsTotal: Int
        public var masteryCheckPassed: Bool
        public var placedOut: Bool
    }
    public struct Usage: Sendable {
        public var minutesLast7Days: Double
        public var activitiesLast7Days: Int
        public var xp: Int
    }
    public struct Mastery: Sendable {
        public var understood: [String]   // comprehension mastered (item ids)
        public var canUse: [String]       // comprehension + spontaneous production
        public var learning: Int
        public var dueForReview: Int
        public var delayedRetentionPercent: Int?
        public var bySkill: [Skill: SkillScore]  // from first-try accuracy per skill
    }

    public var units: [UnitLine]
    public var usage: Usage
    public var mastery: Mastery
    public var latestBaseline: AssessmentResult?
    public var retentionHistory: [AssessmentResult]
    public var offlineSuggestions: [String]

    public static func build(_ p: PlayerProfile, library: ContentLibrary, now: Date, calendar: Calendar = .current) -> ParentReport {
        let units = library.units.map { u in
            UnitLine(unitId: u.id, title: u.title,
                     questsDone: u.quests.filter { p.progress.completedQuests.contains($0.id) }.count,
                     questsTotal: u.quests.count,
                     masteryCheckPassed: p.progress.passedMasteryChecks.contains(u.masteryCheck.id),
                     placedOut: p.progress.placedOutUnits.contains(u.id))
        }
        var mins = 0.0, acts = 0
        for d in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -d, to: now) else { continue }
            let k = ActivityLog.dayKey(day, calendar: calendar)
            mins += p.log.minutesByDay[k] ?? 0
            acts += p.log.activitiesByDay[k] ?? 0
        }
        let understood = p.knowledge.filter { $0.value.comprehensionMastered }.map(\.key).sorted()
        let canUse = p.knowledge.filter { $0.value.level == .canUse }.map(\.key).sorted()
        let learning = p.knowledge.filter { $0.value.level < .understood && $0.value.level > .new }.count
        let due = ReviewPlanner.dueItems(p.knowledge, now: now, limit: .max).count
        let checks = p.knowledge.values.reduce(0) { $0 + $1.comprehension.delayedChecks + $1.production.delayedChecks }
        let good = p.knowledge.values.reduce(0) { $0 + $1.comprehension.delayedCorrect + $1.production.delayedCorrect }
        let retention: Int? = checks == 0 ? nil : Int((Double(good) / Double(checks) * 100).rounded())

        var bySkill: [Skill: SkillScore] = [:]
        for (id, rec) in p.progress.completedActivities {
            guard let a = library.activity(id) else { continue }
            var s = bySkill[a.skill] ?? SkillScore()
            s.total += 1
            if rec.firstTryCorrect { s.correct += 1 }
            bySkill[a.skill] = s
        }

        return ParentReport(
            units: units,
            usage: Usage(minutesLast7Days: mins, activitiesLast7Days: acts, xp: p.rewards.xp),
            mastery: Mastery(understood: understood, canUse: canUse, learning: learning, dueForReview: due,
                             delayedRetentionPercent: retention, bySkill: bySkill),
            latestBaseline: p.assessments.last { $0.kind == .baseline },
            retentionHistory: p.assessments.filter { $0.kind == .retention },
            offlineSuggestions: offlineIdeas(p, library: library))
    }

    /// Screen-free practice ideas tied to what the child is learning.
    static func offlineIdeas(_ p: PlayerProfile, library: ContentLibrary) -> [String] {
        var ideas: [String] = []
        let done = p.progress.completedQuests
        func did(_ unit: String) -> Bool { library.unit(unit)?.quests.contains { done.contains($0.id) } ?? false }
        if did("u1-saludos") { ideas.append("Greet each other in Spanish at breakfast: \"¡Buenos días! ¿Cómo estás?\"") }
        if did("u2-familia") { ideas.append("Look at family photos together and name each person: \"Es mi abuela.\"") }
        if did("u3-mercado") { ideas.append("At the store, let your child ask you \"¿Cuánto cuesta?\" and answer with numbers up to 20.") }
        ideas.append("Count steps, stairs or toys aloud in Spanish (uno, dos, tres…).")
        return ideas
    }
}
