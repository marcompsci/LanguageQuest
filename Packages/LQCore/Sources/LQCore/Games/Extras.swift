import Foundation

/// Progress for side games and exploration. Stored as an optional block on the
/// profile so older saves load unchanged.
public struct ExtrasProgress: Codable, Hashable, Sendable {
    /// Best stars (0–3) per Word Battle opponent id.
    public var battleStars: [String: Int] = [:]
    public var scrambleBestStars = 0
    public var marketBestStars = 0
    public var treasuresFound: Set<String> = []
    /// Added in v0.4: optional so v0.2/v0.3 saves still decode.
    public var kanaBestStars: Int? = nil
    public var flashcardsReviewed: Int? = nil
    /// Added in v0.6: days (yyyy-MM-dd) the bonus lesson's XP was claimed, and words written out.
    public var bonusDays: [String]? = nil
    public var wordsWritten: [String]? = nil
    /// Added in v0.8: starred words, Sentence Builder best stars, best unit-quiz score (%) by unit id.
    public var starredWords: [String]? = nil
    public var builderBestStars: Int? = nil
    public var quizBest: [String: Int]? = nil
    public init() {}
}

extension PlayerProfile {
    public var extrasOrEmpty: ExtrasProgress { extras ?? ExtrasProgress() }

    public mutating func updateExtras(_ change: (inout ExtrasProgress) -> Void) {
        var e = extras ?? ExtrasProgress()
        change(&e)
        extras = e
    }
}

/// Small helpers shared by the side games.
enum GameHelpers {
    /// Items the learner has met (practised at least once), in a stable order.
    static func metItems(_ p: PlayerProfile, _ lib: ContentLibrary) -> [LexItem] {
        lib.allItems.filter { p.knowledge[$0.id] != nil }
    }

    static func seeded(_ seed: UInt64) -> SeededRandom { SeededRandom(seed: seed) }

    /// Removes a leading article (Spanish el/la/los/las, French le/la/les/l'/un/une) and trailing "…".
    static func bareWord(_ s: String) -> (article: String?, word: String) {
        let clean = s.replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
        for a in ["el ", "la ", "los ", "las ", "le ", "les ", "un ", "une "] where clean.lowercased().hasPrefix(a) {
            return (String(clean.prefix(a.count - 1)), String(clean.dropFirst(a.count)))
        }
        for a in ["l'", "l’"] where clean.lowercased().hasPrefix(a) {
            return (String(clean.prefix(2)), String(clean.dropFirst(2)))
        }
        return (nil, clean)
    }

    static func stars(correct: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        let pct = Double(correct) / Double(total)
        return pct >= 1 ? 3 : pct >= 0.7 ? 2 : pct >= 0.4 ? 1 : 0
    }
}
