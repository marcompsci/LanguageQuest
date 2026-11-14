import SwiftUI
import SpriteKit
import LQCore

/// Bridges the SpriteKit scene to SwiftUI state.
@MainActor
final class WorldCoordinator: ObservableObject, VillageSceneDelegate {
    struct Conversation {
        var npc: NPCSpot
        var runner: DialogueRunner
        var quest: Quest?
        var replayQuest: Quest?
        var duel: BattleOpponent?
    }

    struct Tracker: Equatable {
        var questTitle: String
        var npcName: String
        var heading: Heading
        var steps: Int
        var target: GridPoint
    }

    let scene: VillageScene
    weak var model: AppModel?
    @Published var conversation: Conversation?
    @Published var signText: PlaceSign?
    @Published var notice: String?
    @Published var actionLabel = "Look"
    @Published var tracker: Tracker?

    init(start: GridPoint) {
        scene = VillageScene(size: CGSize(width: 390, height: 600), start: start)
        scene.villageDelegate = self
    }

    private var syncedProfileId: UUID?

    func sync(from model: AppModel) {
        self.model = model
        guard let p = model.profile, let prog = model.progression else { return }
        if syncedProfileId != p.id {
            // New or switched explorer: put them where they last were.
            syncedProfileId = p.id
            let map = scene.map
            let start = p.lastPosition.flatMap { map.isWalkable($0, blocked: StarterVillage.npcPositions) ? $0 : nil } ?? StarterVillage.spawn
            scene.resetStart(start)
        }
        scene.setReducedMotion(p.settings.reducedMotion || UIAccessibility.isReduceMotionEnabled)
        scene.explorerTheme = p.theme == .explorer
        scene.setPlayer(PixelArt.avatarLook(p.avatar), showPet: p.avatar.accessory == "pet-dog")
        let offering = Set(StarterVillage.npcs.map(\.id).filter { prog.quest(offeredBy: $0, p.progress, plan: model.plan) != nil })
        scene.setQuestMarkers(offering)
        scene.setFoundTreasures(p.extrasOrEmpty.treasuresFound)
        updateTracker()
        scene.inputLocked = conversation != nil || model.sheet != nil
        refreshActionLabel()
    }

    /// Points the HUD arrow at whoever hosts the next quest.
    func updateTracker() {
        guard let model, let p = model.profile, let prog = model.progression,
              let q = prog.nextQuest(p.progress, plan: model.plan), let npc = StarterVillage.npc(q.npc) else { tracker = nil; return }
        let me = scene.playerPosition
        tracker = Tracker(questTitle: q.title, npcName: npc.name,
                          heading: QuestCompass.heading(from: me, to: npc.position),
                          steps: QuestCompass.steps(from: me, to: npc.position, map: scene.map, blocked: StarterVillage.npcPositions),
                          target: npc.position)
    }

    func refreshActionLabel() {
        if let n = scene.facingNPC { actionLabel = "Talk to \(n.name)" }
        else if scene.facingTreasure != nil { actionLabel = "Look closer" }
        else if scene.facingSign != nil { actionLabel = "Read sign" }
        else { actionLabel = "Look" }
    }

    // MARK: VillageSceneDelegate

    func scene(_ s: VillageScene, interactWithNPC npc: NPCSpot) {
        guard let model, let p = model.profile, let prog = model.progression, let lib = model.library else { return }
        if let q = prog.quest(offeredBy: npc.id, p.progress, plan: model.plan) {
            conversation = Conversation(npc: npc, runner: DialogueRunner(q.dialogue), quest: q)
        } else {
            let done = lib.allQuests.filter { $0.npc == npc.id && p.progress.completedQuests.contains($0.id) }
            if let last = done.last {
                let duel = BattleRoster.opponent(forNPC: npc.id).flatMap { BattleRoster.isUnlocked($0, progress: p.progress, progression: prog) ? $0 : nil }
                let ph = model.phrases
                var choices = [DialogueChoice(text: ph.yesPlease, gloss: "Yes, please! (practice the quest again)", next: "yes"),
                               DialogueChoice(text: ph.notNow, gloss: "Not now, thanks.", next: "no")]
                if duel != nil {
                    choices.insert(DialogueChoice(text: ph.duel, gloss: "A word duel!", next: "duel"), at: 1)
                }
                let greeting = duel.flatMap { ph.duelGreetings[$0.id] } ?? ph.letsGo
                let d = Dialogue(start: "a", nodes: [
                    DialogueNode(id: "a", speaker: npc.name, line: ph.helloAgain, gloss: "Hi again, {name}! Shall we practice?",
                                 choices: choices, next: nil, effects: nil, hint: nil),
                    DialogueNode(id: "duel", speaker: npc.name, line: greeting, gloss: duel?.greetingGloss ?? "Let's go!",
                                 choices: nil, next: nil, effects: [DialogueEffect(kind: .setFlag, value: "duel")], hint: nil),
                    DialogueNode(id: "yes", speaker: npc.name, line: ph.letsGo, gloss: "Let's go!", choices: nil, next: nil,
                                 effects: [DialogueEffect(kind: .setFlag, value: "replay")], hint: nil),
                    DialogueNode(id: "no", speaker: npc.name, line: ph.seeYou, gloss: "See you later!", choices: nil, next: nil, effects: nil, hint: nil),
                ])
                conversation = Conversation(npc: npc, runner: DialogueRunner(d), quest: nil, replayQuest: last, duel: duel)
            } else {
                let next = prog.nextQuest(p.progress, plan: model.plan)
                let tip = next.map { q in "Finish “\(q.title)” with \(StarterVillage.npc(q.npc)?.name ?? "a friend") first." } ?? "Come back soon!"
                let d = Dialogue(start: "a", nodes: [
                    DialogueNode(id: "a", speaker: npc.name, line: model.phrases.comeBackSoon, gloss: "Hi! Come back soon. (\(tip))",
                                 choices: nil, next: nil, effects: nil, hint: nil)])
                conversation = Conversation(npc: npc, runner: DialogueRunner(d), quest: nil)
            }
        }
        scene.inputLocked = true
        model.sfx(.talk)
        if let line = conversation?.runner.current?.line { model.say(line) }
    }

    func scene(_ s: VillageScene, foundTreasure t: WordTreasure) {
        guard let model else { return }
        model.updateProfile { $0.updateExtras { $0.treasuresFound.insert(t.id) } }
        model.sfx(.treasure)
        model.foundTreasure = t
        model.say(t.word(model.library?.course.targetLanguage ?? "es"))
        refreshActionLabel()
    }

    func scene(_ s: VillageScene, readSign sign: PlaceSign) {
        signText = sign
        model?.say(VText(sign.text(model?.library?.course.targetLanguage ?? "es")))
    }

    func scene(_ s: VillageScene, reachedExit exit: MapExit) {
        guard let model else { return }
        if model.progression?.isExitOpen(exit, model.profile?.progress ?? CourseProgress()) == true {
            // The lookout opens a mixed review of everything learned so far.
            notice = "From the lookout you can see \(exit.label). Warm up with a review of everything you've learned!"
            model.sheet = .review
        } else {
            notice = "The lookout opens after you finish every unit in \(model.languageName)."
        }
    }

    private var steps = 0

    func scene(_ s: VillageScene, movedTo p: GridPoint, facing: Direction) {
        steps += 1
        if steps % 2 == 0 { model?.sfx(.step) }
        refreshActionLabel()
        updateTracker()
        signText = nil
        model?.updateProfile(persist: false) { $0.lastPosition = p; $0.lastScene = StarterVillage.sceneId }
    }

    // MARK: Dialogue

    func advance() {
        guard var c = conversation else { return }
        c.runner.advance()
        finishOrUpdate(c)
    }

    func choose(_ i: Int) {
        guard var c = conversation else { return }
        c.runner.choose(i)
        finishOrUpdate(c)
    }

    private func finishOrUpdate(_ c: Conversation) {
        guard let model else { return }
        if c.runner.isFinished {
            conversation = nil
            scene.inputLocked = false
            if let q = c.quest { model.startQuest(q) }
            else if let o = c.duel, c.runner.effects.contains(where: { $0.kind == .setFlag && $0.value == "duel" }) { model.sheet = .battle(o.id) }
            else if let r = c.replayQuest, c.runner.effects.contains(where: { $0.kind == .setFlag && $0.value == "replay" }) { model.startQuest(r) }
        } else {
            conversation = c
            if c.runner.lastFeedback != nil { model.sfx(.retry) } else { model.sfx(.select) }
            if let line = c.runner.current?.line, c.runner.lastFeedback == nil { model.say(line) }
        }
    }
}

struct WorldView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var world: WorldCoordinator
    @State private var showPlaces = false

    init() {
        _world = StateObject(wrappedValue: WorldCoordinator(start: StarterVillage.spawn))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: world.scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()
                .accessibilityLabel("Starter Village map. Use the Go to button to walk to a person or place.")
            VStack(spacing: 0) {
                topBar
                if let t = world.tracker { trackerBanner(t) }
                Spacer()
                if let s = world.signText { signBubble(s) }
                if let n = world.notice { noticeBubble(n) }
                if model.stretchReminder { stretchBubble }
                controls
            }
            if let t = model.foundTreasure {
                TreasureCard(treasure: t) { model.foundTreasure = nil }
                    .transition(.scale)
            }
            if let c = world.conversation {
                DialogueOverlay(conversation: c, onAdvance: world.advance, onChoose: world.choose)
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear { world.sync(from: model); model.syncMusic() }
        .onChange(of: model.save) { _, _ in world.sync(from: model); model.syncMusic() }
        .onChange(of: model.sheet) { _, _ in world.sync(from: model) }
        .task {
            // Re-check the clock every few minutes so evening arrives on its own.
            while !Task.isCancelled {
                world.scene.setDayPhase(DayPhase.now())
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
        .confirmationDialog("Go to…", isPresented: $showPlaces, titleVisibility: .visible) {
            ForEach(StarterVillage.npcs, id: \.id) { n in
                Button("\(n.name)") { world.scene.walk(to: n.position) }
            }
            ForEach(StarterVillage.signs, id: \.spanish) { s in
                Button("\(s.english) (\(s.text(lang)))") { world.scene.walk(to: s.position) }
            }
        }
    }

    private var lang: String { model.library?.course.targetLanguage ?? "es" }

    private var topBar: some View {
        HStack(spacing: 8) {
            hudButton("house.fill", "\(model.languageName) home") { model.openHub() }
                .accessibilityIdentifier("menuButton")
            Button { model.sheet = .languages } label: {
                Text(model.courseSummaries.first(where: \.isActive)?.flag ?? "🌐").font(.title2).frame(width: 46, height: 46)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Language: \(model.languageName). Tap to switch.")
            .accessibilityIdentifier("languageButton")
            hudButton("book.closed.fill", "Quest journal") { model.sheet = .journal }
            hudButton("bag.fill", "Bag and badges") { model.sheet = .bag }
            hudButton("gamecontroller.fill", "Games") { model.sheet = .games }
                .accessibilityIdentifier("gamesButton")
            Spacer()
            if let p = model.profile {
                Label("\(p.rewards.xp) XP", systemImage: "star.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityLabel("\(p.rewards.xp) experience points")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func trackerBanner(_ t: WorldCoordinator.Tracker) -> some View {
        Button { world.scene.walk(to: t.target) } label: {
            HStack(spacing: 10) {
                Image(systemName: t.heading.symbolName).font(.title3.bold())
                    .frame(width: 34, height: 34)
                    .background(Color(model.palette.accent), in: Circle())
                    .foregroundStyle(Color(model.palette.onAccent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.questTitle).font(.subheadline.bold()).lineLimit(1)
                    Text(t.heading == .here ? "\(t.npcName) is right here. Press A!" : "Find \(t.npcName) · \(t.steps) steps").font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: "figure.walk").font(.caption)
            }
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .accessibilityLabel("Next quest: \(t.questTitle). \(t.npcName) is \(t.heading.words), \(t.steps) steps away.")
        .accessibilityHint("Walks you there")
        .accessibilityIdentifier("questTracker")
    }

    private func hudButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).frame(width: 46, height: 46)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(label)
    }

    /// The arrow pad goes on the right for left-handed play (Settings › Arrow pad on the right).
    private var controls: some View {
        HStack(alignment: .bottom) {
            if model.profile?.settings.leftHandedOn == true {
                actionButtons
                Spacer()
                DPad { world.scene.heldDirection = $0 }
            } else {
                DPad { world.scene.heldDirection = $0 }
                Spacer()
                actionButtons
            }
        }
        .padding(16)
    }

    private var actionButtons: some View {
            VStack(spacing: 10) {
                Button { showPlaces = true } label: {
                    Label("Go to", systemImage: "mappin.and.ellipse").font(.subheadline.bold())
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(.thinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("goToButton")
                Button { world.scene.interact() } label: {
                    Text("A").font(.system(size: 30, weight: .heavy, design: .rounded))
                        .frame(width: 84, height: 84)
                        .background(Color(model.palette.accent), in: Circle())
                        .foregroundStyle(Color(model.palette.onAccent))
                }
                .accessibilityLabel(world.actionLabel)
                .accessibilityIdentifier("actionButton")
            }
    }

    private func signBubble(_ s: PlaceSign) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading) {
                    Text(model.display(s.text(lang))).font(.title3.bold())
                    Text(s.english).font(.subheadline).foregroundStyle(Color(model.palette.secondaryText))
                }
                Spacer()
                SpeakerButton(text: VText(s.text(lang)))
            }
        }
        .padding(.horizontal, 16)
        .onTapGesture { world.signText = nil }
    }

    private func noticeBubble(_ n: String) -> some View {
        Card { Text(n) }
            .padding(.horizontal, 16)
            .onTapGesture { world.notice = nil }
            .task { try? await Task.sleep(nanoseconds: 4_000_000_000); world.notice = nil }
    }

    private var stretchBubble: some View {
        Card {
            HStack {
                Text("You've been exploring a while. Time for a stretch or a drink of water? 🌿")
                Button("OK") { model.stretchReminder = false }.buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
    }

}

/// Four big arrows. Hold to walk.
struct DPad: View {
    let onChange: (Direction?) -> Void
    var body: some View {
        VStack(spacing: 4) {
            arrow(.up, "chevron.up")
            HStack(spacing: 4) {
                arrow(.left, "chevron.left")
                Color.clear.frame(width: 52, height: 52)
                arrow(.right, "chevron.right")
            }
            arrow(.down, "chevron.down")
        }
    }

    private func arrow(_ d: Direction, _ icon: String) -> some View {
        Image(systemName: icon)
            .font(.title2.bold())
            .frame(width: 52, height: 52)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in onChange(d) }
                .onEnded { _ in onChange(nil) })
            .accessibilityElement()
            .accessibilityLabel("Walk \(d.rawValue)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onChange(d); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onChange(nil) } }
    }
}
