import SwiftUI
import LQCore

/// App-wide state. Learning logic lives in LQCore (unit-tested); this class
/// wires it to persistence, services, and navigation.
@MainActor
final class AppModel: ObservableObject {
    enum Route: Equatable { case loading, onboarding, world, failed(String) }

    enum Sheet: Identifiable, Equatable {
        case quest(String)
        case journal
        case bag
        case review
        case placement
        case mastery(String)
        case parent
        case games
        case battle(String)
        case scramble
        case market
        case phrasebook
        var id: String {
            switch self {
            case .quest(let q): return "quest-\(q)"
            case .journal: return "journal"
            case .bag: return "bag"
            case .review: return "review"
            case .placement: return "placement"
            case .mastery(let u): return "mastery-\(u)"
            case .parent: return "parent"
            case .games: return "games"
            case .battle(let o): return "battle-\(o)"
            case .scramble: return "scramble"
            case .market: return "market"
            case .phrasebook: return "phrasebook"
            }
        }
    }

    @Published var route: Route = .loading
    @Published var sheet: Sheet?
    @Published private(set) var save = FamilySave()
    @Published var toast: String?
    @Published var stretchReminder = false

    let library: ContentLibrary?
    let progression: Progression?
    let storeConfig: StoreConfig
    let speech = SpeechService()
    let audio = AudioService()
    /// A word treasure just found (shown as a card over the map).
    @Published var foundTreasure: WordTreasure?
    lazy var store = StoreService(config: storeConfig)
    private let saveStore: SaveStore
    private var sessionStart: Date?
    private var reminderTask: Task<Void, Never>?

    /// UI tests launch with "-uiTesting" to use an in-memory save.
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    init() {
        storeConfig = .default
        if AppModel.isUITesting {
            saveStore = MemorySaveStore()
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            saveStore = FileSaveStore(directory: base.appendingPathComponent("LanguageQuest", isDirectory: true))
        }
        do {
            let lib = try ContentLibrary.bundledSpanish()
            library = lib
            progression = Progression(library: lib)
        } catch {
            library = nil
            progression = nil
            route = .failed("The lessons couldn't be loaded. Please reinstall the app.\n\n\(error)")
            return
        }
        do {
            if let loaded = try saveStore.load() { save = loaded }
        } catch {
            // Keep the unreadable file untouched; start fresh in memory and tell the grown-up.
            toast = "We couldn't open the saved progress, so we're starting fresh."
        }
        if AppModel.isUITesting, ProcessInfo.processInfo.arguments.contains("-seedProfile") {
            var p = PlayerProfile(nickname: "Tester", ageBand: .age10to12, variant: "es-MX")
            p.settings.reducedMotion = true
            try? FamilyManager.addProfile(p, to: &save, config: storeConfig)
        }
        route = profile == nil ? .onboarding : .world
    }

    // MARK: Profile

    var profile: PlayerProfile? { save.activeProfile }

    func updateProfile(persist shouldPersist: Bool = true, _ change: (inout PlayerProfile) -> Void) {
        guard var p = save.activeProfile else { return }
        change(&p)
        save.activeProfile = p
        if shouldPersist { persist() }
    }

    func updateParent(_ change: (inout ParentSettings) -> Void) {
        change(&save.parent)
        persist()
    }

    var plan: Plan { EntitlementResolver.effectivePlan(save.entitlement, config: storeConfig, now: Date()) }

    var variant: LanguageVariant? {
        guard let lib = library, let p = profile else { return nil }
        return lib.course.variant(p.variant) ?? lib.course.variant(lib.course.defaultVariant)
    }

    var palette: ThemePalette { ThemePalette.of(profile?.theme ?? .playful) }

    func variantName(_ id: String) -> String { library?.course.variant(id)?.name ?? id }

    func createProfile(_ p: PlayerProfile) throws {
        try FamilyManager.addProfile(p, to: &save, config: storeConfig)
        save.activeProfileId = p.id
        persist()
        route = .world
    }

    func switchProfile(_ id: UUID) {
        save.activeProfileId = id
        persist()
    }

    func deleteProfile(_ id: UUID) {
        try? FamilyManager.deleteProfile(id, from: &save)
        persist()
        if save.profiles.isEmpty { route = .onboarding; sheet = nil }
    }

    func deleteEverything() {
        if let fresh = try? FamilyManager.deleteEverything(store: saveStore) { save = fresh }
        sheet = nil
        route = .onboarding
    }

    func addNewProfileFlow() {
        sheet = nil
        route = .onboarding
    }

    func persist() {
        do { try saveStore.save(save) } catch { toast = "Couldn't save progress right now." }
    }

    // MARK: Learning

    /// Records a finished activity. A self-checked spoken answer (`verified == false`)
    /// can't prove spontaneous use, so it is recorded as guided practice.
    @discardableResult
    func complete(_ a: Activity, outcome: ReviewOutcome, verified: Bool = true) -> ActivityCompletion? {
        guard let prog = progression, var p = profile else { return nil }
        var act = a
        if !verified { act.practice = .guided }
        let r = prog.complete(activity: act, outcome: outcome, profile: &p, now: Date())
        save.activeProfile = p
        persist()
        return r
    }

    func startQuest(_ q: Quest) {
        guard let prog = progression else { return }
        updateProfile { prog.start(q, profile: &$0) }
        sheet = .quest(q.id)
    }

    /// Replaces {name} in authored dialogue with the nickname (or a neutral default).
    func personalize(_ s: String) -> String {
        let n = profile?.nickname.isEmpty == false ? profile!.nickname : "Alex"
        return s.replacingOccurrences(of: "{name}", with: n)
    }

    func text(_ v: VText) -> String { personalize(v.text(for: profile?.variant ?? "es-419")) }

    func say(_ v: VText) {
        guard let p = profile else { return }
        speech.speakSpanish(text(v), variant: variant, settings: p.settings)
    }

    func readAloud(_ english: String) {
        guard let p = profile, p.settings.readAloudInstructions else { return }
        speech.speakEnglish(english, settings: p.settings)
    }

    // MARK: Session time (on device only)

    // MARK: Sound

    /// Plays a sound effect if the explorer's settings allow it.
    func sfx(_ e: SoundEffect) {
        audio.effectsOn = profile?.settings.soundEffects ?? true
        audio.play(e)
    }

    /// Applies the music setting and picks the track for what's on screen.
    func syncMusic() {
        audio.musicOn = profile?.settings.music ?? true
        let battle: Bool
        if case .battle = sheet { battle = true } else { battle = false }
        audio.setMusic(route == .world ? (battle ? .battle : .village) : nil)
    }

    func sessionBegan() {
        audio.resume()
        syncMusic()
        sessionStart = Date()
        stretchReminder = false
        reminderTask?.cancel()
        guard let mins = profile?.settings.sessionReminderMinutes else { return }
        reminderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(mins) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stretchReminder = true }
        }
    }

    func sessionEnded() {
        audio.suspend()
        reminderTask?.cancel()
        persist()   // position changes are saved lazily
        guard let start = sessionStart else { return }
        sessionStart = nil
        let minutes = Date().timeIntervalSince(start) / 60
        guard minutes > 0.05 else { return }
        updateProfile { p in
            p.log.minutesByDay[ActivityLog.dayKey(Date()), default: 0] += minutes
            p.log.prune(now: Date())
        }
    }

    // MARK: Store

    func refreshEntitlements() async {
        let txs = await store.currentVerifiedTransactions()
        save.entitlement = EntitlementResolver.resolve(txs, config: storeConfig, now: Date())
        persist()
    }
}
