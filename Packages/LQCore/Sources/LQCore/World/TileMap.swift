import Foundation

public struct GridPoint: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }

    public func moved(_ d: Direction) -> GridPoint {
        switch d {
        case .up: return GridPoint(x, y - 1)
        case .down: return GridPoint(x, y + 1)
        case .left: return GridPoint(x - 1, y)
        case .right: return GridPoint(x + 1, y)
        }
    }

    public func manhattan(to o: GridPoint) -> Int { abs(x - o.x) + abs(y - o.y) }
}

public enum Direction: String, Codable, CaseIterable, Sendable { case up, down, left, right }

/// Tile kinds. Each has a legend character in text maps.
public enum Tile: Character, CaseIterable, Sendable {
    case grass = "."
    case path = ","
    case flowers = "*"
    case water = "~"
    case bridge = "="
    case tree = "T"
    case bush = "b"
    case wall = "#"
    case roof = "^"
    case door = "D"
    case fence = "f"
    case fountain = "o"
    case stall = "s"
    case sign = "!"
    case sand = ":"

    public var walkable: Bool {
        switch self {
        case .grass, .path, .flowers, .bridge, .door, .sand: return true
        default: return false
        }
    }

    public var accessibilityName: String {
        switch self {
        case .grass: return "grass"
        case .path: return "path"
        case .flowers: return "flowers"
        case .water: return "water"
        case .bridge: return "bridge"
        case .tree: return "tree"
        case .bush: return "bush"
        case .wall: return "wall"
        case .roof: return "roof"
        case .door: return "door"
        case .fence: return "fence"
        case .fountain: return "fountain"
        case .stall: return "market stall"
        case .sign: return "signpost"
        case .sand: return "sand"
        }
    }
}

public enum MapError: Error, Equatable {
    case empty
    case raggedRow(Int)
    case unknownTile(Character, row: Int)
}

/// A rectangular tile grid parsed from text (one character per tile).
public struct TileMap: Sendable {
    public let width: Int
    public let height: Int
    private let tiles: [Tile]

    public init(rows: [String]) throws {
        guard let first = rows.first, !first.isEmpty else { throw MapError.empty }
        let w = first.count
        var t: [Tile] = []
        for (r, row) in rows.enumerated() {
            guard row.count == w else { throw MapError.raggedRow(r) }
            for ch in row {
                guard let tile = Tile(rawValue: ch) else { throw MapError.unknownTile(ch, row: r) }
                t.append(tile)
            }
        }
        width = w
        height = rows.count
        tiles = t
    }

    public func contains(_ p: GridPoint) -> Bool { p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }

    public func tile(at p: GridPoint) -> Tile? { contains(p) ? tiles[p.y * width + p.x] : nil }

    public func isWalkable(_ p: GridPoint, blocked: Set<GridPoint> = []) -> Bool {
        guard let t = tile(at: p) else { return false }
        return t.walkable && !blocked.contains(p)
    }

    public func points(of kind: Tile) -> [GridPoint] {
        var out: [GridPoint] = []
        for y in 0..<height { for x in 0..<width where tiles[y * width + x] == kind { out.append(GridPoint(x, y)) } }
        return out
    }

    /// A* on 4-neighbour grid. Returns the path excluding `start`, or nil.
    /// If `goal` is not walkable (e.g. an NPC), paths to the nearest walkable neighbour.
    public func path(from start: GridPoint, to goal: GridPoint, blocked: Set<GridPoint> = [], maxNodes: Int = 4000) -> [GridPoint]? {
        guard contains(start), contains(goal) else { return nil }
        if start == goal { return [] }
        var targets: Set<GridPoint> = [goal]
        if !isWalkable(goal, blocked: blocked) {
            targets = Set(Direction.allCases.map { goal.moved($0) }.filter { isWalkable($0, blocked: blocked) })
            if targets.contains(start) { return [] }
            if targets.isEmpty { return nil }
        }
        func h(_ p: GridPoint) -> Int { targets.map { p.manhattan(to: $0) }.min() ?? 0 }

        var open: [(f: Int, g: Int, p: GridPoint)] = [(h(start), 0, start)]
        var came: [GridPoint: GridPoint] = [:]
        var gScore: [GridPoint: Int] = [start: 0]
        var expanded = 0
        while !open.isEmpty {
            // Deterministic: lowest f, then lowest h, then y, then x.
            var bi = 0
            for i in 1..<open.count {
                let a = open[i], b = open[bi]
                if (a.f, a.f - a.g, a.p.y, a.p.x) < (b.f, b.f - b.g, b.p.y, b.p.x) { bi = i }
            }
            let cur = open.remove(at: bi)
            if targets.contains(cur.p) {
                var path = [cur.p]
                var c = cur.p
                while let prev = came[c], prev != start { path.append(prev); c = prev }
                return path.reversed()
            }
            expanded += 1
            if expanded > maxNodes { return nil }
            for d in Direction.allCases {
                let n = cur.p.moved(d)
                guard isWalkable(n, blocked: blocked) else { continue }
                let g = cur.g + 1
                if g < gScore[n] ?? .max {
                    gScore[n] = g
                    came[n] = cur.p
                    open.append((g + h(n), g, n))
                }
            }
        }
        return nil
    }

    /// Every walkable tile reachable from `start`.
    public func reachable(from start: GridPoint, blocked: Set<GridPoint> = []) -> Set<GridPoint> {
        var seen: Set<GridPoint> = []
        var stack = [start]
        while let p = stack.popLast() {
            guard isWalkable(p, blocked: blocked), seen.insert(p).inserted else { continue }
            for d in Direction.allCases { stack.append(p.moved(d)) }
        }
        return seen
    }
}

/// Grid movement with collision. The scene animates between tiles; this decides
/// whether a step is allowed. Pure and deterministic, so it is unit-tested.
public struct GridMover: Sendable {
    public private(set) var position: GridPoint
    public private(set) var facing: Direction = .down

    public init(start: GridPoint) { position = start }

    /// Attempts one step. Turning toward a wall still updates facing.
    @discardableResult
    public mutating func step(_ d: Direction, on map: TileMap, blocked: Set<GridPoint>) -> Bool {
        facing = d
        let n = position.moved(d)
        guard map.isWalkable(n, blocked: blocked) else { return false }
        position = n
        return true
    }

    public var facingTile: GridPoint { position.moved(facing) }

    public mutating func teleport(to p: GridPoint) { position = p }
}
