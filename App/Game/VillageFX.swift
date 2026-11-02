import SpriteKit
import UIKit
import LQCore

// v0.6 art pass for an 11+ audience: richer tiles with variation, soft light, and
// weather-like particles. Everything is still drawn in code (no third-party art).

extension PixelArt {
    /// Higher-detail tiles with a few variants each so the ground doesn't repeat.
    static func richTile(_ t: Tile, frame: Int = 0, variant: Int = 0) -> SKTexture {
        var c = Canvas(16, 16)
        let v = variant % 3
        func grass() {
            let base: [UInt32] = [0x6FBF5E, 0x74C463, 0x6AB95A]
            c.fill(base[v])
            for y in 0..<16 { for x in 0..<16 {
                let n = noise(x, y, 11 + v)
                if n < 36 { c.set(x, y, 0x58A64C) } else if n > 236 { c.set(x, y, 0x8FD67A) }
            } }
            // A few blades of grass.
            for (x, y) in [(2, 5), (9, 2), (13, 9), (5, 12), (11, 14)] where noise(x, y, 40 + v) < 180 {
                c.set(x, y, 0x4A9440); c.set(x, y - 1, 0x4A9440); c.set(x + 1, y - 2, 0x9EE087)
            }
        }
        switch t {
        case .grass:
            grass()
        case .flowers:
            grass()
            let petals: [UInt32] = [0xF07AA0, 0xFFFFFF, 0xB18CF2, 0xF2D04A]
            for (i, (x, y)) in [(3, 4), (11, 3), (6, 11), (13, 12), (8, 7)].enumerated() {
                let col = petals[(i + v) % petals.count]
                c.set(x, y - 1, col); c.set(x - 1, y, col); c.set(x + 1, y, col); c.set(x, y + 1, col)
                c.set(x, y, 0xF2B530); c.set(x, y + 2, 0x3E8E4E)
            }
        case .path:
            c.fill(0xE0C08A)
            for y in 0..<16 { for x in 0..<16 {
                let n = noise(x, y, 21 + v)
                if n < 30 { c.set(x, y, 0xC69F62) } else if n > 240 { c.set(x, y, 0xF2DCAA) }
            } }
            for (x, y) in [(3, 3), (12, 6), (6, 13)] where noise(x, y, 50 + v) < 150 {
                c.rect(x, y, 2, 1, 0xA9A39A); c.set(x, y + 1, 0x7F7A72); c.set(x + 1, y + 1, 0x8C877F)
            }
        case .sand:
            c.fill(0xF1DFA6)
            for y in 0..<16 { for x in 0..<16 {
                let n = noise(x, y, 31 + v)
                if n < 26 { c.set(x, y, 0xDCC283) } else if n > 243 { c.set(x, y, 0xFFF3CC) }
            } }
        case .water:
            // Deeper toward the middle, with moving glints.
            for y in 0..<16 { for x in 0..<16 { c.set(x, y, (y > 4 && y < 12) ? 0x3E8FD0 : 0x4FA3E0) } }
            let f = frame % 3
            for y in stride(from: 2 + f, to: 16, by: 5) {
                for x in 0..<16 where (x + y * 3 + f * 4) % 9 < 2 { c.set(x, y, 0xB6E2FA) }
            }
            for x in 0..<16 where (x + f * 5) % 7 == 0 { c.set(x, (x + f) % 16, 0xFFFFFF) }
        case .tree:
            grass()
            c.draw(["..oooooooo..", ".o........o.", "oo........oo"], ["o": 0x3E6E36], dx: 2, dy: 13)   // ground shadow
            c.rect(7, 10, 2, 6, 0x6B4423); c.set(7, 10, 0x8A5A32); c.set(7, 12, 0x8A5A32)
            c.draw([
                "....kkkkkk......",
                "...kGGHHGGk.....",
                "..kGHHHGGGGk....",
                ".kGGHGGGGgGGk...",
                ".kGGGGGGGGGgk...",
                ".kGGGGGgGGGGk...",
                "..kGGgGGGGgk....",
                "...kGGGGGGk.....",
                ".....kkkk.......",
            ].map { String($0.prefix(16)) }, ["G": 0x3E8E4E, "g": 0x2F6F3C, "H": 0x5FB36A, "k": 0x24502C], dx: 1, dy: 1)
        case .bush:
            grass()
            c.draw(["...kkkkk........", "..kGHHGGk.......", ".kGHGGGgGk......", ".kGGGgGGGk......", "..kkkkkkk......."],
                   ["G": 0x4C9E52, "g": 0x2F6F3C, "H": 0x6CC06E, "k": 0x2A5A30], dx: 2, dy: 7)
            c.set(5, 9, 0xD94A5A); c.set(8, 10, 0xD94A5A)
        case .wall:
            c.fill(0xF0DFBC)
            for y in stride(from: 3, to: 16, by: 5) { c.rect(0, y, 16, 1, 0xD3BC93) }
            for y in 0..<16 { c.set(0, y, 0xD3BC93); c.set(15, y, 0xC4AD84) }
            c.rect(4, 4, 8, 7, 0x6B4423)                         // frame
            c.rect(5, 5, 6, 5, 0x8FC8EE); c.rect(5, 5, 6, 1, 0xC9E8FB)
            c.rect(7, 5, 1, 5, 0xF4F1EA); c.rect(5, 7, 6, 1, 0xF4F1EA)
            c.rect(3, 11, 10, 1, 0x8A5A32)                       // sill
            c.set(4, 10, 0xF07AA0); c.set(11, 10, 0xF2D04A)       // flower box
        case .roof:
            c.fill(0xC8553D)
            for y in stride(from: 1, to: 16, by: 4) { c.rect(0, y, 16, 1, 0x9E3E2C) }
            for y in 0..<16 { for x in stride(from: (y / 4) % 2 == 0 ? 0 : 4, to: 16, by: 8) { c.set(x, y, 0x9E3E2C) } }
            for x in 0..<16 { c.set(x, 0, 0xE47A5E) }          // highlight ridge
        default:
            return tileTexture(t, frame: frame)
        }
        return c.texture()
    }
}

enum VillageFX {
    /// A soft round light (white center fading out), for glows, fireflies and the night lantern.
    static func softLight(_ size: CGFloat = 64) -> SKTexture {
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let img = r.image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
        }
        return SKTexture(image: img)
    }

    /// Darker screen corners: draws the eye to the middle without hiding anything.
    static func vignette(_ size: CGSize) -> SKTexture {
        let s = CGSize(width: max(size.width, 2), height: max(size.height, 2))
        let r = UIGraphicsImageRenderer(size: s)
        let img = r.image { ctx in
            let colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.55).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.55, 1])!
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                                             endRadius: hypot(s.width, s.height) / 2, options: [.drawsAfterEndLocation])
        }
        return SKTexture(image: img)
    }

    /// Small pixel leaf/petal for the daytime breeze.
    static func petal() -> SKTexture {
        var c = PixelArt.Canvas(3, 3)
        c.set(1, 0, 0xFFFFFF); c.set(0, 1, 0xFFFFFF); c.set(1, 1, 0xFFFFFF); c.set(2, 1, 0xFFFFFF); c.set(1, 2, 0xFFFFFF)
        return c.texture()
    }

    /// Drifting petals and leaves (day) or blinking fireflies (evening and night).
    static func emitter(for phase: DayPhase, area: CGSize) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particlePositionRange = CGVector(dx: area.width * 1.2, dy: area.height * 1.2)
        e.zPosition = 95
        switch phase {
        case .evening, .night:
            e.particleTexture = softLight(32)
            e.particleBirthRate = phase == .night ? 5 : 2
            e.particleLifetime = 5; e.particleLifetimeRange = 2
            e.particleScale = 0.28; e.particleScaleRange = 0.12
            e.particleColor = UIColor(red: 0.85, green: 1.0, blue: 0.45, alpha: 1)
            e.particleColorBlendFactor = 1
            e.particleBlendMode = .add
            e.particleAlpha = 0; e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.9, 0.2, 0.9, 0], times: [0, 0.2, 0.5, 0.75, 1])
            e.particleSpeed = 8; e.particleSpeedRange = 8; e.emissionAngleRange = .pi * 2
        case .morning, .day:
            e.particleTexture = petal()
            e.particleBirthRate = 1.6
            e.particleLifetime = 9; e.particleLifetimeRange = 3
            e.particleScale = 2.2; e.particleScaleRange = 0.8
            e.particleColorSequence = nil
            e.particleColor = phase == .morning ? UIColor(red: 1, green: 0.78, blue: 0.86, alpha: 1) : UIColor(red: 0.55, green: 0.8, blue: 0.4, alpha: 1)
            e.particleColorBlendFactor = 1
            e.particleAlpha = 0.85
            e.particleSpeed = 22; e.particleSpeedRange = 10
            e.emissionAngle = -.pi * 0.85; e.emissionAngleRange = 0.4
            e.particleRotationRange = .pi * 2; e.particleRotationSpeed = 1.2
            e.xAcceleration = 4; e.yAcceleration = -3
        }
        e.particleTexture?.filteringMode = phase == .day || phase == .morning ? .nearest : .linear
        return e
    }
}
