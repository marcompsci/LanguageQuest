import Foundation

public struct NPCSpot: Hashable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    public var position: GridPoint
    public var facing: Direction
}

public struct MapExit: Hashable, Sendable {
    public var position: GridPoint
    public var destination: String
    public var label: String
    /// Unit order that must be finished (all quests) before this exit opens.
    public var requiresUnitOrder: Int?
}

public struct PlaceSign: Hashable, Sendable {
    public var position: GridPoint
    public var spanish: String
    public var english: String
    /// The sign in other target languages (key: language code).
    public var other: [String: String] = [:]

    /// The sign's text in a target language (Spanish if missing).
    public func text(_ language: String) -> String {
        language == "es" ? spanish : other[language] ?? StarterVillage.generatedSigns[english]?[language] ?? spanish
    }
}

/// The first explorable world. Map is text so designers can edit it without code.
public enum StarterVillage {
    public static let sceneId = "starter-village"

    public static let rows: [String] = [
        "TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
        "T..............................T",
        "T.^^^^^.......*.....^^^^^^^....T",
        "T.#####..b..........#######..b.T",
        "T.##D##.............###D###....T",
        "T...,.......*.......,..,.......T",
        "T...,,,,,,,,,,,,,,,,,,,,..~~~..T",
        "T..*.......,....*.......,.~~~..T",
        "T..........,............,..=...T",
        "Tb.....,,,,,,,,,,,,,,...,..,...T",
        "T......,.....,...,..,...,,,,,,,,",
        "T..T...,..,,,,o,,,,.,..........!",
        "T......,..,.......,.,..........T",
        "T......,..,,,,,,,,,.,....*.....T",
        "T......,............,..........T",
        "T.^^^^^,.........*..,..s.s.s...T",
        "T.#####,............,..,,,,,...T",
        "T.##D##,,,,,,,,,,,,,,,,,,,,,...T",
        "T...,..............,...........T",
        "T...,,,,,..*....b..,...~~~~....T",
        "T..................,...~~~~..T.T",
        "T.b......f.f.f.f...,.......*...T",
        "T..............................T",
        "TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
    ]

    public static func map() -> TileMap {
        // The rows are a fixed literal checked by tests; parsing cannot fail.
        try! TileMap(rows: rows)
    }

    public static let spawn = GridPoint(4, 5)

    /// Original characters (no third-party IP).
    public static let npcs: [NPCSpot] = [
        NPCSpot(id: "luna", name: "Luna", role: "Your guide. She loves maps and her yellow scarf.", position: GridPoint(6, 6), facing: .down),
        NPCSpot(id: "mateo", name: "Mateo", role: "A kid who knows every corner of the plaza.", position: GridPoint(12, 12), facing: .left),
        NPCSpot(id: "dona-rosa", name: "Doña Rosa", role: "The baker. Her pan dulce is famous.", position: GridPoint(5, 18), facing: .down),
        NPCSpot(id: "profe-sol", name: "Profe Sol", role: "The village teacher, always with a book.", position: GridPoint(22, 5), facing: .down),
        NPCSpot(id: "don-pepe", name: "Don Pepe", role: "Runs the fruit stand at the market.", position: GridPoint(24, 15), facing: .down),
        NPCSpot(id: "abuela-lola", name: "Abuela Lola", role: "Mateo's grandma, a painter.", position: GridPoint(9, 20), facing: .up),
        NPCSpot(id: "nico", name: "Nico", role: "Walks his dog Canela every day.", position: GridPoint(17, 7), facing: .down),
        NPCSpot(id: "senora-ana", name: "Señora Ana", role: "Sells milk, cheese and eggs.", position: GridPoint(26, 15), facing: .down),
    ]

    public static let exits: [MapExit] = [
        MapExit(position: GridPoint(31, 10), destination: "conversation-town", label: "Conversation Town", requiresUnitOrder: 3)
    ]

    public static let signs: [PlaceSign] = [
        PlaceSign(position: GridPoint(4, 4), spanish: "La casa de Luna", english: "Luna's house",
                  other: ["fr": "La maison de Luna", "ja": "ルナ の いえ"]),
        PlaceSign(position: GridPoint(23, 4), spanish: "La escuela", english: "The school",
                  other: ["fr": "L'école", "ja": "がっこう"]),
        PlaceSign(position: GridPoint(4, 17), spanish: "La panadería", english: "The bakery",
                  other: ["fr": "La boulangerie", "ja": "パンや"]),
        PlaceSign(position: GridPoint(14, 11), spanish: "La fuente", english: "The fountain",
                  other: ["fr": "La fontaine", "ja": "ふんすい"]),
        PlaceSign(position: GridPoint(25, 15), spanish: "El mercado", english: "The market",
                  other: ["fr": "Le marché", "ja": "いちば"]),
        PlaceSign(position: GridPoint(31, 11), spanish: "Pueblo Conversación", english: "Conversation Town lookout",
                  other: ["fr": "Ville Conversation", "ja": "かいわ タウン"]),
    ]

    public static var npcPositions: Set<GridPoint> { Set(npcs.map(\.position)) }

    public static func npc(at p: GridPoint) -> NPCSpot? { npcs.first { $0.position == p } }
    public static func npc(_ id: String) -> NPCSpot? { npcs.first { $0.id == id } }
    public static func sign(at p: GridPoint) -> PlaceSign? { signs.first { $0.position == p } }
    public static func exit(at p: GridPoint) -> MapExit? { exits.first { $0.position == p } }
}
