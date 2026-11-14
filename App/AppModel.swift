import SwiftUI
import LQCore

/// App-wide state. Learning logic lives in LQCore (unit-tested); this class
/// wires it to persistence, services, and navigation.
@MainActor
final class AppModel: ObservableObject {
    enum Route: Equatable { case loading, onboarding, menu, hub, world, failed(String) }

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
        case languages
        case settings
        case wardrobe
        case flashcards
        case kana
        case bonus
        case writeOut
        case trophies
        case stats
        case mistakes
        case echo
        case memory
        case bee
        case privacy
        case words
        case starredPractice
        case builder
        case quizzes
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
            case .languages: return "languages"
            case .settings: return "settings"
            case .wardrobe: return "wardrobe"
            case .flashcards: return "flashcards"
            case .kana: return "kana"
            case .bonus: return "bonus"
            case .writeOut: return "writeOut"
            case .trophies: return "trophies"
            case .stats: return "stats"
            case .mistakes: return "mistakes"
            case .echo: return "echo"
            case .memory: return "memory"
            case .bee: return "bee"
            case .privacy: return "privacy"
            case .words: return "words"
            case .starredPractice: return "starredPractice"
            case .builder: return "builder"
            case .quizzes: return "quizzes"
            }
        }
    }

    @Published var route: Route = .loading
    @Published var sheet: Sheet?
    @Published private(set) var save = FamilySave()
    @Published var toast: String?
    /// A level-up, achievement or finished challenge to celebrate (shown over everything).
    @Published var celebration: Celebration?

    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        var icon: String
        var title: String
        var detail: String
    }
    @Published var stretchReminder = false

    /// Every bundled course, by id ("en-es", "en-fr", "en-ja").
    let libraries: [String: ContentLibrary]
    private let progressions: [String: Progression]
    /// Course chosen during onboarding, before a profile exists.
    @Published var onboardingCourseId = "en-es"

    /// The active explorer's course (or the one being picked in onboarding).
    var activeCourseId: String { route == .onboarding ? onboardingCourseId : (profile?.courseId ?? onboardingCourseId) }
    var library: ContentLibrary? { libraries[activeCourseId] ?? libraries["en-es"] }
    var progression: Progression? { progressions[activeCourseId] ?? progressions["en-es"] }
    /// Short lines in the active course's language.
    var phrases: LocalPhrases { library?.phrases ?? .spanish }
    var languageName: String { library?.course.displayLanguage ?? "Spanish" }
    /// Bundled courses in menu order.
    var courses: [Course] { ContentLibrary.bundledCourseIds.compactMap { libraries[$0]?.course } }
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
    /// Release builds ignore these launch arguments entirely (no hidden modes ship).
    nonisolated static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
        #else
        false
        #endif
    }

    init() {
        storeConfig = .default
        if AppModel.isUITesting {
            saveStore = MemorySaveStore()
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            saveStore = FileSaveStore(directory: base.appendingPathComponent("LanguageQuest", isDirectory: true))
        }
        var libs: [String: ContentLibrary] = [:]
        var loadError: Error?
        for id in ContentLibrary.bundledCourseIds {
            do { libs[id] = try ContentLibrary.bundled(id) } catch { loadError = error }
        }
        libraries = libs
        progressions = libs.mapValues { Progression(library: $0) }
        if libs["en-es"] == nil {
            route = .failed("The lessons couldn't be loaded. Please reinstall the app.\n\n\(String(describing: loadError))")
            return
        }
        do {
            if let loaded = try saveStore.load() { save = loaded }
        } catch {
            // Move the unreadable file aside (kept, not deleted) so new saves can't overwrite it.
            (saveStore as? FileSaveStore)?.quarantineUnreadable()
            toast = "We couldn't open the saved progress, so we're starting fresh. The old file was kept."
        }
        if AppModel.isUITesting, ProcessInfo.processInfo.arguments.contains("-seedProfile") {
            var p = PlayerProfile(nickname: "Tester", ageBand: .age11to12, variant: "es-MX")
            p.settings.reducedMotion = true
            try? FamilyManager.addProfile(p, to: &save, config: storeConfig)
        }
        // Retention: prune every explorer's daily log at launch, not only the active one's.
        if !save.profiles.isEmpty {
            for i in save.profiles.indices { save.profiles[i].log.prune(now: Date()) }
            persist()
        }
        route = profile == nil ? .onboarding : .menu
        speech.onSpeakingChanged = { [weak self] speaking in self?.audio.voiceSpeaking = speaking }
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

    /// Main menu (pick a language) -> language page -> village.
    func openMenu() { sheet = nil; route = .menu; syncMusic() }
    func openHub() { sheet = nil; route = .hub; syncMusic() }
    /// From the main menu: switch to that language and open its page.
    func chooseLanguage(_ id: String) {
        if id != profile?.courseId { switchCourse(to: id) }
        openHub()
    }
    func play() { sheet = nil; route = .world; syncMusic() }

    var courseSummaries: [CourseSummary] {
        guard let p = profile else { return [] }
        return CourseOverview.summaries(p, libraries: libraries, order: ContentLibrary.bundledCourseIds)
    }

    func switchProfile(_ id: UUID) {
        save.activeProfileId = id
        persist()
    }

    func deleteProfile(_ id: UUID) {
        try? FamilyManager.deleteProfile(id, from: &save)
        persist()
        (saveStore as? FileSaveStore)?.purgeBackup()   // the backup still held the deleted explorer
        AppModel.removeExportFiles()
        if save.profiles.isEmpty { route = .onboarding; sheet = nil }
    }

    func deleteEverything() {
        ParentPINStore.delete()
        ReminderScheduler.removeAll()
        AppModel.removeExportFiles()
        if let fresh = try? FamilyManager.deleteEverything(store: saveStore) { save = fresh }
        sheet = nil
        route = .onboarding
    }

    /// Exported JSON files live in the temporary folder until deleted here (or by iOS).
    static func removeExportFiles() {
        let tmp = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix("LanguageQuest-export") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
        }
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
        record(.activity)
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

    func text(_ v: VText) -> String { personalize(v.text(for: profile?.variant ?? library?.course.defaultVariant ?? "es-419")) }

    /// Text for display: adds the pronunciation line (romaji, pinyin, transliteration) when the setting is on.
    func display(_ v: VText) -> String {
        let raw = v.text(for: profile?.variant ?? library?.course.defaultVariant ?? "es-419")
        guard profile?.settings.romanizationOn ?? true, let r = library?.course.romanize(raw), r != raw else { return personalize(raw) }
        return "\(personalize(raw))\n\(personalize(r))"
    }
    func display(_ s: String) -> String {
        guard profile?.settings.romanizationOn ?? true, let r = library?.course.romanize(s), r != s else { return s }
        return "\(s)\n\(r)"
    }

    /// Switches the active explorer to another language, keeping each course's progress.
    func switchCourse(to id: String) {
        guard let lib = libraries[id] else { return }
        guard id != profile?.courseId else { sheet = nil; return }
        updateProfile { $0.switchCourse(to: id, defaultVariant: lib.course.defaultVariant) }
        sheet = nil
        sfx(.reward)
        toast = "\(lib.course.variant(profile?.variant ?? "")?.flagEmoji ?? "🌐") Now learning \(lib.course.displayLanguage)!"
        syncMusic()
    }

    func say(_ v: VText) {
        guard let p = profile else { return }
        let raw = v.text(for: p.variant)
        speech.speakTarget(personalize(raw), romanized: library?.course.romanize(raw).map(personalize), variant: variant, settings: p.settings)
    }

    func readAloud(_ english: String) {
        guard let p = profile, p.settings.readAloudInstructions else { return }
        speech.speakEnglish(english, settings: p.settings)
    }

    // MARK: Session time (on device only)

    // MARK: Sound

    /// Plays a sound effect (and a matching vibration) if the explorer's settings allow it.
    func sfx(_ e: SoundEffect) {
        audio.effectsOn = profile?.settings.soundEffects ?? true
        audio.play(e)
        guard profile?.settings.soundEffects ?? true else { return }
        switch e {
        case .correct, .reward, .treasure: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .retry: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .battleHit: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .select, .coin: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .step, .talk: break
        }
    }

    // MARK: Challenges, achievements, levels

    /// Counts something the learner did, then celebrates any level, achievement or challenge it unlocked.
    func record(_ e: MetaEvent) {
        guard profile != nil else { return }
        let now = Date()
        let todays = DailyChallenge.today(now)
        let before = Set(todays.filter { c in profile.map { c.isDone($0, now: now) } ?? false }.map(\.id))
        updateProfile { $0.record(e, now: now) }
        if let p = profile, let done = todays.first(where: { $0.isDone(p, now: now) && !before.contains($0.id) && !$0.isClaimed(p, now: now) }) {
            celebrate(Celebration(icon: done.icon, title: "Challenge complete!", detail: "\(done.title). Claim +\(DailyChallenge.xp) XP on the main menu."))
        }
        checkMilestones()
    }

    /// Unlocks achievements and shows a level-up when XP crossed a level.
    func checkMilestones() {
        guard profile != nil else { return }
        var newOnes: [Achievement] = []
        let libs = libraries
        updateProfile { newOnes = Achievement.evaluate(&$0, libraries: libs) }
        for a in newOnes { celebrate(Celebration(icon: a.icon, title: "Achievement: \(a.title)", detail: a.detail)) }
        if let p = profile, let lvl = ExplorerLevel.pendingLevelUp(p) {
            updateProfile { $0.updateMeta { $0.lastLevelSeen = lvl } }
            celebrate(Celebration(icon: "arrow.up.circle.fill", title: "Level \(lvl)!", detail: "You're now a \(ExplorerLevel.title(lvl))."))
        }
    }

    private var celebrationQueue: [Celebration] = []
    func celebrate(_ c: Celebration) {
        if celebration == nil { celebration = c; sfx(.reward) } else { celebrationQueue.append(c) }
    }
    func dismissCelebration() {
        celebration = celebrationQueue.isEmpty ? nil : celebrationQueue.removeFirst()
    }

    /// Applies the music setting and picks the track for what's on screen.
    func syncMusic() {
        audio.musicOn = profile?.settings.music ?? true
        audio.musicLevel = profile?.settings.musicLevel ?? LearnerSettings.defaultMusicVolume
        audio.lessonMode = sheet != nil
        audio.setMusic(route == .world || route == .menu || route == .hub ? musicForScreen : nil)
    }

    /// Battle music for duels; each language's lesson theme (reggaeton, Paris waltz, Tokyo pop) during lessons and games; the village theme otherwise.
    private var musicForScreen: GameMusic {
        guard let sheet else { return .village }
        switch sheet {
        case .battle: return .battle
        case .quest, .review, .placement, .mastery, .scramble, .market, .flashcards, .kana, .bonus, .writeOut, .echo, .memory, .bee, .mistakes:
            return GameMusic.lessons(for: library?.course.targetLanguage ?? "es")
        case .journal, .bag, .parent, .games, .phrasebook, .languages, .settings, .wardrobe, .trophies, .stats, .privacy:
            return .village
        }
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
