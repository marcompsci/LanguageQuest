import Foundation

/// The result of checking a typed, spoken, or built answer.
/// Nothing here punishes: every non-correct result carries a gentle note.
public enum AnswerVerdict: Equatable, Sendable {
    /// Exactly right for the learner's variant.
    case correct
    /// Right, but missing accents or ñ. Counts as correct; shows a note.
    case correctMissingAccents(expected: String)
    /// A correct form from another region (e.g. "zumo" while learning Mexican Spanish).
    case correctOtherRegion(expected: String, variant: String)
    /// One small typo away. Not counted as correct; learner may retry.
    case almost(expected: String)
    case incorrect(expected: String)

    public var isCorrect: Bool {
        switch self {
        case .correct, .correctMissingAccents, .correctOtherRegion: return true
        case .almost, .incorrect: return false
        }
    }
}

public enum AnswerChecker {
    /// Lowercases, trims, removes punctuation (including ¿ ¡), and collapses spaces.
    public static func normalize(_ s: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        let scalars = s.lowercased().unicodeScalars.map { punctuation.contains($0) ? " " : Character($0) }
        return String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Also removes accents and turns ñ into n.
    public static func fold(_ s: String) -> String {
        normalize(s).folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es"))
    }

    /// Checks a free answer against accepted answers for a variant.
    /// - Parameters:
    ///   - accepted: every acceptable answer (each may have regional forms).
    ///   - variant: the learner's chosen variant id.
    ///   - allowTypos: speech results and young learners get one-letter leeway as "almost".
    public static func check(_ input: String, accepted: [VText], variant: String, allowTypos: Bool = true) -> AnswerVerdict {
        let given = normalize(input)
        let preferred = accepted.map { $0.text(for: variant) }
        let expected = preferred.first ?? ""
        guard !given.isEmpty else { return .incorrect(expected: expected) }

        // 1. Exact for this variant.
        if preferred.contains(where: { normalize($0) == given }) { return .correct }

        // 2. Exact for another variant.
        for a in accepted {
            for v in a.regionalVariants where v != variant {
                if let form = a.overrides[v], normalize(form) == given {
                    return .correctOtherRegion(expected: a.text(for: variant), variant: v)
                }
            }
            if variant != "es-419", a.overrides[variant] != nil, normalize(a.base) == given {
                return .correctOtherRegion(expected: a.text(for: variant), variant: "es-419")
            }
        }

        // 3. Right letters, missing accents/ñ.
        let foldedGiven = fold(input)
        if let match = preferred.first(where: { fold($0) == foldedGiven }) { return .correctMissingAccents(expected: match) }
        for a in accepted { for f in a.allForms where fold(f) == foldedGiven { return .correctMissingAccents(expected: a.text(for: variant)) } }

        // 4. One small typo (only for answers long enough that a typo can't flip meaning).
        if allowTypos {
            for f in preferred where fold(f).count >= 5 && editDistance(fold(f), foldedGiven) == 1 {
                return .almost(expected: f)
            }
        }
        return .incorrect(expected: expected)
    }

    /// Checks a built sentence (tile order) against the correct order.
    public static func checkTiles(_ chosen: [String], correct: [VText], variant: String) -> AnswerVerdict {
        let want = correct.map { $0.text(for: variant) }
        let expected = want.joined(separator: " ")
        if chosen.map(normalize) == want.map(normalize) { return .correct }
        if chosen.count == want.count, Set(chosen.map(normalize)) == Set(want.map(normalize)) {
            return .almost(expected: expected)
        }
        return .incorrect(expected: expected)
    }

    /// Levenshtein distance (small strings only).
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }

    /// Kid-friendly feedback line for a verdict. Variant names come from the course.
    public static func feedback(for verdict: AnswerVerdict, variantName: (String) -> String) -> String {
        switch verdict {
        case .correct: return "¡Muy bien! That's right."
        case .correctMissingAccents(let e): return "Right! Watch the accents: \(e)"
        case .correctOtherRegion(let e, let v): return "That's right in \(variantName(v))! Here we say: \(e)"
        case .almost(let e): return "So close! Check the spelling: \(e)"
        case .incorrect(let e): return "Not quite. It's: \(e). Let's try again later."
        }
    }
}
