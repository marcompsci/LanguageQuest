import Foundation

/// Hiragana/katakana → Hepburn romaji, for display under Japanese text and for
/// accepting romaji answers. Lessons write Japanese with spaces between words
/// (as beginner books do), so the particles は, を and へ can be read as wa, o, e.
public enum Kana {
    static let base: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "o", "ん": "n", "ゔ": "vu",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
    ]
    static let smallY: [Character: String] = ["ゃ": "a", "ゅ": "u", "ょ": "o"]
    static let particles: [String: String] = ["は": "wa", "を": "o", "へ": "e"]

    /// Katakana → hiragana (same sounds), leaving other characters alone.
    static func toHiragana(_ c: Character) -> Character {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return c }
        if (0x30A1...0x30F6).contains(s.value), let h = Unicode.Scalar(s.value - 0x60) { return Character(h) }
        return c
    }

    public static func isKana(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first else { return false }
        return (0x3041...0x309F).contains(s.value) || (0x30A0...0x30FF).contains(s.value)
    }

    public static func containsKana(_ s: String) -> Bool { s.contains(where: isKana) }

    /// Romaji for one word (no spaces).
    public static func word(_ w: String) -> String {
        let chars = Array(w).map(toHiragana)
        var out = ""
        var i = 0
        var doubleNext = false
        while i < chars.count {
            let c = chars[i]
            if c == "っ" { doubleNext = true; i += 1; continue }
            if c == "ー" {
                if let v = out.last, "aeiou".contains(v) { out.append(v) }
                i += 1; continue
            }
            guard var syl = base[c] else { out.append(c); i += 1; continue }
            // Digraphs: き + ゃ → kya, し + ゃ → sha, ち + ゃ → cha, じ + ゃ → ja.
            if i + 1 < chars.count, let v = smallY[chars[i + 1]], syl.hasSuffix("i"), syl.count >= 2 {
                let stem = String(syl.dropLast())
                syl = ["sh", "ch", "j"].contains(stem) ? stem + v : stem + "y" + v
                i += 1
            }
            if doubleNext {
                syl = (syl.hasPrefix("ch") ? "t" : String(syl.prefix(1))) + syl
                doubleNext = false
            }
            out += syl
            i += 1
        }
        return out
    }

    /// Romaji for a phrase. Spaces separate words; standalone は/を/へ are particles.
    public static func romanize(_ s: String, overrides: [String: String] = [:]) -> String {
        if let whole = overrides[s.trimmingCharacters(in: .whitespaces)] { return whole }
        return s.split(separator: " ", omittingEmptySubsequences: true).map { tok -> String in
            var t = String(tok)
            // Keep punctuation attached to the word but out of the lookup.
            let trailing = String(t.reversed().prefix { "。、？！?!,.…「」".contains($0) }.reversed())
            t = String(t.dropLast(trailing.count))
            let leading = String(t.prefix { "「".contains($0) })
            t = String(t.dropFirst(leading.count))
            let body = overrides[t] ?? particles[t] ?? word(t)
            let p = trailing.map { ch -> String in
                switch ch { case "。": return "."; case "、": return ","; case "？": return "?"; case "！": return "!"; case "「", "」": return ""; default: return String(ch) }
            }.joined()
            return body + p
        }.joined(separator: " ")
    }

    /// A forgiving comparison key for typed answers: romaji, letters only,
    /// long vowels collapsed (arigatou = arigato = arigatō, oneesan = onesan).
    public static func matchKey(_ s: String, overrides: [String: String] = [:]) -> String {
        let roman = containsKana(s) ? romanize(s, overrides: overrides) : s
        var t = roman.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        t = t.filter { $0.isLetter }
        var out = ""
        for ch in t {
            if let last = out.last, "aeiou".contains(ch) {
                if last == ch { continue }                  // aa, ii, uu, ee, oo
                if last == "o" && ch == "u" { continue }    // ou → o
                if last == "e" && ch == "i" { continue }    // ei → e
            }
            out.append(ch)
        }
        return out
    }
}
