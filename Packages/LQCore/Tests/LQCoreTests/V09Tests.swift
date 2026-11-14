import XCTest
@testable import LQCore

final class V09Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    func libs() throws -> [String: ContentLibrary] {
        Dictionary(uniqueKeysWithValues: try ContentLibrary.bundledCourseIds.map { ($0, try ContentLibrary.bundled($0)) })
    }
    func learner(_ lib: ContentLibrary) -> PlayerProfile {
        PlayerProfile(nickname: "", ageBand: .age13to15, courseId: lib.course.id, variant: lib.course.defaultVariant, now: t0)
    }

    // 1
    func testListenAndTypeAcceptsTheWordInEveryLanguage() throws {
        for (id, lib) in try libs() {
            var p = learner(lib)
            var g = ListenTypeGame(profile: p, library: lib, seed: 5)
            XCTAssertGreaterThanOrEqual(g.items.count, 5, id)
            let v = p.variant(for: lib)
            while let item = g.current { g.submit(item.target.text(for: v), variant: v, context: lib.checkContext) }
            XCTAssertEqual(g.correct, g.items.count, "\(id): typing the word itself is right")
            ListenTypeGame.finish(g, profile: &p)
            XCTAssertEqual(p.extrasOrEmpty.listenBest, g.correct)
        }
        let lib = try ContentLibrary.bundled("en-es")
        var g = ListenTypeGame(profile: learner(lib), library: lib, seed: 1)
        let v = lib.course.defaultVariant
        XCTAssertFalse(g.submit("zzzz", variant: v, context: lib.checkContext).isCorrect)
        XCTAssertEqual(g.missed.count, 1)
    }

    // 2
    func testRightOrWrongMixesAndScores() throws {
        let l = try libs()
        for (id, lib) in l {
            var p = learner(lib)
            var g = RightOrWrongGame(profile: p, library: lib, seed: 8)
            XCTAssertEqual(g.rounds.count, RightOrWrongGame.rounds, id)
            XCTAssertTrue(g.rounds.contains { $0.isRight } && g.rounds.contains { !$0.isRight }, "\(id) both kinds")
            for r in g.rounds where !r.isRight { XCTAssertNotEqual(AnswerChecker.normalize(r.shownMeaning), AnswerChecker.normalize(r.realMeaning)) }
            while let r = g.current { g.answer(saysRight: r.isRight) }
            XCTAssertEqual(g.correct, 10)
            RightOrWrongGame.finish(g, profile: &p)
            XCTAssertTrue(Achievement.evaluate(&p, libraries: l, now: t0).contains { $0.id == "a-sharp" }, id)
        }
    }

    // 3
    func testSlowSpeechOnlyChangesRate() {
        var s = LearnerSettings(); s.voiceVolume = 0.6
        let slow = SlowSpeech.settings(s)
        XCTAssertEqual(slow.speechRate, 0.3)
        XCTAssertEqual(slow.voiceVolume, 0.6)
    }

    // 4
    func testUnitMapCountsQuestsWordsAndQuiz() throws {
        let lib = try ContentLibrary.bundled("en-fr")
        var p = learner(lib)
        let u = lib.units[0]
        p.progress.completedQuests.insert(u.quests[0].id)
        let item = u.allItems[0]
        for _ in 0..<6 { PracticeRecorder.record(itemId: item.id, outcome: ReviewOutcome(correct: true), track: .comprehension, profile: &p, now: t0) }
        p.updateExtras { $0.quizBest = [u.id: 70] }
        let map = UnitMap.units(p, library: lib, progression: Progression(library: lib), plan: .explorer)
        XCTAssertEqual(map.count, lib.units.count)
        XCTAssertEqual(map[0].questsDone, 1)
        XCTAssertEqual(map[0].wordsMet, 1)
        XCTAssertEqual(map[0].quizBest, 70)
        XCTAssertTrue(map[0].unlocked)
        XCTAssertGreaterThan(map[0].fractionDone, 0)
    }

    // 5
    func testReviewForecast() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let ids = lib.allItems.prefix(3).map(\.id)
        for id in ids { PracticeRecorder.record(itemId: id, outcome: ReviewOutcome(correct: false), track: .comprehension, profile: &p, now: t0) }
        p.knowledge[ids[0]]?.comprehension.due = t0.addingTimeInterval(-60)
        p.knowledge[ids[1]]?.comprehension.due = t0.addingTimeInterval(3 * 3600)
        p.knowledge[ids[2]]?.comprehension.due = t0.addingTimeInterval(5 * 86400)
        let f = ReviewForecast.make(p, now: t0)
        XCTAssertEqual(f.dueNow, p.knowledge.values.filter { $0.nextDue <= t0 }.count)
        XCTAssertGreaterThanOrEqual(f.nextSevenDays, f.tomorrow)
        XCTAssertEqual(f.dueNow + f.nextSevenDays <= 3, true)
    }

    // 6
    func testQuizMissedAnswer() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        p.progress.completedQuests.insert(lib.units[0].quests[0].id)
        let q = try XCTUnwrap(UnitQuiz(unit: lib.units[0], profile: p, library: lib, seed: 2).current)
        XCTAssertNil(q.missed(picked: q.answerIndex))
        let m = try XCTUnwrap(q.missed(picked: (q.answerIndex + 1) % q.options.count))
        XCTAssertEqual(m.right, q.options[q.answerIndex])
        XCTAssertNotEqual(m.picked, m.right)
    }

    // 7
    func testSentenceHintGivesNextTileAndCostsFirstTry() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        p.progress.startedQuests.insert(lib.units[0].quests[0].id)
        var g = SentenceBuilder(profile: p, library: lib, seed: 4)
        let pz = try XCTUnwrap(g.current)
        var placed: [Int] = []
        while let h = SentenceBuilder.hint(for: pz, placed: placed) { placed.append(h) }
        XCTAssertEqual(placed.map { pz.tiles[$0] }, pz.answer, "hints build the whole sentence")
        // A wrong start gets no hint.
        if let wrong = pz.tiles.indices.first(where: { pz.tiles[$0] != pz.answer[0] }) {
            XCTAssertNil(SentenceBuilder.hint(for: pz, placed: [wrong]))
        }
        g.useHint()
        g.check(pz.answer)
        XCTAssertEqual(g.firstTryCorrect, 0)
    }

    // 8
    func testConversationReplayCoversEveryLineOnce() throws {
        for (id, lib) in try libs() {
            for q in lib.units.flatMap(\.quests) {
                let lines = ConversationReplay.lines(q, npcName: "Luna")
                let npcLines = lines.filter { !$0.isYou }
                XCTAssertEqual(Set(npcLines.map(\.id)), Set(q.dialogue.nodes.map(\.id)), "\(id) \(q.id)")
                XCTAssertEqual(npcLines.count, q.dialogue.nodes.count, "\(id) \(q.id) no repeats")
                XCTAssertEqual(lines.first?.id, q.dialogue.start)
            }
        }
        var p = learner(try ContentLibrary.bundled("en-es"))
        for _ in 0..<3 { ConversationReplay.recordReplay(profile: &p) }
        XCTAssertTrue(Achievement.evaluate(&p, libraries: try libs(), now: t0).contains { $0.id == "a-replay" })
    }

    // 9
    func testWordNotesTrimCapAndRemove() throws {
        let lib = try ContentLibrary.bundled("en-de")
        var p = learner(lib)
        let id = lib.allItems[0].id
        WordNotes.set("  sounds like 'hollow'  ", for: id, profile: &p)
        XCTAssertEqual(WordNotes.note(id, in: p), "sounds like 'hollow'")
        WordNotes.set(String(repeating: "a", count: 500), for: id, profile: &p)
        XCTAssertEqual(WordNotes.note(id, in: p)?.count, WordNotes.maxLength)
        WordNotes.set("   ", for: id, profile: &p)
        XCTAssertNil(WordNotes.note(id, in: p))
        for item in lib.allItems.prefix(3) { WordNotes.set("note", for: item.id, profile: &p) }
        let e = try XCTUnwrap(WordLibrary.entries(p, library: lib).first { $0.id == id })
        XCTAssertTrue(WordLibrary.matchesNote(e, query: "NOTE", profile: p))
        XCTAssertTrue(Achievement.evaluate(&p, libraries: try libs(), now: t0).contains { $0.id == "a-notes" })
    }

    // 10
    func testPinnedLanguagesKeepAtMostThree() throws {
        var p = learner(try ContentLibrary.bundled("en-es"))
        for id in ["en-es", "en-fr", "en-ja", "en-de"] { XCTAssertTrue(PinnedLanguages.toggle(id, profile: &p)) }
        XCTAssertEqual(PinnedLanguages.pinned(p), ["en-fr", "en-ja", "en-de"])
        XCTAssertFalse(PinnedLanguages.toggle("en-ja", profile: &p))
        XCTAssertEqual(PinnedLanguages.pinned(p), ["en-fr", "en-de"])
    }

    // 11
    func testHighContrastPaletteIsAAA() {
        for (name, a, b) in ThemePalette.highContrast.textPairs {
            XCTAssertGreaterThanOrEqual(RGB.contrast(a, b), 7, name)
        }
        XCTAssertFalse(LearnerSettings().highContrastOn)
        XCTAssertFalse(LearnerSettings().leftHandedOn)
    }

    // 13
    func testLastMonthCalendar() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let lib = try! ContentLibrary.bundled("en-es")
        var p = learner(lib)
        p.log.activitiesByDay[ActivityLog.dayKey(t0, calendar: cal)] = 10
        p.log.minutesByDay[ActivityLog.dayKey(t0.addingTimeInterval(-86400 * 3), calendar: cal)] = 4
        let days = PlayerStats.lastMonth(p, now: t0, calendar: cal)
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.last?.day, ActivityLog.dayKey(t0, calendar: cal))
        XCTAssertEqual(days.last?.intensity, 3)
        XCTAssertEqual(days[26].intensity, 1)
        XCTAssertEqual(PlayerStats.activeDays(days), 2)
        XCTAssertGreaterThanOrEqual(ActivityLog.retentionDays, 30, "the log keeps enough days for the calendar")
    }

    // 14
    func testAchievementProgress() throws {
        let l = try libs(), lib = try XCTUnwrap(l["en-es"])
        var p = learner(lib)
        for item in lib.allItems.prefix(2) { StarredWords.toggle(item.id, profile: &p) }
        let starred = try XCTUnwrap(Achievement.all.first { $0.id == "a-starred" })
        XCTAssertEqual(starred.progress(p, libraries: l), AchievementProgress(current: 2, target: 5))
        let first = try XCTUnwrap(Achievement.all.first { $0.id == "a-first-quest" })
        XCTAssertNil(first.progress(p, libraries: l))
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
    }

    // Saves from v0.8 still load.
    func testV08SaveLoads() throws {
        var save = FamilySave()
        save.profiles = [PlayerProfile(nickname: "", ageBand: .age11to12, variant: "es-MX")]
        let data = try JSONEncoder().encode(save)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var profs = json["profiles"] as! [[String: Any]]
        var settings = profs[0]["settings"] as! [String: Any]
        settings.removeValue(forKey: "highContrast"); settings.removeValue(forKey: "leftHanded")
        profs[0]["settings"] = settings; json["profiles"] = profs
        let back = try JSONDecoder().decode(FamilySave.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(back.profiles[0].settings.highContrastOn)
    }
}
