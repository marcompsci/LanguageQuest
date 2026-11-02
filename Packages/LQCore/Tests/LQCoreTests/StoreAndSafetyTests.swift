import XCTest
@testable import LQCore

final class PurchaseGatingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var enabled: StoreConfig { var c = StoreConfig.default; c.paidPlansEnabled = true; return c }

    func testPaidPlansAreOffByDefault() {
        XCTAssertFalse(StoreConfig.default.paidPlansEnabled)
        let tx = VerifiedTransaction(productId: StoreConfig.default.monthlyProductId, purchaseDate: now, expirationDate: now.addingTimeInterval(86_400 * 30))
        XCTAssertEqual(EntitlementResolver.resolve([tx], config: .default, now: now).plan, .explorer)
        XCTAssertEqual(PurchaseGate.decide(config: .default, parent: ParentSettings(), gatePassedAt: now, now: now), .plansDisabled)
    }

    func testEssentialLearningIsNeverGated() {
        let essential: [Feature] = [.lessons(unitOrder: 1), .lessons(unitOrder: 3), .review, .correctionFeedback, .hints,
                                    .placementTest, .retentionChecks, .parentDashboard, .dataExportAndDeletion, .accessibilitySettings]
        for f in essential {
            XCTAssertTrue(f.isEssential)
            XCTAssertTrue(FeatureGate.isAvailable(f, plan: .explorer, config: enabled))
        }
        XCTAssertFalse(FeatureGate.isAvailable(.advancedWorld, plan: .explorer, config: enabled))
        XCTAssertTrue(FeatureGate.isAvailable(.advancedWorld, plan: .familyPlus, config: enabled))
        XCTAssertFalse(FeatureGate.isAvailable(.lessons(unitOrder: 4), plan: .explorer, config: enabled))
    }

    func testProfileSlots() throws {
        var s = FamilySave()
        for i in 0..<StoreConfig.default.maxProfilesFree {
            try FamilyManager.addProfile(PlayerProfile(nickname: "K\(i)", ageBand: .age7to9, variant: "es-MX"), to: &s, config: enabled, now: now)
        }
        XCTAssertThrowsError(try FamilyManager.addProfile(PlayerProfile(nickname: "X", ageBand: .age7to9, variant: "es-MX"), to: &s, config: enabled, now: now)) {
            XCTAssertEqual($0 as? FamilyError, .profileLimitReached(max: 2))
        }
        s.entitlement = EntitlementSnapshot()
        s.entitlement.plan = .familyPlus
        s.entitlement.expiresAt = now.addingTimeInterval(86_400)
        try FamilyManager.addProfile(PlayerProfile(nickname: "X", ageBand: .age7to9, variant: "es-MX"), to: &s, config: enabled, now: now)
        try FamilyManager.addProfile(PlayerProfile(nickname: "Y", ageBand: .age7to9, variant: "es-MX"), to: &s, config: enabled, now: now)
        XCTAssertThrowsError(try FamilyManager.addProfile(PlayerProfile(nickname: "Z", ageBand: .age7to9, variant: "es-MX"), to: &s, config: enabled, now: now))
        try FamilyManager.deleteProfile(s.profiles[0].id, from: &s)
        XCTAssertEqual(s.profiles.count, 3)
        XCTAssertEqual(s.activeProfileId, s.profiles.first?.id)
    }

    func testEntitlementValidation() {
        let c = enabled
        let month = TimeInterval(86_400 * 30)
        let good = VerifiedTransaction(productId: c.yearlyProductId, purchaseDate: now.addingTimeInterval(-100), expirationDate: now.addingTimeInterval(month), familyShared: true)
        let expired = VerifiedTransaction(productId: c.monthlyProductId, purchaseDate: now.addingTimeInterval(-2 * month), expirationDate: now.addingTimeInterval(-month))
        let revoked = VerifiedTransaction(productId: c.monthlyProductId, purchaseDate: now, expirationDate: now.addingTimeInterval(month), revocationDate: now)
        let upgraded = VerifiedTransaction(productId: c.monthlyProductId, purchaseDate: now, expirationDate: now.addingTimeInterval(month), isUpgraded: true)
        let unknown = VerifiedTransaction(productId: "com.other.app.sub", purchaseDate: now, expirationDate: now.addingTimeInterval(month))

        let s = EntitlementResolver.resolve([good], config: c, now: now)
        XCTAssertEqual(s.plan, .familyPlus)
        XCTAssertTrue(s.familyShared)
        for bad in [expired, revoked, upgraded, unknown] {
            XCTAssertEqual(EntitlementResolver.resolve([bad], config: c, now: now).plan, .explorer, bad.productId)
        }
        XCTAssertEqual(EntitlementResolver.resolve([expired, revoked, good], config: c, now: now).expiresAt, good.expirationDate)
        // Offline: cached snapshot honoured until expiry, then lapses to free (learning keeps working).
        XCTAssertEqual(EntitlementResolver.effectivePlan(s, config: c, now: now), .familyPlus)
        XCTAssertEqual(EntitlementResolver.effectivePlan(s, config: c, now: now.addingTimeInterval(month * 2)), .explorer)
        XCTAssertEqual(EntitlementResolver.effectivePlan(s, config: .default, now: now), .explorer)
    }

    func testPurchaseNeedsFreshParentGateAndParentPermission() {
        var parent = ParentSettings()
        XCTAssertEqual(PurchaseGate.decide(config: enabled, parent: parent, gatePassedAt: nil, now: now), .needsParentGate)
        XCTAssertEqual(PurchaseGate.decide(config: enabled, parent: parent, gatePassedAt: now, now: now), .purchasesNotAllowedByParent)
        parent.purchasesAllowed = true
        XCTAssertEqual(PurchaseGate.decide(config: enabled, parent: parent, gatePassedAt: now.addingTimeInterval(-30), now: now), .allowed)
        XCTAssertEqual(PurchaseGate.decide(config: enabled, parent: parent, gatePassedAt: now.addingTimeInterval(-600), now: now), .needsParentGate)
        XCTAssertEqual(PurchaseGate.decide(config: enabled, parent: parent, gatePassedAt: now.addingTimeInterval(60), now: now), .needsParentGate, "a gate time in the future is rejected")
    }
}

final class ParentalGateTests: XCTestCase {
    func testWords() {
        XCTAssertEqual(ParentalGate.words(7), "seven")
        XCTAssertEqual(ParentalGate.words(40), "forty")
        XCTAssertEqual(ParentalGate.words(47), "forty-seven")
        XCTAssertEqual(ParentalGate.words(13), "thirteen")
    }

    func testChallengesAreCorrectAndNeverShowDigits() {
        var rng = SeededRandom(seed: 42)
        for _ in 0..<500 {
            let c = ParentalGate.makeChallenge(using: &rng)
            XCTAssertFalse(c.question.contains { $0.isNumber }, c.question)
            XCTAssertGreaterThanOrEqual(c.answer, 36)
            // Re-derive the answer from words to prove it's right.
            let parts = c.question.lowercased().components(separatedBy: c.question.contains("plus") ? " plus " : " times ")
            let nums = parts.map { w in (0...99).first { ParentalGate.words($0) == w }! }
            XCTAssertEqual(c.question.contains("plus") ? nums[0] + nums[1] : nums[0] * nums[1], c.answer)
        }
    }

    func testLockoutAfterThreeWrongAnswers() {
        let c = GateChallenge(question: "Six times seven", spoken: "", answer: 42)
        var t = GateAttemptTracker()
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(t.submit("41", for: c, now: now))
        XCTAssertFalse(t.submit("abc", for: c, now: now))
        XCTAssertFalse(t.submit("40", for: c, now: now))
        XCTAssertTrue(t.isLocked(now: now))
        XCTAssertFalse(t.submit("42", for: c, now: now), "locked even with the right answer")
        let later = now.addingTimeInterval(GateAttemptTracker.lockSeconds + 1)
        XCTAssertTrue(t.submit(" 42 ", for: c, now: later))
    }
}

final class WorldTests: XCTestCase {
    func testMapParsesAndIsEnclosed() throws {
        let m = StarterVillage.map()
        XCTAssertEqual(m.width, 32)
        XCTAssertEqual(m.height, 24)
        XCTAssertThrowsError(try TileMap(rows: ["..", "."]))
        XCTAssertThrowsError(try TileMap(rows: ["?"]))
        // Only exits may be walkable on the border.
        let exits = Set(StarterVillage.exits.map(\.position))
        for x in 0..<m.width { for y in [0, m.height - 1] where !exits.contains(GridPoint(x, y)) { XCTAssertFalse(m.isWalkable(GridPoint(x, y))) } }
        for y in 0..<m.height { for x in [0, m.width - 1] where !exits.contains(GridPoint(x, y)) { XCTAssertFalse(m.isWalkable(GridPoint(x, y)), "\(x),\(y)") } }
    }

    func testEveryNPCDoorSignAndExitIsReachableFromSpawn() {
        let m = StarterVillage.map()
        let blocked = StarterVillage.npcPositions
        XCTAssertTrue(m.isWalkable(StarterVillage.spawn, blocked: blocked))
        let reach = m.reachable(from: StarterVillage.spawn, blocked: blocked)
        for n in StarterVillage.npcs {
            XCTAssertTrue(m.isWalkable(n.position), "\(n.id) stands on a walkable tile")
            XCTAssertTrue(Direction.allCases.contains { reach.contains(n.position.moved($0)) }, "\(n.id) can be reached")
        }
        for s in StarterVillage.signs {
            XCTAssertTrue(reach.contains(s.position) || Direction.allCases.contains { reach.contains(s.position.moved($0)) }, s.english)
        }
        for e in StarterVillage.exits { XCTAssertTrue(reach.contains(e.position), e.label) }
    }

    func testEveryQuestNPCIsInTheVillage() throws {
        let lib = try ContentLibrary.bundledSpanish()
        for q in lib.allQuests { XCTAssertNotNil(StarterVillage.npc(q.npc), "\(q.id) npc \(q.npc)") }
    }

    func testPathfindingAvoidsWallsAndNPCs() throws {
        let m = StarterVillage.map()
        let blocked = StarterVillage.npcPositions
        let target = try XCTUnwrap(StarterVillage.npc("don-pepe")).position
        let path = try XCTUnwrap(m.path(from: StarterVillage.spawn, to: target, blocked: blocked))
        XCTAssertFalse(path.isEmpty)
        var cur = StarterVillage.spawn
        for p in path {
            XCTAssertEqual(cur.manhattan(to: p), 1)
            XCTAssertTrue(m.isWalkable(p, blocked: blocked))
            cur = p
        }
        XCTAssertEqual(cur.manhattan(to: target), 1, "ends next to the NPC")
        XCTAssertNil(m.path(from: StarterVillage.spawn, to: GridPoint(0, 0)), "tree corner is unreachable")
        XCTAssertEqual(m.path(from: StarterVillage.spawn, to: target, blocked: blocked), path, "deterministic")
    }

    func testMoverCollides() {
        let m = StarterVillage.map()
        var mv = GridMover(start: GridPoint(1, 1))
        XCTAssertFalse(mv.step(.up, on: m, blocked: []))
        XCTAssertEqual(mv.position, GridPoint(1, 1))
        XCTAssertEqual(mv.facing, .up)
        XCTAssertTrue(mv.step(.right, on: m, blocked: []))
        XCTAssertEqual(mv.position, GridPoint(2, 1))
        XCTAssertFalse(mv.step(.down, on: m, blocked: []), "roof below")
        XCTAssertFalse(mv.step(.right, on: m, blocked: [GridPoint(3, 1)]), "NPC in the way")
    }
}

final class AccessibilityAndPrivacyTests: XCTestCase {
    func testThemeContrastMeetsWCAGAA() {
        for k in ThemeKind.allCases {
            for (name, fg, bg) in ThemePalette.of(k).textPairs {
                XCTAssertGreaterThanOrEqual(RGB.contrast(fg, bg), 4.5, "\(k) \(name)")
            }
        }
    }

    func testExportIsReadableJSONWithProfile() throws {
        let p = PlayerProfile(nickname: "Mia", ageBand: .age13to15, variant: "es-CO")
        let data = try FamilyManager.export(p)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["app"] as? String, "Language Quest")
        XCTAssertNotNil(obj["profile"])
    }

    func testPrivacyDefaults() {
        let parent = ParentSettings()
        XCTAssertFalse(parent.allowOnDeviceSpeech, "microphone is off until a grown-up allows it")
        XCTAssertFalse(parent.allowCloudSync)
        XCTAssertFalse(parent.purchasesAllowed)
        XCTAssertFalse(PrivacyNotice.dataInventory.isEmpty)
    }

    /// Offline-first and no tracking: the core library must not contain networking,
    /// analytics, or advertising code.
    func testCoreHasNoNetworkingOrTracking() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LQCore")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let banned = ["URLSession", "URLRequest", "NWConnection", "CFNetwork", "ASIdentifierManager", "advertisingIdentifier",
                      "AppTrackingTransparency", "CLLocationManager", "Firebase", "Analytics"]
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            for b in banned { XCTAssertFalse(text.contains(b), "\(f.lastPathComponent) uses \(b)") }
        }
    }

    func testContentLoadsFromLocalBundleWithoutNetwork() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Content", withExtension: nil))
        XCTAssertTrue(url.isFileURL)
        XCTAssertNoThrow(try ContentLibrary.load(from: url.appendingPathComponent("en-es")))
    }
}
