import Foundation

/// Hidden "palabras perdidas" (lost words) around Starter Village. Inspecting a
/// spot reveals a bonus nature word and a fun fact. Purely optional exploration.
public struct WordTreasure: Hashable, Identifiable, Sendable {
    public var id: String
    public var position: GridPoint
    public var spanish: VText
    public var english: String
    public var emoji: String
    public var fact: String
    /// The word in other target languages, and a fact about that language's world.
    public var other: [String: (word: VText, fact: String)] = [:]

    public func word(_ language: String) -> VText { language == "es" ? spanish : other[language]?.word ?? spanish }
    public func fact(_ language: String) -> String { language == "es" ? fact : other[language]?.fact ?? fact }

    public static func == (a: WordTreasure, b: WordTreasure) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

extension StarterVillage {
    public static let treasures: [WordTreasure] = [
        WordTreasure(id: "t-flor", position: GridPoint(14, 2), spanish: "la flor", english: "the flower", emoji: "🌸",
                     fact: "Mexico's national flower is the dahlia (la dalia).",
                     other: ["fr": ("la fleur", "The fleur-de-lis (a lily flower) appears on the flag of Québec."), "ja": ("はな", "Every spring, people hold hanami picnics under the cherry blossoms (さくら).")]),
        WordTreasure(id: "t-mariposa", position: GridPoint(12, 5), spanish: "la mariposa", english: "the butterfly", emoji: "🦋",
                     fact: "Millions of monarch butterflies spend the winter in the forests of Michoacán, Mexico.",
                     other: ["fr": ("le papillon", "In French, a bow tie is a nœud papillon: a butterfly knot!"), "ja": ("ちょうちょ", "A famous Japanese children's song is called ちょうちょ (Butterfly).")]),
        WordTreasure(id: "t-abeja", position: GridPoint(3, 7), spanish: "la abeja", english: "the bee", emoji: "🐝",
                     fact: "The Maya kept stingless bees for honey more than a thousand years ago.",
                     other: ["fr": ("l'abeille", "Napoleon used golden bees as his personal symbol."), "ja": ("はち", "はち means both bee and the number eight, written with different kanji.")]),
        WordTreasure(id: "t-sol", position: GridPoint(16, 7), spanish: "el sol", english: "the sun", emoji: "☀️",
                     fact: "A sun appears on the flags of Argentina and Uruguay: el Sol de Mayo.",
                     other: ["fr": ("le soleil", "King Louis XIV of France was nicknamed the Sun King: le Roi-Soleil."), "ja": ("たいよう", "Japan's name, にほん, means origin of the sun, the land of the rising sun.")]),
        WordTreasure(id: "t-estrella", position: GridPoint(25, 13), spanish: "la estrella", english: "the star", emoji: "⭐",
                     fact: "Chile's Atacama Desert has some of the clearest night skies on Earth for watching estrellas.",
                     other: ["fr": ("l'étoile", "A shooting star is une étoile filante in French."), "ja": ("ほし", "On Tanabata (July 7), people write wishes on paper strips under the stars.")]),
        WordTreasure(id: "t-luna", position: GridPoint(17, 15), spanish: "la luna", english: "the moon", emoji: "🌙",
                     fact: "Luna is also a popular name in Spanish-speaking countries.",
                     other: ["fr": ("la lune", "Être dans la lune (to be in the moon) means to daydream."), "ja": ("つき", "In Japan, people say they see a rabbit making rice cakes on the moon.")]),
        WordTreasure(id: "t-arbol", position: GridPoint(11, 19), spanish: "el árbol", english: "the tree", emoji: "🌳",
                     fact: "El Árbol del Tule in Oaxaca has one of the thickest trunks of any tree in the world.",
                     other: ["fr": ("l'arbre", "Some oak trees in France are more than 1,000 years old."), "ja": ("き", "Japan's Jōmon Sugi cedar tree may be thousands of years old.")]),
        WordTreasure(id: "t-nube", position: GridPoint(27, 21), spanish: "la nube", english: "the cloud", emoji: "☁️",
                     fact: "In Spain, someone daydreaming is said to be “en las nubes” (in the clouds).",
                     other: ["fr": ("le nuage", "Être sur un petit nuage (on a little cloud) means feeling very happy."), "ja": ("くも", "くも means cloud, and also spider, written with a different kanji!")]),
        WordTreasure(id: "t-caracol", position: GridPoint(9, 3), spanish: "el caracol", english: "the snail", emoji: "🐌",
                     fact: "A spiral staircase in Spanish is an escalera de caracol: a snail staircase!",
                     other: ["fr": ("l'escargot", "Some people in France eat escargots with garlic butter as a special dish."), "ja": ("かたつむり", "かたつむり is a classic rainy-season (つゆ) song in Japan.")]),
        WordTreasure(id: "t-rana", position: GridPoint(16, 19), spanish: "la rana", english: "the frog", emoji: "🐸",
                     fact: "Costa Rica's rainforests are home to the bright red-eyed tree frog.",
                     other: ["fr": ("la grenouille", "In Québec, wood frogs can freeze in winter and thaw out alive in spring!"), "ja": ("かえる", "かえる also means to go home, so frog charms are a wish for a safe return.")]),
    ]

    public static func treasure(at p: GridPoint) -> WordTreasure? { treasures.first { $0.position == p } }
}

/// An 8-way heading from the player toward a goal, for the quest tracker.
public enum Heading: String, CaseIterable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest, here

    public var symbolName: String {
        switch self {
        case .north: return "arrow.up"
        case .northEast: return "arrow.up.right"
        case .east: return "arrow.right"
        case .southEast: return "arrow.down.right"
        case .south: return "arrow.down"
        case .southWest: return "arrow.down.left"
        case .west: return "arrow.left"
        case .northWest: return "arrow.up.left"
        case .here: return "location.fill"
        }
    }

    public var words: String {
        switch self {
        case .north: return "up"
        case .northEast: return "up and right"
        case .east: return "right"
        case .southEast: return "down and right"
        case .south: return "down"
        case .southWest: return "down and left"
        case .west: return "left"
        case .northWest: return "up and left"
        case .here: return "right next to you"
        }
    }
}

public enum QuestCompass {
    /// Grid y grows downward, so "north" (up the screen) is negative dy.
    public static func heading(from a: GridPoint, to b: GridPoint) -> Heading {
        let dx = b.x - a.x, dy = b.y - a.y
        if abs(dx) + abs(dy) <= 1 { return .here }
        let angle = atan2(Double(-dy), Double(dx)) * 180 / .pi   // 0 = east, 90 = north
        let sector = Int(((angle + 360 + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return [Heading.east, .northEast, .north, .northWest, .west, .southWest, .south, .southEast][sector]
    }

    /// Steps along the real walking path (falls back to straight-line distance).
    public static func steps(from a: GridPoint, to b: GridPoint, map: TileMap, blocked: Set<GridPoint>) -> Int {
        map.path(from: a, to: b, blocked: blocked)?.count ?? a.manhattan(to: b)
    }
}
