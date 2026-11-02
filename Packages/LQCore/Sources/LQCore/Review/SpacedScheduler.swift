import Foundation

/// What happened on one practice of one item.
public struct ReviewOutcome: Codable, Hashable, Sendable {
    public var correct: Bool
    /// 1 = right on the first try.
    public var attempts: Int
    public var responseSeconds: Double
    public var usedHint: Bool

    public init(correct: Bool, attempts: Int = 1, responseSeconds: Double = 4, usedHint: Bool = false) {
        self.correct = correct
        self.attempts = max(1, attempts)
        self.responseSeconds = max(0, responseSeconds)
        self.usedHint = usedHint
    }
}

/// Spaced-review memory for one item on one track (comprehension or production).
/// A small SM-2 variant that also uses response time, attempts, hints, and the
/// real time since the last review.
public struct MemoryState: Codable, Hashable, Sendable {
    public var ease: Double = 2.5
    public var intervalDays: Double = 0
    public var reps: Int = 0
    public var lapses: Int = 0
    public var due: Date
    public var lastReviewed: Date?
    public var reviewCount: Int = 0
    public var correctCount: Int = 0
    /// Reviews that happened at least `delayedThresholdDays` after the previous one.
    public var delayedChecks: Int = 0
    public var delayedCorrect: Int = 0
    public var averageResponseSeconds: Double = 0

    public init(due: Date) { self.due = due }

    public var accuracy: Double { reviewCount == 0 ? 0 : Double(correctCount) / Double(reviewCount) }
    public var delayedRetention: Double? { delayedChecks == 0 ? nil : Double(delayedCorrect) / Double(delayedChecks) }
}

public enum SpacedScheduler {
    public static let day: TimeInterval = 86_400
    public static let relearnDelay: TimeInterval = 10 * 60
    public static let delayedThresholdDays: Double = 1
    public static let slowResponseSeconds: Double = 10
    public static let minEase = 1.3
    public static let maxEase = 3.0
    public static let maxIntervalDays: Double = 180

    /// 0–5 quality grade.
    public static func grade(_ o: ReviewOutcome) -> Int {
        if !o.correct { return 1 }
        if o.attempts > 2 { return 3 }
        if o.attempts == 2 || o.usedHint { return 3 }
        if o.responseSeconds > slowResponseSeconds { return 4 }
        return 5
    }

    public static func update(_ s: MemoryState, with o: ReviewOutcome, now: Date) -> MemoryState {
        var m = s
        let g = grade(o)
        let elapsedDays = s.lastReviewed.map { max(0, now.timeIntervalSince($0) / day) } ?? 0
        let delayed = s.lastReviewed != nil && elapsedDays >= delayedThresholdDays

        m.reviewCount += 1
        if o.correct { m.correctCount += 1 }
        m.averageResponseSeconds = s.reviewCount == 0
            ? o.responseSeconds
            : (s.averageResponseSeconds * Double(s.reviewCount) + o.responseSeconds) / Double(m.reviewCount)
        if delayed {
            m.delayedChecks += 1
            if o.correct && o.attempts == 1 && !o.usedHint { m.delayedCorrect += 1 }
        }

        if g < 3 {
            m.reps = 0
            m.lapses += 1
            m.intervalDays = 0
            m.ease = max(minEase, s.ease - 0.2)
            m.due = now.addingTimeInterval(relearnDelay)
        } else {
            m.reps += 1
            let q = Double(5 - g)
            m.ease = min(maxEase, max(minEase, s.ease + 0.1 - q * (0.08 + q * 0.02)))
            switch m.reps {
            case 1: m.intervalDays = 1
            case 2: m.intervalDays = 3
            default:
                // Credit real elapsed time: remembering after a longer gap is stronger evidence.
                let basis = max(s.intervalDays, min(elapsedDays, s.intervalDays * 2))
                m.intervalDays = min(maxIntervalDays, (basis * m.ease).rounded())
            }
            // A correct but effortful answer doesn't jump as far.
            if g == 3 { m.intervalDays = max(1, (m.intervalDays * 0.6).rounded()) }
            m.due = now.addingTimeInterval(m.intervalDays * day)
        }
        m.lastReviewed = now
        return m
    }
}

// MARK: - Learner model

/// Which memory track an activity exercises.
public enum PracticeTrack: String, Codable, Sendable {
    /// Recognising meaning: listen/read/match/fill-blank/replies.
    case comprehension
    /// Producing with scaffolds (word tiles).
    case guidedProduction
    /// Producing from memory: typing with no word bank, speaking without a model shown.
    case spontaneousProduction

    public static func of(_ a: Activity) -> PracticeTrack {
        switch a.type {
        case .listenChoose, .readChoose, .match, .fillBlank, .dialogueReply: return .comprehension
        case .buildSentence: return .guidedProduction
        case .typeAnswer, .speak: return a.practice == .independent ? .spontaneousProduction : .guidedProduction
        }
    }
}

public enum MasteryLevel: Int, Codable, Comparable, CaseIterable, Sendable {
    case new = 0, learning, familiar, understood, canUse

    public static func < (a: MasteryLevel, b: MasteryLevel) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .new: return "New"
        case .learning: return "Learning"
        case .familiar: return "Familiar"
        case .understood: return "Understands"
        case .canUse: return "Can use"
        }
    }
}

/// Comprehension and production are tracked and reported separately.
public struct ItemKnowledge: Codable, Hashable, Sendable {
    public var comprehension: MemoryState
    public var production: MemoryState
    public var spontaneousCorrect: Int = 0
    public var spontaneousDelayedCorrect: Int = 0

    public init(now: Date) {
        comprehension = MemoryState(due: now)
        production = MemoryState(due: now)
    }

    public mutating func record(_ o: ReviewOutcome, track: PracticeTrack, now: Date) {
        switch track {
        case .comprehension:
            comprehension = SpacedScheduler.update(comprehension, with: o, now: now)
        case .guidedProduction:
            production = SpacedScheduler.update(production, with: o, now: now)
        case .spontaneousProduction:
            let wasDelayed = production.lastReviewed.map { now.timeIntervalSince($0) >= SpacedScheduler.day } ?? false
            production = SpacedScheduler.update(production, with: o, now: now)
            if o.correct && o.attempts == 1 && !o.usedHint {
                spontaneousCorrect += 1
                if wasDelayed { spontaneousDelayedCorrect += 1 }
            }
        }
    }

    /// Mastery is earned only through spaced, delayed evidence: never XP.
    public var comprehensionMastered: Bool {
        comprehension.intervalDays >= 7 && comprehension.delayedCorrect >= 1
    }

    public var productionMastered: Bool {
        spontaneousCorrect >= 2 && spontaneousDelayedCorrect >= 1
    }

    public var level: MasteryLevel {
        if comprehensionMastered && productionMastered { return .canUse }
        if comprehensionMastered { return .understood }
        if comprehension.reps >= 2 || production.reps >= 2 { return .familiar }
        if comprehension.reviewCount + production.reviewCount > 0 { return .learning }
        return .new
    }

    /// Earliest due date among tracks that have actually been practised.
    /// (A track never practised isn't "due": production comes later in the course.)
    public var nextDue: Date {
        let practised = [comprehension, production].filter { $0.lastReviewed != nil }
        return practised.map(\.due).min() ?? comprehension.due
    }
}

/// Builds review sessions from the learner model.
public enum ReviewPlanner {
    /// Items due now, most overdue first (relative to their interval).
    public static func dueItems(_ knowledge: [String: ItemKnowledge], now: Date, limit: Int = 12) -> [String] {
        let due = knowledge.filter { $0.value.nextDue <= now }
        return due.sorted { a, b in
            overdueRatio(a.value, now) > overdueRatio(b.value, now) || (overdueRatio(a.value, now) == overdueRatio(b.value, now) && a.key < b.key)
        }.prefix(limit).map(\.key)
    }

    static func overdueRatio(_ k: ItemKnowledge, _ now: Date) -> Double {
        let overdue = now.timeIntervalSince(k.nextDue) / SpacedScheduler.day
        let interval = max(1, min(k.comprehension.intervalDays, k.production.intervalDays))
        return overdue / interval
    }

    /// Items eligible for a periodic retention check: practised before, and not
    /// seen for at least `minDaysUnseen` days. Deterministic order.
    public static func retentionCandidates(_ knowledge: [String: ItemKnowledge], now: Date, minDaysUnseen: Double = 7, limit: Int = 8) -> [String] {
        knowledge.compactMap { (id, k) -> (String, Double)? in
            let last = [k.comprehension.lastReviewed, k.production.lastReviewed].compactMap { $0 }.max()
            guard let l = last, k.comprehension.reviewCount >= 2 else { return nil }
            let unseen = now.timeIntervalSince(l) / SpacedScheduler.day
            return unseen >= minDaysUnseen ? (id, unseen) : nil
        }
        .sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        .prefix(limit).map(\.0)
    }
}
