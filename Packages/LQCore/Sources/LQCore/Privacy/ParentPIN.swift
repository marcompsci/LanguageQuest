import Foundation

/// Optional parent PIN. The written-out math gate stops younger siblings but not
/// teens, so for an 11+ audience a parent can set a PIN. Only a salted SHA-256
/// hash is stored (the app keeps it in the Keychain).
public struct ParentPINRecord: Codable, Hashable, Sendable {
    public var salt: String
    public var hash: String
}

public enum ParentPIN {
    public static let lengths = 4...6

    public enum Problem: Error, Equatable { case notDigits, wrongLength, tooSimple, mismatch }

    /// Rejects non-digits, bad lengths, and trivially guessable PINs (1111, 1234, 4321…).
    public static func validateNew(_ pin: String, confirm: String) -> Problem? {
        guard pin.allSatisfy(\.isASCIIDigit) else { return .notDigits }
        guard lengths.contains(pin.count) else { return .wrongLength }
        let d = pin.compactMap(\.wholeNumberValue)
        let allSame = Set(d).count == 1
        let ascending = zip(d, d.dropFirst()).allSatisfy { $1 == $0 + 1 }
        let descending = zip(d, d.dropFirst()).allSatisfy { $1 == $0 - 1 }
        if allSame || ascending || descending { return .tooSimple }
        guard pin == confirm else { return .mismatch }
        return nil
    }

    public static func makeRecord(pin: String, salt: String) -> ParentPINRecord {
        ParentPINRecord(salt: salt, hash: SHA256.hex(Array((salt + ":" + pin).utf8)))
    }

    public static func verify(_ pin: String, against r: ParentPINRecord) -> Bool {
        constantTimeEqual(SHA256.hex(Array((r.salt + ":" + pin).utf8)), r.hash)
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

/// Lockout for PIN attempts (same policy as the math gate).
extension GateAttemptTracker {
    public mutating func submitPIN(_ pin: String, record: ParentPINRecord, now: Date) -> Bool {
        if isLocked(now: now) { return false }
        if ParentPIN.verify(pin, against: record) {
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

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// Minimal SHA-256 (FIPS 180-4) so the core has no platform crypto dependency.
public enum SHA256 {
    static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    public static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var m = message
        let bitLen = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        for i in (0..<8).reversed() { m.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xff)) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for chunk in stride(from: 0, to: m.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(m[j]) << 24 | UInt32(m[j + 1]) << 16 | UInt32(m[j + 2]) << 8 | UInt32(m[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.flatMap { v in (0..<4).reversed().map { UInt8((v >> (UInt32($0) * 8)) & 0xff) } }
    }

    public static func hex(_ message: [UInt8]) -> String {
        hash(message).map { String(format: "%02x", $0) }.joined()
    }
}
