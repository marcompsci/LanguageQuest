import Foundation

/// Señora Ana's Market Rush: read a Spanish shopping list, pick the right items,
/// then pay the exact total with coins. Prices use the variant's currency.
public struct MarketGood: Hashable, Sendable {
    public var itemId: String
    public var price: Int
}

public struct MarketOrder: Hashable, Sendable {
    /// The list, in Spanish (what the learner must read).
    public var wanted: [MarketGood]
    /// Everything on the stall: wanted goods plus decoys.
    public var stall: [MarketGood]
    public var total: Int { wanted.reduce(0) { $0 + $1.price } }
}

public struct MarketRush: Sendable {
    public static let rounds = 3
    public static let itemsPerOrder = 3
    public static let stallSize = 6
    public static let coins = [1, 2, 5, 10]
    /// Food words from Unit 3 that make sense on a stall.
    public static let goods = ["manzana", "platano", "naranja", "fresa", "uvas", "aguacate", "pan", "leche", "queso", "huevos", "jugo", "agua"]

    public let orders: [MarketOrder]
    public private(set) var index = 0
    public private(set) var cleanRounds = 0
    private var mistakesThisRound = 0

    public init(library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let available = Self.goods.filter { library.item($0) != nil }
        var orders: [MarketOrder] = []
        for _ in 0..<Self.rounds {
            let stallIds = Array(available.shuffled(using: &rng).prefix(Self.stallSize))
            let stall = stallIds.map { MarketGood(itemId: $0, price: Int.random(in: 1...6, using: &rng)) }
            let wanted = Array(stall.shuffled(using: &rng).prefix(Self.itemsPerOrder))
            orders.append(MarketOrder(wanted: wanted, stall: stall))
        }
        self.orders = orders
    }

    public var finished: Bool { index >= orders.count }
    public var current: MarketOrder? { finished ? nil : orders[index] }
    public var stars: Int { GameHelpers.stars(correct: cleanRounds, of: orders.count) }

    /// True if the picked items are exactly the list (order doesn't matter).
    public func checkBasket(_ picked: [String]) -> Bool {
        guard let o = current else { return false }
        return Set(picked) == Set(o.wanted.map(\.itemId)) && picked.count == o.wanted.count
    }

    /// True if the coins add up to the exact total.
    public func checkPayment(_ coins: [Int]) -> Bool {
        guard let o = current else { return false }
        return coins.reduce(0, +) == o.total
    }

    public mutating func noteMistake() { mistakesThisRound += 1 }

    /// Call when both basket and payment are right.
    public mutating func completeRound() {
        guard !finished else { return }
        if mistakesThisRound == 0 { cleanRounds += 1 }
        mistakesThisRound = 0
        index += 1
    }

    /// Fewest coins that make an amount (proves every total is payable).
    public static func fewestCoins(for amount: Int) -> [Int] {
        var left = amount
        var out: [Int] = []
        for c in coins.sorted(by: >) { while left >= c { out.append(c); left -= c } }
        return out
    }
}
