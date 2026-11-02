import Foundation

/// Kana Dojo: read hiragana or katakana and pick the romaji (or the reverse).
public enum KanaScript: String, CaseIterable, Sendable { case hiragana, katakana }

public struct KanaQuestion: Hashable, Sendable {
    public var kana: String
    public var romaji: String
    /// true: show kana, pick romaji. false: show romaji, pick kana.
    public var readKana: Bool
    public var options: [String]
    public var answerIndex: Int
}

public struct KanaDojo: Sendable {
    public static let rounds = 10
    /// The 46 basic hiragana in gojūon order.
    public static let hiragana: [String] = [
        "あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "さ", "し", "す", "せ", "そ",
        "た", "ち", "つ", "て", "と", "な", "に", "ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ",
        "ま", "み", "む", "め", "も", "や", "ゆ", "よ", "ら", "り", "る", "れ", "ろ", "わ", "を", "ん",
    ]

    public static func characters(_ s: KanaScript) -> [String] {
        switch s {
        case .hiragana: return hiragana
        case .katakana:
            return hiragana.map { h in
                String(String.UnicodeScalarView(h.unicodeScalars.map { Unicode.Scalar($0.value + 0x60) ?? $0 }))
            }
        }
    }

    /// Romaji for a single kana, with を read as "o" (wo).
    public static func romaji(_ k: String) -> String { Kana.word(k) }

    public let script: KanaScript
    public let questions: [KanaQuestion]
    public private(set) var index = 0
    public private(set) var correct = 0

    public init(script: KanaScript, seed: UInt64) {
        self.script = script
        var rng = SeededRandom(seed: seed)
        let pool = Self.characters(script).filter { $0 != "を" }   // を duplicates お's sound
        let picks = Array(pool.shuffled(using: &rng).prefix(Self.rounds))
        questions = picks.enumerated().map { i, k in
            let readKana = i % 3 != 2
            var seen: Set<String> = [Self.romaji(k)]
            let others = pool.shuffled(using: &rng).filter { seen.insert(Self.romaji($0)).inserted }.prefix(3)
            var opts = ([k] + others).map { readKana ? Self.romaji($0) : $0 }
            let right = opts[0]
            opts.shuffle(using: &rng)
            return KanaQuestion(kana: k, romaji: Self.romaji(k), readKana: readKana, options: opts, answerIndex: opts.firstIndex(of: right) ?? 0)
        }
    }

    public var finished: Bool { index >= questions.count }
    public var current: KanaQuestion? { finished ? nil : questions[index] }
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

/// Flashcards: a quick flip-card pass over words the learner has met, due ones first.
public struct Flashcard: Hashable, Sendable {
    public var itemId: String
    public var front: VText
    public var back: String
    public var picture: String?
}

public enum FlashcardDeck {
    public static let size = 12

    public static func build(_ p: PlayerProfile, library: ContentLibrary, now: Date, seed: UInt64) -> [Flashcard] {
        var rng = SeededRandom(seed: seed)
        let due = ReviewPlanner.dueItems(p.knowledge, now: now, limit: size)
        let met = p.knowledge.keys.sorted().filter { !due.contains($0) }.shuffled(using: &rng)
        var ids = due + met
        if ids.count < size {
            // Top up with words from the first unit not met yet, so new learners have a deck too.
            let fresh = (library.units.first?.allItems ?? []).map(\.id).filter { !ids.contains($0) }
            ids += fresh
        }
        return ids.prefix(size).compactMap { id in
            library.item(id).map { Flashcard(itemId: id, front: $0.target, back: $0.english, picture: $0.picture) }
        }
    }

    /// "I knew it" counts as a correct comprehension review; "still learning" as a miss
    /// (the word simply comes back sooner).
    public static func record(_ card: Flashcard, knewIt: Bool, profile: inout PlayerProfile, now: Date) {
        PracticeRecorder.record(itemId: card.itemId, outcome: ReviewOutcome(correct: knewIt), track: .comprehension, profile: &profile, now: now)
        profile.updateExtras { $0.flashcardsReviewed = ($0.flashcardsReviewed ?? 0) + 1 }
    }
}
