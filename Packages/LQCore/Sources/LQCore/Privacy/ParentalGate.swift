import Foundation

/// A small deterministic random generator so gates and tests are reproducible.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// An adult check before purchases, external links, and parent settings.
///
/// The question is written in words ("forty-seven plus thirty-eight") and must be
/// answered in digits, which young children can't easily read or solve. Teens can
/// solve it, so the parent area also supports an optional parent PIN (App layer,
/// stored in the Keychain) and purchases additionally go through Apple's own
/// confirmation and Ask to Buy.
public struct GateChallenge: Equatable, Sendable {
    public var question: String
    public var spoken: String
    public var answer: Int
}

public enum ParentalGate {
    static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                       "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                       "seventeen", "eighteen", "nineteen"]
    static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    public static func words(_ n: Int) -> String {
        precondition((0...99).contains(n))
        if n < 20 { return ones[n] }
        let t = tens[n / 10]
        return n % 10 == 0 ? t : "\(t)-\(ones[n % 10])"
    }

    public static func makeChallenge<R: RandomNumberGenerator>(using rng: inout R) -> GateChallenge {
        let kind = Int.random(in: 0..<2, using: &rng)
        if kind == 0 {
            let a = Int.random(in: 21...59, using: &rng)
            let b = Int.random(in: 21...39, using: &rng)
            let q = "\(words(a).capitalizedFirst) plus \(words(b))"
            return GateChallenge(question: q, spoken: q, answer: a + b)
        } else {
            let a = Int.random(in: 6...9, using: &rng)
            let b = Int.random(in: 6...9, using: &rng)
            let q = "\(words(a).capitalizedFirst) times \(words(b))"
            return GateChallenge(question: q, spoken: q, answer: a * b)
        }
    }

    public static func makeChallenge() -> GateChallenge {
        var g = SystemRandomNumberGenerator()
        return makeChallenge(using: &g)
    }
}

/// Tracks failed attempts. After `maxFailures` wrong answers the gate locks for `lockSeconds`.
public struct GateAttemptTracker: Codable, Hashable, Sendable {
    public static let maxFailures = 3
    public static let lockSeconds: Double = 60

    public var failures = 0
    public var lockedUntil: Date? = nil
    public init() {}

    public func isLocked(now: Date) -> Bool { (lockedUntil ?? .distantPast) > now }

    /// Returns true if the answer opened the gate.
    public mutating func submit(_ input: String, for c: GateChallenge, now: Date) -> Bool {
        if isLocked(now: now) { return false }
        let digits = input.trimmingCharacters(in: .whitespaces)
        if let n = Int(digits), n == c.answer {
            failures = 0
            lockedUntil = nil
            return true
        }
        failures += 1
        if failures >= Self.maxFailures {
            lockedUntil = now.addingTimeInterval(Self.lockSeconds)
            failures = 0
        }
        return false
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
