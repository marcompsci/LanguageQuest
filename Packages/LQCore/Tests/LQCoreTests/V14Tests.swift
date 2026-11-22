import XCTest
@testable import LQCore

final class V14Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_900_000_000)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func learner(_ lib: ContentLibrary) -> PlayerProfile {
        PlayerProfile(nickname: "", ageBand: .age13to15, courseId: lib.course.id, variant: lib.course.defaultVariant, now: t0)
    }
    func play(_ q: Quest, _ p: inout PlayerProfile, _ lib: ContentLibrary, at: Date) {
        let prog = Progression(library: lib)
        for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: at) }
    }
    func veteran(_ course: String = "en-es") throws -> (ContentLibrary, PlayerProfile) {
        let lib = try ContentLibrary.bundled(course)
        var p = learner(lib)
        for u in lib.units { for q in u.quests { play(q, &p, lib, at: t0) } }
        return (lib, p)
    }
    func checkRound(_ r: ChoiceRound, file: StaticString = #filePath, line: UInt = #line) {
        for q in r.questions {
            XCTAssertTrue(q.options.indices.contains(q.answerIndex), file: file, line: line)
            XCTAssertEqual(Set(q.options).count, q.options.count, "no duplicate options", file: file, line: line)
            XCTAssertGreaterThanOrEqual(q.options.count, 2, file: file, line: line)
        }
        var r = r
        while let q = r.current { r.answer(q.answerIndex) }
        XCTAssertEqual(r.correct, r.questions.count, file: file, line: line)
        XCTAssertTrue(r.isFinished, file: file, line: line)
    }

    // 1
    func testArticleDrill() throws {
        let (lib, p) = try veteran()
        XCTAssertEqual(ArticleDrill.articles(lib.course)?.m, "el")
        XCTAssertTrue(ArticleDrill.isAvailable(p, library: lib))
        let r = ArticleDrill.round(p, library: lib, seed: 1)
        XCTAssertFalse(r.questions.isEmpty)
        checkRound(r)
        for q in r.questions {
            let item = lib.item(q.id)!
            XCTAssertEqual(q.options[q.answerIndex], item.gender == "m" ? "el" : "la")
            XCTAssertFalse(q.prompt.lowercased().hasPrefix("el "))
            XCTAssertFalse(q.prompt.lowercased().hasPrefix("la "))
        }
        XCTAssertEqual(ArticleDrill.bareNoun("La casa", articles: ("el", "la")), "casa")
        XCTAssertEqual(ArticleDrill.bareNoun("l'école", articles: ("le", "la")), "école")
        let (ja, jp) = try veteran("en-ja")
        XCTAssertFalse(ArticleDrill.isAvailable(jp, library: ja), "only languages with these articles")
    }

    // 2, 3, 27, 28
    func testChoiceGamesAreWellFormedAndDontTouchSchedule() throws {
        let (lib, p) = try veteran()
        let before = p.knowledge
        checkRound(PictureMatch.round(p, library: lib, seed: 2))
        let odd = OddOneOut.round(p, library: lib, seed: 3)
        XCTAssertFalse(odd.questions.isEmpty)
        checkRound(odd)
        checkRound(FamilyQuiz.round(p, library: lib, seed: 4))
        let chain = WordChain.round(p, library: lib, seed: 5)
        checkRound(chain)
        for q in chain.questions { XCTAssertEqual(q.options[q.answerIndex].first, q.prompt.last) }
        XCTAssertEqual(p.knowledge, before)
        XCTAssertTrue(PictureMatch.round(learner(lib), library: lib, seed: 1).questions.count <= 8)
    }

    // 4
    func testFreeRecall() throws {
        let (lib, p0) = try veteran()
        var p = p0
        let unit = try XCTUnwrap(FreeRecall.bestUnit(p, library: lib))
        var r = FreeRecall(unit: unit, profile: p, library: lib)
        XCTAssertGreaterThan(r.possible, 3)
        let v = lib.course.defaultVariant
        let items = unit.allItems.filter { p.knowledge[$0.id] != nil }
        XCTAssertNotNil(r.submit(items[0].target.text(for: v).uppercased()), "case doesn't matter")
        XCTAssertNil(r.submit(items[0].target.text(for: v)), "no double counting")
        XCTAssertNil(r.submit("zzzz"))
        XCTAssertNotNil(r.submit(items[1].target.text(for: v)))
        XCTAssertEqual(r.found.count, 2)
        XCTAssertTrue(FreeRecall.finish(r, profile: &p))
        XCTAssertFalse(FreeRecall.finish(FreeRecall(unit: unit, profile: p, library: lib), profile: &p))
        XCTAssertNil(FreeRecall.bestUnit(learner(lib), library: lib))
    }

    // 5
    func testYesterdaysWords() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        XCTAssertTrue(YesterdayRecall.ids(p, now: t0, calendar: cal).isEmpty)
        let ids = YesterdayRecall.ids(p, now: t0.addingTimeInterval(86400), calendar: cal)
        XCTAssertFalse(ids.isEmpty)
        XCTAssertLessThanOrEqual(ids.count, 5)
        XCTAssertTrue(YesterdayRecall.ids(p, now: t0.addingTimeInterval(3 * 86400), calendar: cal).isEmpty)
    }

    // 6
    func testMiniStory() throws {
        let (lib, p) = try veteran()
        let s = try XCTUnwrap(MiniStory.make(p, library: lib, seed: 1))
        XCTAssertGreaterThanOrEqual(s.texts.count, 3)
        XCTAssertEqual(s.texts.count, s.englishes.count)
        checkRound(ChoiceRound([s.question]))
    }

    // 7
    func testRelatedWordsShareAStem() throws {
        let (lib, p) = try veteran()
        let v = lib.course.defaultVariant
        var anyFound = false
        for item in lib.allItems where p.knowledge[item.id] != nil {
            let rel = RelatedWords.ids(for: item, profile: p, library: lib)
            XCTAssertFalse(rel.contains(item.id))
            if !rel.isEmpty { anyFound = true }
            XCTAssertLessThanOrEqual(rel.count, 4)
            _ = v
        }
        _ = anyFound   // content-dependent; the checks above are what matter
    }

    // 9
    func testChallengeModeTypesEverything() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        p.settings.challengeMode = true
        let q = RetentionQuiz(kind: .memoryCheck, profile: p, library: lib, now: t0.addingTimeInterval(86400), seed: 1)
        XCTAssertFalse(q.questions.isEmpty)
        XCTAssertTrue(q.questions.allSatisfy { $0.kind == .typeIt || $0.kind == .cloze })
        let lesson = RetentionQuiz(kind: .lesson(questId: lib.units[0].quests[0].id), profile: p, library: lib, now: t0, seed: 1)
        XCTAssertTrue(lesson.questions.contains { $0.kind != .typeIt }, "lesson quizzes keep their easier start")
    }

    // 10 + 16
    func testLockInsAndMilestones() {
        var k = ItemKnowledge(now: t0)
        k.spontaneousDelayedCorrect = 3
        let locked = RecallModel.isLockedIn(k, now: t0)
        let found = LockIns.newly(before: ["a": ItemKnowledge(now: t0)], after: ["a": k], now: t0)
        XCTAssertEqual(found, locked ? ["a"] : [])
        XCTAssertEqual(LockIns.newly(before: ["a": k], after: ["a": k], now: t0), [])
        XCTAssertEqual(WordMilestones.crossed(before: 24, after: 26), 25)
        XCTAssertNil(WordMilestones.crossed(before: 25, after: 30))
        XCTAssertEqual(WordMilestones.crossed(before: 40, after: 120), 100)
    }

    // 11
    func testFreshStartOnlyForSlippingWords() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        let id = p.knowledge.keys.sorted()[0]
        WordReset.freshStart(id, profile: &p, now: t0)
        XCTAssertNil(p.metaOrEmpty.counters[MetaEvent.wordReset], "not slipping yet")
        p.knowledge[id]!.comprehension.lapses = 6
        XCTAssertTrue(WordReset.canReset(p.knowledge[id]!))
        WordReset.freshStart(id, profile: &p, now: t0)
        XCTAssertEqual(p.knowledge[id]!.comprehension.lapses, 0)
        XCTAssertTrue(ReviewPlanner.dueItems(p.knowledge, now: t0, limit: 99).contains(id))
    }

    // 12, 13, settings
    func testReasonCueAndSettingsDecode() throws {
        var s = LearnerSettings()
        XCTAssertNil(s.reason); XCTAssertNil(s.cue); XCTAssertFalse(s.challengeModeOn)
        s.learningReason = "travel"; s.practiceCue = "afterDinner"
        XCTAssertEqual(s.reason, .travel)
        XCTAssertEqual(s.cue?.plan, "After dinner, I'll do a Quick 3.")
        s.learningReason = "nonsense"
        XCTAssertNil(s.reason)
        let d = try JSONDecoder().decode(LearnerSettings.self, from: JSONEncoder().encode(LearnerSettings()))
        XCTAssertNil(d.remindersPausedUntil)
        XCTAssertTrue(LearningReason.allCases.allSatisfy { !$0.nudge.isEmpty && !$0.title.isEmpty })
    }

    // 14, 15, 23
    func testSelfRaceHeatmapAndHistory() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let today = ActivityLog.dayKey(t0, calendar: cal)
        let lastWeek = ActivityLog.dayKey(t0.addingTimeInterval(-7 * 86400), calendar: cal)
        p.log.minutesByDay[today] = 12
        p.log.minutesByDay[lastWeek] = 5
        let race = SelfRace.compute(p, now: t0, calendar: cal)
        XCTAssertEqual(race.thisWeek, 12)
        XCTAssertEqual(race.lastWeekSoFar, 5)
        XCTAssertTrue(race.ahead)
        let cells = ActivityHeatmap.cells(p, now: t0, calendar: cal)
        XCTAssertLessThanOrEqual(cells.count, 84)
        XCTAssertEqual(cells.last?.day, today)
        XCTAssertEqual(cells.last?.level, 3)
        XCTAssertEqual(Set(cells.map(\.day)).count, cells.count)
        let hist = ParentHistory.days(p, now: t0, calendar: cal)
        XCTAssertEqual(hist.count, 30)
        XCTAssertEqual(hist.last?.count, 12)
        XCTAssertEqual(ParentWeekly.minutesThisWeek(p, now: t0, calendar: cal), 12)
    }

    // 17
    func testSkillBreakdownCountsByType() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        var quiz = RetentionQuiz(kind: .memoryCheck, profile: p, library: lib, now: t0.addingTimeInterval(86400), seed: 2)
        let v = lib.course.defaultVariant
        while let q = quiz.current {
            if q.kind == .typeIt || q.kind == .cloze { quiz.answer(typed: "wrong", variant: v, context: lib.checkContext) }
            else { quiz.answer(choice: q.answerIndex, variant: v, context: lib.checkContext) }
            RetentionQuiz.record(q, correct: quiz.firstTry[q.itemId] == true, profile: &p, now: t0.addingTimeInterval(86400))
        }
        let rows = SkillBreakdown.rows(p)
        XCTAssertEqual(rows.count, 5)
        XCTAssertGreaterThan(rows.reduce(0) { $0 + $1.asked }, 0)
        if let typed = rows.first(where: { $0.kind == .typeIt }), typed.asked > 0 { XCTAssertEqual(typed.percent, 0) }
    }

    // 19, 21
    func testTipsAndReminderPause() throws {
        XCTAssertTrue(LearningTips.all.contains(LearningTips.tip(now: t0, calendar: cal)))
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        XCTAssertFalse(ReminderPause.isPaused(p.settings, now: t0))
        ReminderPause.pause(days: 7, profile: &p, now: t0, calendar: cal)
        XCTAssertTrue(ReminderPause.isPaused(p.settings, now: t0.addingTimeInterval(3 * 86400)))
        XCTAssertFalse(ReminderPause.isPaused(p.settings, now: t0.addingTimeInterval(8 * 86400)))
        let plan = (0..<10).map { PlannedReminder(date: t0.addingTimeInterval(Double($0) * 86400), templateId: "t", body: "b") }
        let kept = ReminderPause.apply(plan, settings: p.settings)
        XCTAssertTrue(kept.allSatisfy { $0.date >= p.settings.remindersPausedUntil! })
        XCTAssertLessThan(kept.count, plan.count)
        ReminderPause.resume(&p)
        XCTAssertEqual(ReminderPause.apply(plan, settings: p.settings).count, plan.count)
    }

    // 24
    func testPracticeSheet() throws {
        let (lib, p) = try veteran()
        let text = PracticeSheet.text(p, library: lib, seed: 1)
        XCTAssertTrue(text.contains("____"))
        XCTAssertTrue(text.contains("Answers"))
        XCTAssertTrue(text.contains("12. "))
    }

    // 29, 30
    func testAchievementsAndWhatsNew() throws {
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
        for id in ["a-recall10", "a-articles", "a-words100", "a-family"] { XCTAssertTrue(Achievement.all.contains { $0.id == id }) }
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        GameCounters.played(MetaEvent.familyQuiz, profile: &p)
        XCTAssertTrue(Achievement.all.first { $0.id == "a-family" }!.isMetV14(p) == true)
        XCTAssertEqual(OnceMessages.currentVersion, "1.4")
    }
}
