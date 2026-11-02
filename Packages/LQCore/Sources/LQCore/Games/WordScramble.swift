import Foundation

/// Profe Sol's Word Scramble (Puzzle Academy): unscramble the letters of a
/// Spanish word you've met. Spelling practice that counts as guided production.
public struct ScramblePuzzle: Hashable, Sendable {
    public var itemId: String
    public var english: String
    public var article: String?
    /// The word to build (accents included).
    public var answer: String
    /// Letter tiles in scrambled order (never the answer's own order).
    public var letters: [Character]
}

public struct WordScramble: Sendable {
    public static let rounds = 6
    public static let minLetters = 3
    public static let maxLetters = 9

    public let puzzles: [ScramblePuzzle]
    let context: CheckContext
    public private(set) var index = 0
    public private(set) var firstTryCorrect = 0
    public private(set) var attemptsThisRound = 0

    public init(library: ContentLibrary, profile: PlayerProfile, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        context = library.checkContext
        let v = profile.variant
        let candidates = library.allItems.filter { $0.kind == .word }.compactMap { item -> (LexItem, String?, String)? in
            let (article, word) = GameHelpers.bareWord(item.target.text(for: v))
            let letters = word.filter { $0.isLetter }
            guard letters.count == word.count, (Self.minLetters...Self.maxLetters).contains(word.count) else { return nil }
            return (item, article, word)
        }
        let met = candidates.filter { profile.knowledge[$0.0.id] != nil }.shuffled(using: &rng)
        let rest = candidates.filter { profile.knowledge[$0.0.id] == nil }.shuffled(using: &rng)
        var seen = Set<String>()
        var out: [ScramblePuzzle] = []
        for (item, article, word) in met + rest where out.count < Self.rounds && seen.insert(word.lowercased()).inserted {
            out.append(ScramblePuzzle(itemId: item.id, english: item.english, article: article, answer: word,
                                      letters: Self.scramble(word, rng: &rng)))
        }
        puzzles = out
    }

    /// Shuffles until the order differs from the word (words with all-equal letters can't differ).
    static func scramble(_ word: String, rng: inout SeededRandom) -> [Character] {
        let chars = Array(word.lowercased())
        guard Set(chars).count > 1 else { return chars }
        var s = chars
        repeat { s.shuffle(using: &rng) } while s == chars
        return s
    }

    public var finished: Bool { index >= puzzles.count }
    public var current: ScramblePuzzle? { finished ? nil : puzzles[index] }
    public var stars: Int { GameHelpers.stars(correct: firstTryCorrect, of: puzzles.count) }

    /// Checks an attempt (accent-insensitive: the accent is shown in feedback).
    public mutating func submit(_ attempt: String) -> Bool {
        guard let p = current else { return false }
        attemptsThisRound += 1
        let ok = AnswerChecker.equivalent(attempt, p.answer, context: context)
        if ok {
            if attemptsThisRound == 1 { firstTryCorrect += 1 }
            index += 1
            attemptsThisRound = 0
        }
        return ok
    }

    /// Give up on this word (shows the answer, moves on, no penalty).
    public mutating func skip() {
        guard !finished else { return }
        index += 1
        attemptsThisRound = 0
    }
}
