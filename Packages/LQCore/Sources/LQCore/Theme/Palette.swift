import Foundation

/// An sRGB color as 0xRRGGBB, shared by SwiftUI and SpriteKit code.
public struct RGB: Hashable, Sendable {
    public var hex: UInt32
    public init(_ hex: UInt32) { self.hex = hex }
    public var r: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var g: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var b: Double { Double(hex & 0xFF) / 255 }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

/// UI colors for the two age-sensitive themes. Both share the same learning core.
/// Right/wrong feedback always pairs color with a shape and words
/// (✓ check / ↺ try-again arrow), so it never relies on color alone.
public struct ThemePalette: Sendable {
    public var background: RGB
    public var surface: RGB
    public var text: RGB
    public var secondaryText: RGB
    public var accent: RGB
    public var onAccent: RGB
    public var success: RGB
    public var retry: RGB
    public var dialogueBox: RGB
    public var dialogueText: RGB

    public static func of(_ k: ThemeKind) -> ThemePalette {
        switch k {
        case .playful:
            return ThemePalette(background: RGB(0xFFF6E0), surface: RGB(0xFFFFFF), text: RGB(0x2B2340),
                                secondaryText: RGB(0x5A4F6E), accent: RGB(0x1F6FB2), onAccent: RGB(0xFFFFFF),
                                success: RGB(0x1B7A3A), retry: RGB(0x9A4A00),
                                dialogueBox: RGB(0xFFFDF5), dialogueText: RGB(0x2B2340))
        case .explorer:
            return ThemePalette(background: RGB(0x161B2E), surface: RGB(0x222944), text: RGB(0xF2EFE6),
                                secondaryText: RGB(0xC2BFD6), accent: RGB(0x7FD1C7), onAccent: RGB(0x0E1322),
                                success: RGB(0x8FE3A3), retry: RGB(0xFFC27A),
                                dialogueBox: RGB(0x1C2238), dialogueText: RGB(0xF2EFE6))
        }
    }

    /// Text/background pairs that must meet WCAG AA (4.5:1). Checked by tests.
    public var textPairs: [(String, RGB, RGB)] {
        [("text/background", text, background), ("text/surface", text, surface),
         ("secondary/surface", secondaryText, surface), ("secondary/background", secondaryText, background),
         ("onAccent/accent", onAccent, accent), ("success/surface", success, surface),
         ("retry/surface", retry, surface), ("dialogue", dialogueText, dialogueBox)]
    }
}
