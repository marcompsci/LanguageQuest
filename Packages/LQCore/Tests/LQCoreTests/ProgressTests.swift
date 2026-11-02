import XCTest
@testable import LQCore

final class SaveLoadTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lq-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func sampleSave() -> FamilySave {
        var s = FamilySave()
        var p = PlayerProfile(nickname: "Ana", ageBand: .age10to12, avatar: AvatarConfig(body: 2, hair: 1, hairColor: 3, outfit: 4, hat: "cap-red"),
                              variant: "es-AR", now: t0)
        p.progress.completedQuests = ["u1-q1"]
        p.progress.completedActivities["u1-q1-a1"] = ActivityRecord(firstTryCorrect: true, bestAttempts: 1, completions: 1, lastCompleted: t0)
        var k = ItemKnowledge(now: t0)
        k.record(.init(correct: true), track: .comprehension, now: t0)
        p.knowledge["hola"] = k
        p.rewards.xp = 45
        p.rewards.ownedCosmetics = ["scarf-yellow"]
        p.assessments = [AssessmentResult(kind: .baseline, date: t0, unitId: nil, bySkill: [.reading: SkillScore(correct: 3, total: 4)], passed: nil)]
        p.lastPosition = GridPoint(5, 6)
        s.profiles = [p]
        s.activeProfileId = p.id
        s.parent.setupCompleted = true
        return s
    }

    func testFileRoundTrip() throws {
        let store = FileSaveStore(directory: dir)
        XCTAssertNil(try store.load())
        let s = sampleSave()
        try store.save(s)
        XCTAssertEqual(try store.load(), s)
    }

    func testMemoryRoundTrip() throws {
        let store = MemorySaveStore()
        let s = sampleSave()
        try store.save(s)
        XCTAssertEqual(try store.load(), s)
    }

    func testCorruptMainFallsBackToBackup() throws {
        let store = FileSaveStore(directory: dir)
        var s = sampleSave()
        try store.save(s)          // v1 written
        s.profiles[0].rewards.xp = 99
        try store.save(s)          // backup = first save, main = second
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("family.json"))
        let loaded = try XCTUnwrap(try store.load())
        XCTAssertEqual(loaded.profiles[0].rewards.xp, 45, "falls back to the last good save")
    }

    func testCorruptWithNoBackupThrows() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("family.json"))
        XCTAssertThrowsError(try FileSaveStore(directory: dir).load())
    }

    func testFutureVersionIsNotSilentlyDiscarded() throws {
        let store = MemorySaveStore()
        store.setRaw(Data(#"{"version": 99, "savedAt": "2027-01-01T00:00:00Z"}"#.utf8))
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? SaveError, .unsupportedVersion(99)) }
    }

    func testMigratesV1SingleProfileSave() throws {
        let p = sampleSave().profiles[0]
        struct V1: Encodable { var version = 1; var savedAt: Date; var profile: PlayerProfile }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let store = MemorySaveStore()
        store.setRaw(try e.encode(V1(savedAt: t0, profile: p)))
        let s = try XCTUnwrap(try store.load())
        XCTAssertEqual(s.profiles, [p])
        XCTAssertEqual(s.activeProfileId, p.id)
        XCTAssertFalse(s.parent.setupCompleted)
        XCTAssertEqual(s.entitlement.plan, .explorer)
    }

    func testDeleteAll() throws {
        let store = FileSaveStore(directory: dir)
        try store.save(sampleSave())
        try store.save(sampleSave())
        let fresh = try FamilyManager.deleteEverything(store: store)
        XCTAssertTrue(fresh.profiles.isEmpty)
        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("family.backup.json").path))
    }

    func testSaveContainsNoBirthdateEmailOrLocation() throws {
        let store = MemorySaveStore()
        try store.save(sampleSave())
        let json = String(decoding: try XCTUnwrap(store.data), as: UTF8.self).lowercased()
        for key in ["birth", "email", "phone", "latitude", "longitude", "address", "idfa", "deviceid"] {
            XCTAssertFalse(json.contains("\"\(key)"), key)
        }
    }
}

final class ProgressionTests: XCTestCase {
    var lib: ContentLibrary!
    var prog: Progression!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    override func setUpWithError() throws {
        lib = try ContentLibrary.bundledSpanish()
        prog = Progression(library: lib)
    }
    func newProfile() -> PlayerProfile { PlayerProfile(nickname: "Leo", ageBand: .age7to9, variant: "es-MX", now: t0) }

    func testOnlyFirstQuestIsOpenAtStart() {
        let p = newProfile()
        let u1 = lib.units[0]
        XCTAssertEqual(prog.status(of: u1.quests[0], in: u1, p.progress, plan: .explorer), .available)
        XCTAssertEqual(prog.status(of: u1.quests[1], in: u1, p.progress, plan: .explorer), .locked)
        XCTAssertFalse(prog.isUnitUnlocked(lib.units[1], p.progress, plan: .explorer))
        XCTAssertEqual(prog.nextQuest(p.progress, plan: .explorer)?.id, "u1-q1")
        XCTAssertEqual(prog.quest(offeredBy: "luna", p.progress, plan: .explorer)?.id, "u1-q1")
        XCTAssertNil(prog.quest(offeredBy: "mateo", p.progress, plan: .explorer))
    }

    func testCompletingAllActivitiesCompletesQuestAndGivesRewardsOnce() throws {
        var p = newProfile()
        let q = lib.units[0].quests[0]
        var last: ActivityCompletion?
        for a in q.activities { last = prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) }
        XCTAssertEqual(last?.questCompleted, q.id)
        XCTAssertEqual(last?.cosmeticUnlocked, q.reward.cosmetic)
        XCTAssertTrue(p.progress.completedQuests.contains(q.id))
        let expectedXP = q.activities.count * (Progression.xpFirstCompletion + Progression.xpFirstTryBonus) + q.reward.xp
        XCTAssertEqual(p.rewards.xp, expectedXP)
        // Replay: small XP, no duplicate reward.
        let replay = prog.complete(activity: q.activities[0], outcome: .init(correct: true), profile: &p, now: t0)
        XCTAssertEqual(replay.xpGained, Progression.xpReplay)
        XCTAssertNil(replay.questCompleted)
        XCTAssertEqual(p.rewards.xp, expectedXP + Progression.xpReplay)
        XCTAssertEqual(prog.status(of: lib.units[0].quests[1], in: lib.units[0], p.progress, plan: .explorer), .available)
    }

    func testMistakesNeverRemoveXPOrProgress() {
        var p = newProfile()
        let a = lib.units[0].quests[0].activities[0]
        prog.complete(activity: a, outcome: .init(correct: true, attempts: 4, usedHint: true), profile: &p, now: t0)
        XCTAssertEqual(p.rewards.xp, Progression.xpFirstCompletion)
        XCTAssertNotNil(p.progress.completedActivities[a.id])
        XCTAssertFalse(p.progress.completedActivities[a.id]!.firstTryCorrect)
    }

    func testFinishingUnitOneOpensUnitTwoAndExitAfterUnitThree() {
        var p = newProfile()
        for q in lib.units[0].quests { for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) } }
        XCTAssertTrue(prog.isUnitUnlocked(lib.units[1], p.progress, plan: .explorer))
        XCTAssertTrue(p.rewards.badges.contains("badge-u1"))
        let exit = StarterVillage.exits[0]
        XCTAssertFalse(prog.isExitOpen(exit, p.progress))
        for u in lib.units.dropFirst() { for q in u.quests { for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) } } }
        XCTAssertTrue(prog.isExitOpen(exit, p.progress))
        XCTAssertNil(prog.nextQuest(p.progress, plan: .explorer))
        XCTAssertEqual(p.progress.completedQuests.count, 15)
    }

    func testAllFreeUnitsAvailableWithoutPurchase() {
        for u in lib.units { XCTAssertTrue(FeatureGate.isAvailable(.lessons(unitOrder: u.order), plan: .explorer)) }
    }

    func testEveryQuestRewardExistsInCatalog() {
        for q in lib.allQuests {
            if let c = q.reward.cosmetic { XCTAssertNotNil(Catalog.cosmetic(c), c); XCTAssertFalse(Catalog.cosmetic(c)!.plusOnly, c) }
            if let b = q.reward.badge { XCTAssertNotNil(Catalog.badge(b), b) }
        }
        for u in lib.units { XCTAssertNotNil(Catalog.badge(Catalog.masteryBadge(forUnitOrder: u.order))) }
    }

    func testActivityLogPruning() {
        var log = ActivityLog()
        let cal = Calendar(identifier: .gregorian)
        log.minutesByDay[ActivityLog.dayKey(t0, calendar: cal)] = 10
        log.minutesByDay[ActivityLog.dayKey(t0.addingTimeInterval(-90 * 86_400), calendar: cal)] = 5
        log.prune(now: t0, calendar: cal)
        XCTAssertEqual(log.minutesByDay.count, 1)
    }

    func testNicknameSanitizing() {
        XCTAssertEqual(PlayerProfile.sanitizeNickname("  Ana  María  "), "Ana María")
        XCTAssertEqual(PlayerProfile.sanitizeNickname("bob@mail.com 555-1234"), "bobmailcom -")
        XCTAssertLessThanOrEqual(PlayerProfile.sanitizeNickname(String(repeating: "a", count: 50)).count, PlayerProfile.maxNicknameLength)
    }

    func testAgeBandSetsPresentationNotProficiency() {
        let young = PlayerProfile(nickname: "", ageBand: .age7to9, variant: "es-MX")
        let teen = PlayerProfile(nickname: "", ageBand: .age16plus, variant: "es-MX")
        XCTAssertEqual(young.theme, .playful)
        XCTAssertEqual(teen.theme, .explorer)
        XCTAssertTrue(young.settings.readAloudInstructions)
        XCTAssertEqual(young.progress, teen.progress)
    }
}
