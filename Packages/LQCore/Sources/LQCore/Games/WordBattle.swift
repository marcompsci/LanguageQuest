import Foundation

/// A friendly "Duelo de palabras". The player charges a spark meter by answering;
/// the rival charges theirs on a fixed pattern. Mistakes cost nothing except the
/// spark you'd have gained, and every mistake gets a coaching tip. No health,
/// no game over, no timers.
public struct BattleOpponent: Hashable, Identifiable, Sendable {
    public var id: String
    public var npc: String
    public var name: String
    public var title: String
    /// Unit whose words the battle uses (nil = every unit). Unlocks when that unit is finished.
    public var unitOrder: Int?
    public var greeting: VText
    public var greetingGloss: String
}

public enum BattleRoster {
    public static let opponents: [BattleOpponent] = [
        BattleOpponent(id: "duel-mateo", npc: "mateo", name: "Mateo", title: "Greetings duel", unitOrder: 1,
                       greeting: "¡Te reto a un duelo de palabras!", greetingGloss: "I challenge you to a word duel!"),
        BattleOpponent(id: "duel-nico", npc: "nico", name: "Nico", title: "Family & pets duel", unitOrder: 2,
                       greeting: "¡Canela y yo estamos listos!", greetingGloss: "Canela and I are ready!"),
        BattleOpponent(id: "duel-pepe", npc: "don-pepe", name: "Don Pepe", title: "Market duel", unitOrder: 3,
                       greeting: "¿Sabes los nombres de mi fruta?", greetingGloss: "Do you know the names of my fruit?"),
        BattleOpponent(id: "duel-sol", npc: "profe-sol", name: "Profe Sol", title: "Grand duel (all units)", unitOrder: nil,
                       greeting: "Veamos todo lo que aprendiste.", greetingGloss: "Let's see everything you've learned."),
    ]

    public static func opponent(forNPC npc: String) -> BattleOpponent? { opponents.first { $0.npc == npc } }

    public static func isUnlocked(_ o: BattleOpponent, progress: CourseProgress, progression: Progression) -> Bool {
        let units = progression.library.units
        if let n = o.unitOrder {
            guard let u = units.first(where: { $0.order == n }) else { return false }
            return progression.isUnitFinished(u, progress)
        }
        return units.allSatisfy { progression.isUnitFinished($0, progress) }
    }
}

public struct BattleQuestion: Hashable, Sendable {
    public var itemId: String
    /// True: prompt is Spanish and options are English. False: the reverse.
    public var spanishPrompt: Bool
    public var prompt: VText
    public var options: [VText]
    public var answerIndex: Int
}

public struct BattleTurn: Equatable, Sendable {
    public var correct: Bool
    public var playerGain: Int
    public var rivalGain: Int
    /// Always present: what the right answer was and what it means.
    public var coachTip: String
}

public struct WordBattle: Sendable {
    public static let rounds = 6
    public static let rivalPattern = [15, 20, 15, 20, 15, 20]
    public static let baseGain = 20
    public static let comboBonus = 5
    public static let maxComboBonus = 10

    public let opponent: BattleOpponent
    public let questions: [BattleQuestion]
    public private(set) var round = 0
    public private(set) var playerSpark = 0
    public private(set) var rivalSpark = 0
    public private(set) var combo = 0
    public private(set) var correctCount = 0

    /// Builds questions from the opponent's unit, preferring words the player has met.
    public init(opponent: BattleOpponent, library: ContentLibrary, profile: PlayerProfile, seed: UInt64) {
        self.opponent = opponent
        let picked = library.units.filter { opponent.unitOrder == nil || $0.order == opponent.unitOrder }
        let units = picked.isEmpty ? library.units : picked   // starter courses have one unit
        let pool = units.flatMap(\.allItems)
        var rng = SeededRandom(seed: seed)
        let met = pool.filter { profile.knowledge[$0.id] != nil }.shuffled(using: &rng)
        let unmet = pool.filter { profile.knowledge[$0.id] == nil }.shuffled(using: &rng)
        let picks = Array((met + unmet).prefix(Self.rounds))
        let variant = profile.variant
        var qs: [BattleQuestion] = []
        for (i, item) in picks.enumerated() {
            let spanishPrompt = i % 2 == 0
            let others = pool.filter { $0.id != item.id && $0.english != item.english && $0.kind == item.kind
                && $0.target.text(for: variant) != item.target.text(for: variant) }.shuffled(using: &rng)
            var distractors: [LexItem] = []
            for o in others where distractors.count < 3 {
                let clash = distractors.contains { $0.english == o.english || $0.target.text(for: variant) == o.target.text(for: variant) }
                if !clash { distractors.append(o) }
            }
            var opts = ([item] + distractors).map { spanishPrompt ? VText($0.english) : $0.target }
            let answerText = opts[0]
            opts.shuffle(using: &rng)
            let answer = opts.firstIndex(of: answerText) ?? 0
            qs.append(BattleQuestion(itemId: item.id, spanishPrompt: spanishPrompt,
                                     prompt: spanishPrompt ? item.target : VText(item.english),
                                     options: opts, answerIndex: answer))
        }
        questions = qs
    }

    public var finished: Bool { round >= questions.count }
    public var current: BattleQuestion? { finished ? nil : questions[round] }
    public var playerWon: Bool { finished && playerSpark >= rivalSpark }
    public var stars: Int { GameHelpers.stars(correct: correctCount, of: questions.count) }

    @discardableResult
    public mutating func answer(_ index: Int, library: ContentLibrary, variant: String) -> BattleTurn? {
        guard let q = current else { return nil }
        let correct = index == q.answerIndex
        var gain = 0
        if correct {
            gain = Self.baseGain + min(combo * Self.comboBonus, Self.maxComboBonus)
            combo += 1
            correctCount += 1
        } else {
            combo = 0
        }
        let rival = Self.rivalPattern[round % Self.rivalPattern.count]
        playerSpark += gain
        rivalSpark += rival
        round += 1
        let item = library.item(q.itemId)
        let tip = item.map { "\($0.target.text(for: variant)) = \($0.english)" } ?? ""
        return BattleTurn(correct: correct, playerGain: gain, rivalGain: rival, coachTip: tip)
    }
}

/// Records practice from side games straight into the learner model.
public enum PracticeRecorder {
    public static func record(itemId: String, outcome: ReviewOutcome, track: PracticeTrack, profile: inout PlayerProfile, now: Date) {
        var k = profile.knowledge[itemId] ?? ItemKnowledge(now: now)
        k.record(outcome, track: track, now: now)
        profile.knowledge[itemId] = k
        profile.log.activitiesByDay[ActivityLog.dayKey(now), default: 0] += 1
    }
}
