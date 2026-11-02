import SpriteKit
import LQCore

@MainActor
protocol VillageSceneDelegate: AnyObject {
    func scene(_ s: VillageScene, interactWithNPC npc: NPCSpot)
    func scene(_ s: VillageScene, readSign sign: PlaceSign)
    func scene(_ s: VillageScene, reachedExit exit: MapExit)
    func scene(_ s: VillageScene, movedTo p: GridPoint, facing: Direction)
    func scene(_ s: VillageScene, foundTreasure t: WordTreasure)
}

/// The explorable Starter Village. Movement and collision come from LQCore's
/// GridMover/TileMap; this class only draws and animates.
final class VillageScene: SKScene {
    weak var villageDelegate: VillageSceneDelegate?

    let map = StarterVillage.map()
    let tileSize: CGFloat = 48
    var reducedMotion = false
    var explorerTheme = false { didSet { tint.alpha = explorerTheme ? 0.18 : 0 } }
    /// Time-of-day wash over the village (from the device clock).
    private let dayTint = SKSpriteNode(color: .clear, size: .zero)
    private(set) var dayPhase: DayPhase = .day

    // v0.6 lighting and atmosphere.
    private let vignette = SKSpriteNode()
    private let lantern = SKSpriteNode(texture: VillageFX.softLight(128))
    private var windowGlows: [SKSpriteNode] = []
    private var weather: SKEmitterNode?

    func setDayPhase(_ phase: DayPhase) {
        dayPhase = phase
        let t = phase.tint
        dayTint.color = UIColor(red: t.color.r, green: t.color.g, blue: t.color.b, alpha: 1)
        dayTint.alpha = t.alpha
        let dark = phase == .night ? 1.0 : phase == .evening ? 0.55 : 0
        lantern.alpha = dark * 0.45
        for g in windowGlows { g.alpha = dark * 0.7 }
        refreshWeather()
    }

    /// Petals by day, fireflies after dark. Off with Reduce Motion.
    private func refreshWeather() {
        weather?.removeFromParent()
        weather = nil
        guard view != nil, !reducedMotion else { return }
        let e = VillageFX.emitter(for: dayPhase, area: size)
        e.targetNode = self
        cam.addChild(e)
        e.advanceSimulationTime(6)
        weather = e
    }
    /// Direction held on the on-screen pad (nil when released).
    var heldDirection: Direction?
    /// Set while a dialogue or lesson is open, so the player can't wander off.
    var inputLocked = false

    private(set) var mover: GridMover
    private let player = SKSpriteNode()
    private let pet = SKSpriteNode()
    private let cam = SKCameraNode()
    private let tint = SKSpriteNode(color: UIColor(red: 0.12, green: 0.15, blue: 0.35, alpha: 1), size: .zero)
    private var npcNodes: [String: SKSpriteNode] = [:]
    private var questMarkers: [String: SKLabelNode] = [:]
    private var playerLook = PixelArt.Look(skin: 0, hair: 0, hairColor: 0, outfit: 0)
    private var walkQueue: [GridPoint] = []
    private var isStepping = false
    private var waterNodes: [SKSpriteNode] = []
    private var treasureNodes: [String: SKSpriteNode] = [:]
    private var foundTreasures: Set<String> = []
    private var stepCount = 0
    private var lookRNG = SeededRandom(seed: 2026)
    private let stepDuration: TimeInterval = 0.17

    init(size: CGSize, start: GridPoint) {
        mover = GridMover(start: start)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = UIColor(red: 0.18, green: 0.42, blue: 0.24, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Places the player on a tile (restoring a saved position).
    func resetStart(_ p: GridPoint) {
        guard !isStepping, walkQueue.isEmpty else { return }
        mover = GridMover(start: p)
        player.position = point(p)
        pet.position = point(p)
        updateCamera()
    }

    func point(_ p: GridPoint) -> CGPoint {
        CGPoint(x: (CGFloat(p.x) + 0.5) * tileSize, y: (CGFloat(map.height - p.y) - 0.5) * tileSize)
    }

    func grid(_ pt: CGPoint) -> GridPoint {
        GridPoint(Int(floor(pt.x / tileSize)), map.height - 1 - Int(floor(pt.y / tileSize)))
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        view.ignoresSiblingOrder = true
        buildTiles()
        buildNPCs()
        player.size = CGSize(width: tileSize, height: tileSize)
        player.zPosition = 10
        player.position = point(mover.position)
        player.texture = PixelArt.character(playerLook, facing: .down)
        addChild(player)
        addShadow(to: player)
        buildTreasures()
        pet.size = CGSize(width: tileSize * 0.8, height: tileSize * 0.8)
        pet.zPosition = 9
        pet.texture = PixelArt.dog()
        pet.isHidden = true
        addChild(pet)
        camera = cam
        addChild(cam)
        tint.zPosition = 100
        tint.alpha = explorerTheme ? 0.18 : 0
        tint.blendMode = .alpha
        cam.addChild(tint)
        dayTint.zPosition = 99
        cam.addChild(dayTint)
        vignette.zPosition = 101
        vignette.alpha = 0.35
        cam.addChild(vignette)
        lantern.size = CGSize(width: tileSize * 5, height: tileSize * 5)
        lantern.color = UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1); lantern.colorBlendFactor = 1
        lantern.blendMode = .add; lantern.alpha = 0; lantern.zPosition = -1
        player.addChild(lantern)
        setDayPhase(dayPhase)
        updateCamera()
        startAmbient()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        tint.size = CGSize(width: size.width * 2, height: size.height * 2)
        dayTint.size = tint.size
        vignette.texture = VillageFX.vignette(size)
        vignette.size = size
        if weather != nil { refreshWeather() }
        updateCamera()
    }

    private func buildTiles() {
        var cache: [String: SKTexture] = [:]
        for y in 0..<map.height {
            for x in 0..<map.width {
                let p = GridPoint(x, y)
                guard let t = map.tile(at: p) else { continue }
                // Trees, bushes and fountains sit on grass/path: draw them with their own base.
                let variant = PixelArt.noise(x, y, 7) % 3
                let key = "\(t.rawValue)\(variant)"
                let tex = cache[key] ?? PixelArt.richTile(t, variant: variant)
                cache[key] = tex
                let n = SKSpriteNode(texture: tex, size: CGSize(width: tileSize, height: tileSize))
                n.position = point(p)
                n.zPosition = 0
                addChild(n)
                if t == .water || t == .fountain { waterNodes.append(n); n.userData = ["tile": String(t.rawValue)] }
                if t == .wall {
                    // Windows light up after dark.
                    let g = SKSpriteNode(texture: VillageFX.softLight(), size: CGSize(width: tileSize * 1.4, height: tileSize * 1.4))
                    g.color = UIColor(red: 1, green: 0.82, blue: 0.45, alpha: 1); g.colorBlendFactor = 1
                    g.blendMode = .add; g.alpha = 0; g.zPosition = 99.5
                    g.position = n.position
                    addChild(g)
                    windowGlows.append(g)
                }
            }
        }
    }

    private func buildNPCs() {
        for npc in StarterVillage.npcs {
            let n = SKSpriteNode(texture: PixelArt.character(PixelArt.npcLook(npc.id), facing: npc.facing),
                                 size: CGSize(width: tileSize, height: tileSize))
            n.position = point(npc.position)
            n.zPosition = 10
            n.name = npc.id
            addChild(n)
            addShadow(to: n)
            npcNodes[npc.id] = n
            let marker = SKLabelNode(text: "!")
            marker.fontName = "AvenirNext-Heavy"
            marker.fontSize = 26
            marker.fontColor = UIColor(red: 1, green: 0.84, blue: 0.2, alpha: 1)
            marker.position = CGPoint(x: 0, y: tileSize * 0.55)
            marker.isHidden = true
            n.addChild(marker)
            questMarkers[npc.id] = marker
        }
    }

    private func addShadow(to node: SKSpriteNode) {
        let sh = SKShapeNode(ellipseOf: CGSize(width: tileSize * 0.55, height: tileSize * 0.16))
        sh.fillColor = UIColor(white: 0, alpha: 0.22)
        sh.strokeColor = .clear
        sh.position = CGPoint(x: 0, y: -tileSize * 0.44)
        sh.zPosition = -1
        node.addChild(sh)
    }

    private func buildTreasures() {
        let tex = PixelArt.sparkle()
        for t in StarterVillage.treasures {
            let n = SKSpriteNode(texture: tex, size: CGSize(width: tileSize * 0.4, height: tileSize * 0.4))
            n.position = CGPoint(x: point(t.position).x + tileSize * 0.22, y: point(t.position).y + tileSize * 0.22)
            n.zPosition = 8
            n.isHidden = foundTreasures.contains(t.id)
            addChild(n)
            treasureNodes[t.id] = n
        }
    }

    /// Hides sparkles for treasures already found.
    func setFoundTreasures(_ ids: Set<String>) {
        foundTreasures = ids
        for (id, n) in treasureNodes { n.isHidden = ids.contains(id) }
    }

    private func startAmbient() {
        removeAction(forKey: "ambient")
        removeAction(forKey: "lookAround")
        for (_, n) in treasureNodes { n.removeAction(forKey: "twinkle"); n.alpha = 1 }
        for (_, m) in questMarkers { m.removeAction(forKey: "bounce"); m.position = CGPoint(x: 0, y: tileSize * 0.55) }
        guard !reducedMotion else { return }
        for (i, (_, n)) in treasureNodes.sorted(by: { $0.key < $1.key }).enumerated() {
            let twinkle = SKAction.sequence([.wait(forDuration: 0.3 * Double(i % 5)),
                                             .repeatForever(.sequence([.fadeAlpha(to: 0.15, duration: 0.7), .fadeAlpha(to: 1, duration: 0.7)]))])
            n.run(twinkle, withKey: "twinkle")
        }
        for (_, m) in questMarkers {
            m.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.35), .moveBy(x: 0, y: -4, duration: 0.35)])), withKey: "bounce")
        }
        // Villagers glance around now and then.
        let look = SKAction.run { [weak self] in
            guard let self, !self.inputLocked else { return }
            let npcs = StarterVillage.npcs
            let npc = npcs[Int(self.lookRNG.next() % UInt64(npcs.count))]
            let d = Direction.allCases[Int(self.lookRNG.next() % 4)]
            if let n = self.npcNodes[npc.id] {
                n.texture = PixelArt.character(PixelArt.npcLook(npc.id), facing: d)
                n.xScale = d == .left ? -1 : 1
            }
        }
        run(.repeatForever(.sequence([.wait(forDuration: 2.5, withRange: 2), look])), withKey: "lookAround")
        let water = [Tile.water, Tile.fountain]
        let f0 = Dictionary(uniqueKeysWithValues: water.map { ($0, PixelArt.tileTexture($0, frame: 0)) })
        let f1 = Dictionary(uniqueKeysWithValues: water.map { ($0, PixelArt.tileTexture($0, frame: 1)) })
        var frame = 0
        let tick = SKAction.run { [weak self] in
            guard let self else { return }
            frame ^= 1
            for n in self.waterNodes {
                guard let s = n.userData?["tile"] as? String, let ch = s.first, let t = Tile(rawValue: ch) else { continue }
                n.texture = frame == 0 ? f0[t] : f1[t]
            }
        }
        run(.repeatForever(.sequence([.wait(forDuration: 0.6), tick])), withKey: "ambient")
        for (_, n) in npcNodes {
            let bob = SKAction.sequence([.moveBy(x: 0, y: 2, duration: 0.5), .moveBy(x: 0, y: -2, duration: 0.5)])
            n.run(.repeatForever(bob), withKey: "bob")
        }
    }

    func setReducedMotion(_ on: Bool) {
        guard on != reducedMotion else { return }
        reducedMotion = on
        for (id, n) in npcNodes {
            n.removeAction(forKey: "bob")
            if let spot = StarterVillage.npc(id) { n.position = point(spot.position) }
        }
        if view != nil { startAmbient(); refreshWeather() }
    }

    func setPlayer(_ look: PixelArt.Look, showPet: Bool) {
        playerLook = look
        player.texture = PixelArt.character(look, facing: mover.facing)
        pet.isHidden = !showPet
        pet.position = point(mover.position)
    }

    func setQuestMarkers(_ ids: Set<String>) {
        for (id, m) in questMarkers { m.isHidden = !ids.contains(id) }
    }

    // MARK: Movement

    override func update(_ currentTime: TimeInterval) {
        guard !isStepping, !inputLocked else { return }
        if let d = heldDirection {
            walkQueue.removeAll()
            step(d)
        } else if let next = walkQueue.first {
            walkQueue.removeFirst()
            let d: Direction = next.x > mover.position.x ? .right : next.x < mover.position.x ? .left : next.y < mover.position.y ? .up : .down
            if !step(d) { walkQueue.removeAll() }
            if walkQueue.isEmpty { checkArrival() }
        }
    }

    private var pendingTarget: GridPoint?

    @discardableResult
    func step(_ d: Direction) -> Bool {
        let before = mover.position
        let moved = mover.step(d, on: map, blocked: StarterVillage.npcPositions)
        player.texture = PixelArt.character(playerLook, facing: d)
        player.xScale = d == .left ? -abs(player.xScale) : abs(player.xScale)
        guard moved else { return false }
        isStepping = true
        stepCount += 1
        player.texture = PixelArt.character(playerLook, facing: d, frame: 1)
        if !reducedMotion { puff(at: point(before)) }
        let dest = point(mover.position)
        let move = SKAction.move(to: dest, duration: stepDuration)
        let hop = reducedMotion ? SKAction.wait(forDuration: 0) :
            SKAction.sequence([.moveBy(x: 0, y: 3, duration: stepDuration / 2), .moveBy(x: 0, y: -3, duration: stepDuration / 2)])
        player.run(.group([move, hop])) { [weak self] in
            guard let self else { return }
            self.isStepping = false
            self.player.texture = PixelArt.character(self.playerLook, facing: self.mover.facing, frame: 0)
            self.villageDelegate?.scene(self, movedTo: self.mover.position, facing: self.mover.facing)
            if let exit = StarterVillage.exit(at: self.mover.position) { self.villageDelegate?.scene(self, reachedExit: exit) }
        }
        if !pet.isHidden { pet.run(.move(to: point(before), duration: stepDuration)) }
        updateCamera(animated: true)
        return true
    }

    private func puff(at p: CGPoint) {
        let dot = SKShapeNode(circleOfRadius: tileSize * 0.08)
        dot.fillColor = UIColor(white: 1, alpha: 0.7)
        dot.strokeColor = .clear
        dot.position = CGPoint(x: p.x, y: p.y - tileSize * 0.4)
        dot.zPosition = 5
        addChild(dot)
        dot.run(.sequence([.group([.scale(to: 2.2, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
    }

    /// Walk to a tile (tap-to-walk and the accessible "Go to" list).
    func walk(to target: GridPoint) {
        guard !inputLocked, let path = map.path(from: mover.position, to: target, blocked: StarterVillage.npcPositions) else { return }
        walkQueue = path
        pendingTarget = target
        if path.isEmpty { checkArrival() }
    }

    private func checkArrival() {
        guard let t = pendingTarget else { return }
        pendingTarget = nil
        if mover.position == t, let tr = StarterVillage.treasure(at: t) {
            revealTreasure(tr)
        } else if mover.position == t, let sign = StarterVillage.sign(at: t) {
            villageDelegate?.scene(self, readSign: sign)
        } else if mover.position.manhattan(to: t) == 1 {
            let d: Direction = t.x > mover.position.x ? .right : t.x < mover.position.x ? .left : t.y < mover.position.y ? .up : .down
            mover.step(d, on: map, blocked: StarterVillage.npcPositions.union([t]))   // turn to face
            player.texture = PixelArt.character(playerLook, facing: d)
            interact()
        }
    }

    /// The action button: talk to whoever (or read whatever) is in front of you.
    func interact() {
        guard !inputLocked else { return }
        let f = mover.facingTile
        if let npc = StarterVillage.npc(at: f) {
            faceNPC(npc)
            villageDelegate?.scene(self, interactWithNPC: npc)
        } else if let tr = StarterVillage.treasure(at: f) ?? StarterVillage.treasure(at: mover.position), !foundTreasures.contains(tr.id) {
            revealTreasure(tr)
        } else if let sign = StarterVillage.sign(at: f) ?? StarterVillage.sign(at: mover.position) {
            villageDelegate?.scene(self, readSign: sign)
        }
    }

    private func revealTreasure(_ t: WordTreasure) {
        guard !foundTreasures.contains(t.id) else { return }
        foundTreasures.insert(t.id)
        if let n = treasureNodes[t.id] {
            n.removeAllActions()
            if reducedMotion { n.isHidden = true } else {
                n.run(.sequence([.group([.scale(to: 3, duration: 0.4), .fadeOut(withDuration: 0.4)]), .hide()]))
            }
        }
        villageDelegate?.scene(self, foundTreasure: t)
    }

    /// What the action button would do now, for its label.
    var facingNPC: NPCSpot? { StarterVillage.npc(at: mover.facingTile) }
    var facingSign: PlaceSign? { StarterVillage.sign(at: mover.facingTile) }
    var facingTreasure: WordTreasure? {
        guard let t = StarterVillage.treasure(at: mover.facingTile) ?? StarterVillage.treasure(at: mover.position),
              !foundTreasures.contains(t.id) else { return nil }
        return t
    }
    var playerPosition: GridPoint { mover.position }

    private func faceNPC(_ npc: NPCSpot) {
        let opposite: [Direction: Direction] = [.up: .down, .down: .up, .left: .right, .right: .left]
        if let n = npcNodes[npc.id], let d = opposite[mover.facing] {
            n.texture = PixelArt.character(PixelArt.npcLook(npc.id), facing: d)
            n.xScale = d == .left ? -1 : 1
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let target = grid(t.location(in: self))
        guard map.contains(target) else { return }
        walk(to: target)
    }

    private func updateCamera(animated: Bool = false) {
        let p = point(mover.position)
        let halfW = size.width / 2, halfH = size.height / 2
        let mapW = CGFloat(map.width) * tileSize, mapH = CGFloat(map.height) * tileSize
        let x = mapW <= size.width ? mapW / 2 : min(max(p.x, halfW), mapW - halfW)
        let y = mapH <= size.height ? mapH / 2 : min(max(p.y, halfH), mapH - halfH)
        let dest = CGPoint(x: x, y: y)
        if animated && !reducedMotion { cam.run(.move(to: dest, duration: stepDuration)) } else { cam.position = dest }
    }
}
