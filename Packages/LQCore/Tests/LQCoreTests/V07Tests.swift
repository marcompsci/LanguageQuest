import XCTest
@testable import LQCore

final class V07Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    func testLevels() {
        XCTAssertEqual(ExplorerLevel.level(forXP: 0), 1)
        XCTAssertEqual(ExplorerLevel.level(forXP: 99), 1)
        XCTAssertEqual(ExplorerLevel.level(forXP: 100), 2)
        XCTAssertEqual(ExplorerLevel.level(forXP: 250), 3)
        XCTAssertEqual(ExplorerLevel.progress(forXP: 120).into, 20)
        XCTAssertEqual(ExplorerLevel.progress(forXP: 120).needed, 150)
        XCTAssertEqual(ExplorerLevel.title(1), "Newcomer")
        XCTAssertEqual(ExplorerLevel.title(99), "Legend")
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        XCTAssertNil(ExplorerLevel.pendingLevelUp(p))
        p.rewards.xp = 260
        XCTAssertEqual(ExplorerLevel.pendingLevelUp(p), 3)
        p.updateMeta { $0.lastLevelSeen = 3 }
        XCTAssertNil(ExplorerLevel.pendingLevelUp(p))
    }

    func testDailyChallengesResetAndPayOnce() {
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        let today = DailyChallenge.today(t0)
        XCTAssertEqual(today.count, 3)
        XCTAssertEqual(Set(today.map(\.id)).count, 3)
        XCTAssertEqual(DailyChallenge.today(t0.addingTimeInterval(3600)).map(\.id), today.map(\.id), "same all day")
        for c in today {
            XCTAssertFalse(c.isDone(p, now: t0))
            XCTAssertEqual(c.claim(&p, now: t0), 0, "can't claim before done")
            for _ in 0..<c.goal { p.record(c.event, now: t0) }
            XCTAssertTrue(c.isDone(p, now: t0))
            XCTAssertEqual(c.claim(&p, now: t0), DailyChallenge.xp)
            XCTAssertEqual(c.claim(&p, now: t0), 0, "once")
        }
        XCTAssertEqual(p.rewards.xp, DailyChallenge.xp * 3)
        XCTAssertEqual(p.metaOrEmpty.counters["allChallengesDone"], 1)
        let tomorrow = t0.addingTimeInterval(86400 * 2)
        for c in DailyChallenge.today(tomorrow) { XCTAssertEqual(c.count(p, now: tomorrow), 0, "fresh start, nothing lost") }
        // Lifetime counters survive the reset.
        p.record(.activity, now: tomorrow)
        XCTAssertGreaterThanOrEqual(p.metaOrEmpty.counters["activity"] ?? 0, 1)
    }

    func testAchievements() throws {
        let libs = Dictionary(uniqueKeysWithValues: try ContentLibrary.bundledCourseIds.map { ($0, try ContentLibrary.bundled($0)) })
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: "en-de", variant: "de-DE")
        XCTAssertTrue(Achievement.evaluate(&p, libraries: libs).isEmpty)
        let de = libs["en-de"]!
        let prog = Progression(library: de)
        for q in de.allQuests { for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) } }
        let got = Set(Achievement.evaluate(&p, libraries: libs, now: t0).map(\.id))
        XCTAssertTrue(got.isSuperset(of: ["a-first-quest", "a-unit"]), "\(got)")
        XCTAssertTrue(Achievement.evaluate(&p, libraries: libs).isEmpty, "unlocks once")
        p.switchCourse(to: "en-it", defaultVariant: "it-IT")
        p.switchCourse(to: "en-zh", defaultVariant: "zh-CN")
        for _ in 0..<10 { p.record(.wordWritten, now: t0) }
        p.record(.speedDuelWon, now: t0)
        let more = Set(Achievement.evaluate(&p, libraries: libs, now: t0).map(\.id))
        XCTAssertTrue(more.isSuperset(of: ["a-three-langs", "a-scribe", "a-speedster"]), "\(more)")
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
        let back = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.metaOrEmpty.achievements.count, p.metaOrEmpty.achievements.count)
    }

    func testMiniGamesInEveryCourse() throws {
        for id in ContentLibrary.bundledCourseIds {
            let lib = try ContentLibrary.bundled(id)
            let v = lib.course.defaultVariant
            let p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: id, variant: v)
            var echo = EchoGame(profile: p, library: lib, seed: 9)
            XCTAssertEqual(echo.questions.count, EchoGame.rounds, id)
            for q in echo.questions {
                XCTAssertEqual(q.options.count, 4, id)
                XCTAssertEqual(Set(q.options.map { AnswerChecker.normalize($0.text(for: v)) }).count, 4, "\(id) \(q.itemId)")
                XCTAssertEqual(q.options[q.answerIndex], q.spoken)
            }
            while let q = echo.current { echo.answer(q.answerIndex) }
            XCTAssertEqual(echo.stars, 3)

            var mm = MemoryMatch(profile: p, library: lib, seed: 4)
            XCTAssertEqual(mm.cards.count, MemoryMatch.pairs * 2, id)
            // Perfect play: flip each pair together.
            for pair in Set(mm.cards.map(\.pairId)) {
                let ids = mm.cards.filter { $0.pairId == pair }.map(\.id)
                XCTAssertEqual(mm.flip(ids[0]), .first)
                XCTAssertEqual(mm.flip(ids[1]), .match)
            }
            XCTAssertTrue(mm.finished)
            XCTAssertEqual(mm.stars, 3)

            var bee = SpellingBee(profile: p, library: lib, seed: 2)
            XCTAssertEqual(bee.words.count, SpellingBee.rounds, id)
            while let w = bee.current {
                let typed = lib.course.romanize(w.target.text(for: v)) ?? w.target.text(for: v)
                XCTAssertTrue(bee.submit(typed, variant: v, library: lib).isCorrect, "\(id) \(typed)")
            }
            XCTAssertEqual(bee.stars, 3)
        }
    }

    func testMemoryMatchMismatchAndIgnores() throws {
        let lib = try ContentLibrary.bundled("en-es")
        let p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        var mm = MemoryMatch(profile: p, library: lib, seed: 1)
        let a = mm.cards[0]
        let wrong = try XCTUnwrap(mm.cards.first { $0.pairId != a.pairId })
        XCTAssertEqual(mm.flip(a.id), .first)
        XCTAssertEqual(mm.flip(a.id), .ignored, "same card twice")
        XCTAssertEqual(mm.flip(wrong.id), .mismatch)
        XCTAssertEqual(mm.moves, 1)
        let partner = try XCTUnwrap(mm.cards.first { $0.pairId == a.pairId && $0.id != a.id })
        XCTAssertEqual(mm.flip(partner.id), .first, "third flip turns the mismatch back down")
        XCTAssertEqual(mm.flip(a.id), .match)
        XCTAssertEqual(mm.flip(a.id), .ignored, "matched cards stay put")
    }

    func testMistakesNotebookAndStats() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        PracticeRecorder.record(itemId: "hola", outcome: .init(correct: true), track: .comprehension, profile: &p, now: t0)
        PracticeRecorder.record(itemId: "gracias", outcome: .init(correct: false), track: .comprehension, profile: &p, now: t0)
        PracticeRecorder.record(itemId: "gracias", outcome: .init(correct: false), track: .comprehension, profile: &p, now: t0)
        PracticeRecorder.record(itemId: "adios", outcome: .init(correct: false), track: .comprehension, profile: &p, now: t0)
        let m = MistakesNotebook.entries(p, library: lib)
        XCTAssertEqual(m.map(\.itemId), ["gracias", "adios"])
        let s = PlayerStats.languages(p, libraries: ["en-es": lib])
        XCTAssertEqual(s.first?.total, 3)
        let week = PlayerStats.lastWeek(p, now: t0)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.activities, 4)
    }

    func testOlderSavesDecodeWithoutMeta() throws {
        let p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        json.removeValue(forKey: "meta")
        var settings = json["settings"] as! [String: Any]
        settings.removeValue(forKey: "easyRead")
        json["settings"] = settings
        let back = try JSONDecoder().decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.meta)
        XCTAssertFalse(back.settings.easyReadOn)
    }
}

final class MemoryHideTests: XCTestCase {
    func testHideMismatch() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var mm = MemoryMatch(profile: PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX"), library: lib, seed: 1)
        let a = mm.cards[0]; let b = try XCTUnwrap(mm.cards.first { $0.pairId != a.pairId })
        _ = mm.flip(a.id); _ = mm.flip(b.id)
        mm.hideMismatch()
        XCTAssertFalse(mm.isFaceUp(a.id)); XCTAssertFalse(mm.isFaceUp(b.id))
    }
}
