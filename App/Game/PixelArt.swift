import CoreGraphics
import SpriteKit
import UIKit
import LQCore

/// Original pixel art, drawn in code from small character maps. No third-party
/// artwork. Every texture uses nearest-neighbour filtering so pixels stay crisp.
enum PixelArt {
    static let tile = 16

    // MARK: Canvas

    struct Canvas {
        let w: Int, h: Int
        var px: [UInt32?]
        init(_ w: Int, _ h: Int) { self.w = w; self.h = h; px = Array(repeating: nil, count: w * h) }
        mutating func set(_ x: Int, _ y: Int, _ c: UInt32?) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            px[y * w + x] = c
        }
        mutating func fill(_ c: UInt32) { for i in px.indices { px[i] = c } }
        mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: UInt32) {
            for yy in y..<(y + rh) { for xx in x..<(x + rw) { set(xx, yy, c) } }
        }
        /// Draws a character map; `.` is transparent.
        mutating func draw(_ rows: [String], _ colors: [Character: UInt32], dx: Int = 0, dy: Int = 0, flip: Bool = false) {
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    if let c = colors[ch] { set(flip ? (row.count - 1 - x) + dx : x + dx, y + dy, c) }
                }
            }
        }

        func image() -> CGImage? {
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            for i in 0..<(w * h) {
                guard let c = px[i] else { continue }
                bytes[i * 4] = UInt8((c >> 16) & 0xFF)
                bytes[i * 4 + 1] = UInt8((c >> 8) & 0xFF)
                bytes[i * 4 + 2] = UInt8(c & 0xFF)
                bytes[i * 4 + 3] = 255
            }
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }

        func texture() -> SKTexture {
            guard let img = image() else { return SKTexture() }
            let t = SKTexture(cgImage: img)
            t.filteringMode = .nearest
            return t
        }

        func uiImage(scale: CGFloat = 8) -> UIImage {
            guard let img = image() else { return UIImage() }
            let size = CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
            let r = UIGraphicsImageRenderer(size: size)
            return r.image { ctx in
                ctx.cgContext.interpolationQuality = .none
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                ctx.cgContext.draw(img, in: CGRect(origin: .zero, size: size))
            }
        }
    }

    /// Tiny deterministic hash for texture speckles.
    static func noise(_ x: Int, _ y: Int, _ seed: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_274_126_177)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Int(h ^ (h >> 16)) & 0xFF
    }

    // MARK: Palettes

    static let skin: [UInt32] = [0xF6D2B5, 0xE9B48F, 0xC98E64, 0xA86B45, 0x7E4E31, 0x5A3522]
    static let hairColors: [UInt32] = [0x2B1B12, 0x5B3A1E, 0xA8672E, 0xE2B65A, 0x9A3B2B, 0x8A8A96]
    static let outfits: [UInt32] = [0x2E7DC9, 0xD9534F, 0x3BA55C, 0xF0B429, 0x8E5CC4, 0xE57AA8, 0x34A3A3, 0x5B6474]
    static let outline: UInt32 = 0x2A2233

    // MARK: Characters (16×16, front view)

    static let bodyRows = [
        "................",
        "................",
        ".....SSSSSS.....",
        "....SSSSSSSS....",
        "....SSESSESS....",
        "....SSSSSSSS....",
        ".....SSMMSS.....",
        "......SSSS......",
        "....OOOOOOOO....",
        "...SOOOOOOOOS...",
        "...SOOOOOOOOS...",
        "....OOOOOOOO....",
        "....PPPPPPPP....",
        "....PPP..PPP....",
        "....PPP..PPP....",
        "....KKK..KKK....",
    ]

    static let hairStyles: [[String]] = [
        [ // short
            "................",
            ".....HHHHHH.....",
            "....HHHHHHHH....",
            "....H......H....",
        ],
        [ // long
            "................",
            ".....HHHHHH.....",
            "....HHHHHHHH....",
            "...HH......HH...",
            "...H........H...",
            "...H........H...",
            "...HH......HH...",
            "...HH......HH...",
        ],
        [ // spiky
            "....H.H..H.H....",
            ".....HHHHHH.....",
            "....HHHHHHHH....",
            "....H......H....",
        ],
        [ // bun
            ".......HH.......",
            ".....HHHHHH.....",
            "....HHHHHHHH....",
            "....H......H....",
        ],
        [ // curly
            ".....H.HH.H.....",
            "....HHHHHHHH....",
            "...HHHHHHHHHH...",
            "...HH......HH...",
            "...H........H...",
        ],
    ]

    /// Back of the head (walking up): hair covers the face.
    static let backHair = [
        "................",
        ".....HHHHHH.....",
        "....HHHHHHHH....",
        "....HHHHHHHH....",
        "....HHHHHHHH....",
        "....HHHHHHHH....",
        ".....HHHHHH.....",
    ]

    enum Extra { case none, scarf, glasses, mustacheHat, apron, cap, paintbrush, sunHat, crown, backpack, beret, bandana, chefHat }

    struct Look: Hashable {
        var skin: Int, hair: Int, hairColor: Int, outfit: Int
        var pants: UInt32 = 0x3A3F5C
        var extras: [String] = []   // cosmetic ids / NPC extras
    }

    /// Second walking pose: legs apart.
    static let strideRows = [
        "....PPP..PPP....",
        "...PPP....PPP...",
        "...KKK....KKK...",
    ]

    static func character(_ l: Look, facing: Direction, frame: Int = 0) -> SKTexture {
        var c = Canvas(16, 16)
        let colors: [Character: UInt32] = [
            "S": skin[l.skin % skin.count], "E": 0x231A26, "M": 0xB0505A,
            "O": outfits[l.outfit % outfits.count], "P": l.pants, "K": 0x3B2A20,
            "H": hairColors[l.hairColor % hairColors.count],
        ]
        c.draw(bodyRows, colors)
        if frame % 2 == 1 {
            for y in 13..<16 { for x in 0..<16 { c.set(x, y, nil) } }
            c.draw(strideRows, colors, dy: 13)
        }
        if facing == .up {
            c.draw(backHair, colors)
        } else {
            c.draw(hairStyles[l.hair % hairStyles.count], colors)
        }
        for e in l.extras { drawExtra(e, on: &c, facing: facing) }
        // Side views: shift one pixel so turning reads clearly.
        if facing == .left || facing == .right {
            var shifted = Canvas(16, 16)
            for y in 0..<16 { for x in 0..<16 { shifted.set(x + (facing == .right ? 1 : -1), y, c.px[y * 16 + x]) } }
            c = shifted
        }
        return c.texture()
    }

    static func drawExtra(_ id: String, on c: inout Canvas, facing: Direction) {
        switch id {
        case "scarf-yellow": c.rect(4, 7, 8, 2, 0xF2C230); c.rect(9, 9, 2, 2, 0xF2C230)
        case "glasses-round", "npc-glasses":
            if facing != .up { c.rect(5, 4, 2, 1, 0x222222); c.rect(9, 4, 2, 1, 0x222222); c.set(7, 4, 0x222222); c.set(8, 4, 0x222222) }
        case "npc-mustache": if facing != .up { c.rect(6, 5, 4, 1, 0x4A3020) }
        case "hat-straw", "hat-sun": c.rect(3, 1, 10, 1, 0xE8C66A); c.rect(5, 0, 6, 1, 0xE8C66A)
        case "cap-red": c.rect(5, 0, 6, 2, 0xD23B3B); if facing == .down { c.rect(5, 2, 7, 1, 0xA82A2A) }
        case "apron": c.rect(5, 9, 6, 4, 0xF4F1EA)
        case "backpack-blue": if facing == .up { c.rect(5, 8, 6, 4, 0x2E62B8) } else { c.set(3, 8, 0x2E62B8); c.set(12, 8, 0x2E62B8) }
        case "crown-flowers": c.set(5, 1, 0xF07AA0); c.set(7, 0, 0xF2D04A); c.set(9, 0, 0xF07AA0); c.set(10, 1, 0x7AC3F0)
        case "beret-green": c.rect(4, 1, 8, 2, 0x3C7D46); c.set(8, 0, 0x3C7D46)
        case "paintbrush": c.rect(13, 8, 1, 4, 0x9B6A3C); c.set(13, 7, 0xD23B3B)
        case "bandana-purple": c.rect(4, 2, 8, 1, 0x8E4FC2); c.set(12, 3, 0x8E4FC2)
        case "chef-hat": c.rect(5, 0, 6, 2, 0xFAFAFA); c.rect(4, 1, 8, 1, 0xFAFAFA)
        case "basket": c.rect(12, 10, 3, 2, 0xB07A3E)
        case "coin-pin": c.set(10, 9, 0xF2C230)
        case "pet-dog": break // drawn as a separate follower sprite
        case "cape-night": c.rect(3, 8, 1, 6, 0x23305E); c.rect(12, 8, 1, 6, 0x23305E)
        case "helmet-star": c.rect(4, 0, 8, 3, 0xC7D0E0); c.set(8, 1, 0xF2C230)
        default: break
        }
    }

    static func avatarLook(_ a: AvatarConfig) -> Look {
        Look(skin: a.body, hair: a.hair, hairColor: a.hairColor, outfit: a.outfit, extras: [a.hat, a.accessory].compactMap { $0 })
    }

    static func npcLook(_ id: String) -> Look {
        switch id {
        case "luna": return Look(skin: 1, hair: 1, hairColor: 0, outfit: 4, extras: ["scarf-yellow"])
        case "mateo": return Look(skin: 2, hair: 2, hairColor: 0, outfit: 1, extras: [])
        case "dona-rosa": return Look(skin: 2, hair: 3, hairColor: 5, outfit: 5, extras: ["apron"])
        case "profe-sol": return Look(skin: 3, hair: 4, hairColor: 0, outfit: 6, extras: ["npc-glasses"])
        case "don-pepe": return Look(skin: 1, hair: 0, hairColor: 5, outfit: 2, extras: ["npc-mustache", "hat-straw"])
        case "abuela-lola": return Look(skin: 4, hair: 3, hairColor: 5, outfit: 3, extras: ["paintbrush"])
        case "nico": return Look(skin: 5, hair: 0, hairColor: 0, outfit: 0, extras: ["cap-red"])
        case "senora-ana": return Look(skin: 0, hair: 1, hairColor: 2, outfit: 7, extras: ["apron"])
        default: return Look(skin: 0, hair: 0, hairColor: 0, outfit: 0)
        }
    }

    static let dogRows = [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "..........BB....",
        ".........BBBB...",
        ".........BEBBN..",
        "..B.....BBBBB...",
        "...BBBBBBBB.....",
        "...BBBBBBBB.....",
        "...BBBBBBBB.....",
        "...B.B..B.B.....",
        "...B.B..B.B.....",
        "................",
    ]

    /// A soft four-point sparkle for hidden word treasures.
    static func sparkle() -> SKTexture {
        var c = Canvas(8, 8)
        c.draw(["...W....", "...W....", "..WYW...", "WWYYYWW.", "..WYW...", "...W....", "...W....", "........"],
               ["W": 0xFFFFFF, "Y": 0xFFE680])
        return c.texture()
    }

    static func dog() -> SKTexture {
        var c = Canvas(16, 16)
        c.draw(dogRows, ["B": 0xC9853F, "E": 0x231A26, "N": 0x3A2A22])
        return c.texture()
    }

    // MARK: Tiles

    static func tileTexture(_ t: Tile, frame: Int = 0) -> SKTexture {
        var c = Canvas(16, 16)
        let grass: UInt32 = 0x7CC46A, grassDark: UInt32 = 0x5FA855
        func grassBase() {
            c.fill(grass)
            for y in 0..<16 { for x in 0..<16 where noise(x, y, 1) < 18 { c.set(x, y, grassDark) } }
        }
        switch t {
        case .grass: grassBase()
        case .flowers:
            grassBase()
            for (x, y, col) in [(3, 4, 0xF07AA0), (11, 3, 0xF2D04A), (6, 11, 0xFFFFFF), (13, 12, 0xF07AA0)] as [(Int, Int, UInt32)] {
                c.set(x, y, col); c.set(x + 1, y, col); c.set(x, y + 1, col); c.set(x + 1, y + 1, 0xF2D04A)
            }
        case .path:
            c.fill(0xE3C58E)
            for y in 0..<16 { for x in 0..<16 where noise(x, y, 2) < 14 { c.set(x, y, 0xC9A66B) } }
        case .sand:
            c.fill(0xF1DFA6)
            for y in 0..<16 { for x in 0..<16 where noise(x, y, 3) < 12 { c.set(x, y, 0xE0C887) } }
        case .water:
            c.fill(0x4FA3E0)
            for y in stride(from: 3 + frame, to: 16, by: 6) { for x in 0..<16 where (x + y + frame * 3) % 8 < 3 { c.set(x, y, 0x9FD3F5) } }
        case .bridge:
            c.fill(0x4FA3E0)
            c.rect(0, 1, 16, 14, 0xA8743F)
            for y in stride(from: 1, to: 15, by: 4) { c.rect(0, y, 16, 1, 0x7E5430) }
        case .tree:
            grassBase()
            c.rect(7, 11, 2, 5, 0x7E5430)
            c.draw([
                "....GGGGGG......",
                "...GGGGGGGGG....",
                "..GGGgGGGGGGG...",
                ".GGGGGGGGgGGGG..",
                ".GGgGGGGGGGGGG..",
                ".GGGGGGGgGGGGG..",
                "..GGGGGGGGGGG...",
                "...GGGGGgGGG....",
                ".....GGGGG......",
            ], ["G": 0x3E8E4E, "g": 0x2F6F3C], dy: 1)
        case .bush:
            grassBase()
            c.draw(["....GGGGG.......", "..GGGGGGGGG.....", ".GGGgGGGGGGG....", ".GGGGGGGgGGG....", "..GGGGGGGGG....."],
                   ["G": 0x4C9E52, "g": 0x2F6F3C], dx: 2, dy: 7)
        case .wall:
            c.fill(0xF3E3C3)
            for y in stride(from: 3, to: 16, by: 5) { c.rect(0, y, 16, 1, 0xD8C29B) }
            c.rect(5, 5, 6, 5, 0x9FD3F5); c.rect(5, 7, 6, 1, 0xFFFFFF); c.rect(7, 5, 1, 5, 0xFFFFFF)
        case .roof:
            c.fill(0xC8553D)
            for y in stride(from: 1, to: 16, by: 4) { c.rect(0, y, 16, 1, 0xA8432F) }
            for y in 0..<16 { for x in stride(from: (y / 4) % 2 == 0 ? 0 : 4, to: 16, by: 8) { c.set(x, y, 0xA8432F) } }
        case .door:
            c.fill(0xF3E3C3)
            c.rect(4, 2, 8, 14, 0x8A5A32); c.rect(5, 3, 6, 12, 0xA8743F); c.set(10, 9, 0xF2C230)
        case .fence:
            grassBase()
            c.rect(0, 6, 16, 2, 0xE8D9B8); c.rect(0, 11, 16, 2, 0xE8D9B8)
            for x in [2, 7, 12] { c.rect(x, 4, 2, 11, 0xF4EAD2) }
        case .fountain:
            c.fill(0xE3C58E)
            c.draw([
                "....SSSSSSSS....", "..SSWWWWWWWWSS..", ".SWWWWwWWWWWWWS.", "SWWWWWWSSWWwWWWS",
                "SWWwWWSSSSWWWWWS", "SWWWWWSSSSWWWwWS", "SWWWWWWSSWWWWWWS", ".SWWwWWWWWWWWWS.",
                "..SSWWWWWWWWSS..", "....SSSSSSSS....",
            ], ["S": 0xB7B7C2, "W": 0x4FA3E0, "w": frame == 0 ? 0xFFFFFF : 0x9FD3F5], dy: 3)
        case .stall:
            c.fill(0xE3C58E)
            for x in 0..<16 { c.rect(x, 0, 1, 5, (x / 2) % 2 == 0 ? 0xE8473A : 0xFFFFFF) }
            c.rect(1, 9, 14, 6, 0xA8743F)
            c.rect(2, 7, 3, 2, 0xE8473A); c.rect(6, 7, 3, 2, 0xF2B530); c.rect(10, 7, 3, 2, 0x6CC04A)
        case .sign:
            grassBase()
            c.rect(7, 8, 2, 8, 0x7E5430); c.rect(2, 3, 12, 6, 0xA8743F); c.rect(3, 5, 10, 1, 0x5C3B1E)
        }
        return c.texture()
    }

    /// A UIImage of the avatar for SwiftUI screens (onboarding, bag).
    static func avatarImage(_ a: AvatarConfig, scale: CGFloat = 8) -> UIImage {
        var c = Canvas(16, 16)
        let l = avatarLook(a)
        let colors: [Character: UInt32] = [
            "S": skin[l.skin % skin.count], "E": 0x231A26, "M": 0xB0505A,
            "O": outfits[l.outfit % outfits.count], "P": l.pants, "K": 0x3B2A20, "H": hairColors[l.hairColor % hairColors.count],
        ]
        c.draw(bodyRows, colors)
        c.draw(hairStyles[l.hair % hairStyles.count], colors)
        for e in l.extras { drawExtra(e, on: &c, facing: .down) }
        return c.uiImage(scale: scale)
    }
}
