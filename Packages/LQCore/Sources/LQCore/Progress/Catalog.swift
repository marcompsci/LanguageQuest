import Foundation

public enum CosmeticSlot: String, Codable, Sendable { case hat, accessory }

/// Cosmetic rewards. Purely visual: they never change learning or difficulty.
public struct Cosmetic: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var spanishName: String
    public var slot: CosmeticSlot
    /// Extra cosmetics (Family Plus). Quest rewards are always free.
    public var plusOnly: Bool
}

public struct Badge: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
}

public enum Catalog {
    public static let cosmetics: [Cosmetic] = [
        Cosmetic(id: "hat-straw", name: "Straw hat", spanishName: "el sombrero de paja", slot: .hat, plusOnly: false),
        Cosmetic(id: "scarf-yellow", name: "Yellow scarf", spanishName: "la bufanda amarilla", slot: .accessory, plusOnly: false),
        Cosmetic(id: "cap-red", name: "Red cap", spanishName: "la gorra roja", slot: .hat, plusOnly: false),
        Cosmetic(id: "backpack-blue", name: "Blue backpack", spanishName: "la mochila azul", slot: .accessory, plusOnly: false),
        Cosmetic(id: "crown-flowers", name: "Flower crown", spanishName: "la corona de flores", slot: .hat, plusOnly: false),
        Cosmetic(id: "glasses-round", name: "Round glasses", spanishName: "las gafas redondas", slot: .accessory, plusOnly: false),
        Cosmetic(id: "beret-green", name: "Green beret", spanishName: "la boina verde", slot: .hat, plusOnly: false),
        Cosmetic(id: "paintbrush", name: "Paintbrush", spanishName: "el pincel", slot: .accessory, plusOnly: false),
        Cosmetic(id: "bandana-purple", name: "Purple bandana", spanishName: "el pañuelo morado", slot: .hat, plusOnly: false),
        Cosmetic(id: "pet-dog", name: "Puppy pal", spanishName: "el perrito", slot: .accessory, plusOnly: false),
        Cosmetic(id: "apron", name: "Baker's apron", spanishName: "el delantal", slot: .accessory, plusOnly: false),
        Cosmetic(id: "basket", name: "Market basket", spanishName: "la canasta", slot: .accessory, plusOnly: false),
        Cosmetic(id: "chef-hat", name: "Chef hat", spanishName: "el gorro de chef", slot: .hat, plusOnly: false),
        Cosmetic(id: "coin-pin", name: "Coin pin", spanishName: "el broche de moneda", slot: .accessory, plusOnly: false),
        Cosmetic(id: "hat-sun", name: "Sun hat", spanishName: "el sombrero de sol", slot: .hat, plusOnly: false),
        Cosmetic(id: "cape-night", name: "Night cape", spanishName: "la capa de noche", slot: .accessory, plusOnly: true),
        Cosmetic(id: "helmet-star", name: "Star helmet", spanishName: "el casco de estrellas", slot: .hat, plusOnly: true),
    ]

    public static let badges: [Badge] = [
        Badge(id: "badge-u1", name: "Hola Hero", detail: "Finished Unit 1: Greetings"),
        Badge(id: "badge-u2", name: "Family Friend", detail: "Finished Unit 2: Family"),
        Badge(id: "badge-u3", name: "Market Pro", detail: "Finished Unit 3: Market"),
        Badge(id: "badge-mastery-u1", name: "Greetings Master", detail: "Passed the Unit 1 mastery check"),
        Badge(id: "badge-mastery-u2", name: "Family Master", detail: "Passed the Unit 2 mastery check"),
        Badge(id: "badge-mastery-u3", name: "Market Master", detail: "Passed the Unit 3 mastery check"),
    ]

    public static func cosmetic(_ id: String) -> Cosmetic? { cosmetics.first { $0.id == id } }
    public static func badge(_ id: String) -> Badge? { badges.first { $0.id == id } }

    public static func masteryBadge(forUnitOrder n: Int) -> String { "badge-mastery-u\(n)" }
}
