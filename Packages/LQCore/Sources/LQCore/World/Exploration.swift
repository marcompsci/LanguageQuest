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
}

extension StarterVillage {
    public static let treasures: [WordTreasure] = [
        WordTreasure(id: "t-flor", position: GridPoint(14, 2), spanish: "la flor", english: "the flower", emoji: "🌸",
                     fact: "Mexico's national flower is the dahlia (la dalia)."),
        WordTreasure(id: "t-mariposa", position: GridPoint(12, 5), spanish: "la mariposa", english: "the butterfly", emoji: "🦋",
                     fact: "Millions of monarch butterflies spend the winter in the forests of Michoacán, Mexico."),
        WordTreasure(id: "t-abeja", position: GridPoint(3, 7), spanish: "la abeja", english: "the bee", emoji: "🐝",
                     fact: "The Maya kept stingless bees for honey more than a thousand years ago."),
        WordTreasure(id: "t-sol", position: GridPoint(16, 7), spanish: "el sol", english: "the sun", emoji: "☀️",
                     fact: "A sun appears on the flags of Argentina and Uruguay: el Sol de Mayo."),
        WordTreasure(id: "t-estrella", position: GridPoint(25, 13), spanish: "la estrella", english: "the star", emoji: "⭐",
                     fact: "Chile's Atacama Desert has some of the clearest night skies on Earth for watching estrellas."),
        WordTreasure(id: "t-luna", position: GridPoint(17, 15), spanish: "la luna", english: "the moon", emoji: "🌙",
                     fact: "Luna is also a popular name in Spanish-speaking countries."),
        WordTreasure(id: "t-arbol", position: GridPoint(11, 19), spanish: "el árbol", english: "the tree", emoji: "🌳",
                     fact: "El Árbol del Tule in Oaxaca has one of the thickest trunks of any tree in the world."),
        WordTreasure(id: "t-nube", position: GridPoint(27, 21), spanish: "la nube", english: "the cloud", emoji: "☁️",
                     fact: "In Spain, someone daydreaming is said to be “en las nubes” (in the clouds)."),
        WordTreasure(id: "t-caracol", position: GridPoint(9, 3), spanish: "el caracol", english: "the snail", emoji: "🐌",
                     fact: "A spiral staircase in Spanish is an escalera de caracol: a snail staircase!"),
        WordTreasure(id: "t-rana", position: GridPoint(16, 19), spanish: "la rana", english: "the frog", emoji: "🐸",
                     fact: "Costa Rica's rainforests are home to the bright red-eyed tree frog."),
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
