import XCTest
@testable import LQCore

final class V12Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_900_000_000)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func libs() throws -> [String: ContentLibrary] {
        Dictionary(uniqueKeysWithValues: try ContentLibrary.bundledCourseIds.map { ($0, try ContentLibrary.bundled($0)) })
    }
    func learner(_ lib: ContentLibrary) -> PlayerProfile {
        PlayerProfile(nickname: "", ageBand: .age13to15, courseId: lib.course.id, variant: lib.course.defaultVariant, now: t0)
    }
    func play(_ q: Quest, _ p: inout PlayerProfile, _ lib: ContentLibrary, at: Date) {
        let prog = Progression(library: lib)
        for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: at) }
    }

    // 1
    func testTrickyWordsAndDrill() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        XCTAssertTrue(TrickyWords.ids(p).isEmpty)
        let id = RetentionQuiz.lessonItems(lib.units[0].quests[0])[0]
        for i in 0..<4 {
            PracticeRecorder.record(itemId: id, outcome: ReviewOutcome(correct: true), track: .comprehension, profile: &p, now: t0.addingTimeInterval(Double(i) * 86400))
            PracticeRecorder.record(itemId: id, outcome: ReviewOutcome(correct: false), track: .comprehension, profile: &p, now: t0.addingTimeInterval(Double(i) * 86400 + 60))
        }
        XCTAssertEqual(TrickyWords.ids(p).first, id)
        XCTAssertEqual(WordLibrary.entries(p, library: lib, filter: .tricky).map(\.id), TrickyWords.ids(p))
        var drill = RetentionQuiz(kind: .tricky, profile: p, library: lib, now: t0.addingTimeInterval(5 * 86400), seed: 2)
        XCTAssertTrue(drill.questions.contains { $0.itemId == id })
        let v = lib.course.defaultVariant
        while let c = drill.current {
            if c.kind == .typeIt { drill.answer(typed: c.word.text(for: v), variant: v, context: lib.checkContext) }
            else { drill.answer(choice: c.answerIndex, variant: v, context: lib.checkContext) }
        }
        RetentionQuiz.finish(drill, profile: &p, library: lib, now: t0)
        XCTAssertEqual(p.metaOrEmpty.counters[MetaEvent.trickyDrill], 1)
        XCTAssertNil(p.metaOrEmpty.counters[MetaEvent.memoryCheckDone], "a drill isn't counted as a memory check")
    }

    func testPracticeJustTheMissedWords() throws {
        let lib = try ContentLibrary.bundled("en-fr")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        let ids = Array(RetentionQuiz.lessonItems(lib.units[0].quests[0]).prefix(2))
        let q = RetentionQuiz(kind: .words(ids), profile: p, library: lib, now: t0, seed: 1, count: ids.count)
        XCTAssertEqual(Set(q.questions.map(\.itemId)), Set(ids))
    }

    // 2
    func testTypoDiffMarksTheWrongLetters() {
        let m = TypoDiff.marks(typed: "gatto", expected: "gato")
        XCTAssertEqual(String(m.map(\.char)), "gatto")
        XCTAssertEqual(m.filter { !$0.ok }.count, 1)
        XCTAssertTrue(TypoDiff.marks(typed: "Mañana", expected: "manana").allSatisfy(\.ok), "accents and capitals ignored")
        XCTAssertTrue(TypoDiff.marks(typed: "", expected: "x").isEmpty)
        XCTAssertEqual(TypoDiff.marks(typed: "abc", expected: "").filter(\.ok).count, 0)
    }

    func testQuizRemembersAlmostVerdict() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let q = lib.units[0].quests[0]
        play(q, &p, lib, at: t0)
        var quiz = RetentionQuiz(kind: .lesson(questId: q.id), profile: p, library: lib, now: t0, seed: 5)
        let v = lib.course.defaultVariant
        while let c = quiz.current, c.kind != .typeIt { quiz.answer(choice: c.answerIndex, variant: v, context: lib.checkContext) }
        let c = try XCTUnwrap(quiz.current)
        let word = c.word.text(for: v)
        let typo = String(word.dropLast()) + "x"
        quiz.answer(typed: typo, variant: v, context: lib.checkContext)
        XCTAssertEqual(quiz.lastTyped, typo)
        XCTAssertNotNil(quiz.lastVerdict)
    }

    // 4
    func testDictationForgivesPunctuationAndCase() throws {
        for (id, lib) in try libs() {
            var p = learner(lib)
            p.progress.startedQuests.insert(lib.units[0].quests[0].id)
            var g = DictationGame(profile: p, library: lib, seed: 3)
            XCTAssertFalse(g.sentences.isEmpty, id)
            let v = lib.course.defaultVariant
            while let s = g.current {
                let typed = s.text.filter { !".,!?¿¡".contains($0) }.lowercased()
                g.submit(typed, variant: v, context: lib.checkContext)
            }
            XCTAssertEqual(g.correct, g.sentences.count, id)
            DictationGame.finish(g, profile: &p)
            XCTAssertEqual(p.metaOrEmpty.counters[MetaEvent.dictationPerfect], 1)
        }
    }

    // 5 + settings
    func testReviewSizeAndNewSettingsDefaults() {
        var s = LearnerSettings()
        XCTAssertEqual(ReviewSize.size(s), ReviewSize.defaultSize)
        s.reviewSize = 20; XCTAssertEqual(ReviewSize.size(s), 20)
        s.reviewSize = 999; XCTAssertEqual(ReviewSize.size(s), ReviewSize.defaultSize, "only listed sizes")
        XCTAssertFalse(LearnerSettings().quietModeOn)
    }

    // 6
    func testPathChestOncePerDay() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let done = [PathStep(kind: .memoryCheck, title: "", detail: "", done: true), PathStep(kind: .quest, title: "", detail: "", done: true),
                    PathStep(kind: .review, title: "", detail: "", done: true)]
        var notDone = done; notDone[1].done = false
        XCTAssertFalse(TodayPath.canOpenChest(notDone, profile: p, now: t0, calendar: cal))
        let xp = p.rewards.xp
        XCTAssertEqual(TodayPath.openChest(done, profile: &p, now: t0, calendar: cal), TodayPath.chestXP)
        XCTAssertEqual(p.rewards.xp, xp + TodayPath.chestXP)
        XCTAssertEqual(TodayPath.openChest(done, profile: &p, now: t0, calendar: cal), 0)
        XCTAssertTrue(TodayPath.canOpenChest(done, profile: p, now: t0.addingTimeInterval(86400), calendar: cal))
    }

    // 9
    func testDailyTimeLimit() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        var parent = ParentSettings()
        XCTAssertFalse(TimeLimit.isReached(minutesToday: 500, parent: parent, profile: p, now: t0), "no limit by default")
        parent.dailyLimitMinutes = 30
        XCTAssertFalse(TimeLimit.isReached(minutesToday: 29, parent: parent, profile: p, now: t0))
        XCTAssertTrue(TimeLimit.isReached(minutesToday: 30, parent: parent, profile: p, now: t0))
        TimeLimit.allowMoreToday(profile: &p, now: t0, calendar: cal)
        XCTAssertFalse(TimeLimit.isReached(minutesToday: 40, parent: parent, profile: p, now: t0, calendar: cal))
        XCTAssertTrue(TimeLimit.isReached(minutesToday: 40, parent: parent, profile: p, now: t0.addingTimeInterval(86400), calendar: cal), "only today")
    }

    // 10 + 14
    func testWordsThisWeekAndCurves() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        XCTAssertEqual(Set(WordsThisWeek.ids(p, now: t0.addingTimeInterval(3600))), Set(p.knowledge.keys))
        XCTAssertTrue(WordsThisWeek.ids(p, now: t0.addingTimeInterval(9 * 86400)).isEmpty)
        let k = try XCTUnwrap(p.knowledge.values.first)
        let curve = RecallModel.curve(k, now: t0)
        XCTAssertEqual(curve.count, 29)
        XCTAssertGreaterThanOrEqual(curve.first!.recall, curve.last!.recall, "memory fades without practice")
        let ex = RecallModel.exampleCurves()
        XCTAssertEqual(ex.count, 3)
        XCTAssertLessThan(ex[0].points[7].recall, ex[2].points[7].recall, "more reviews, slower forgetting")
    }

    // 15
    func testLevelRewards() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        XCTAssertTrue(LevelRewards.grant(profile: &p).isEmpty)
        p.rewards.xp = 5000
        XCTAssertEqual(Set(LevelRewards.grant(profile: &p)), ["goggles-explorer", "cloak-polyglot"])
        XCTAssertTrue(LevelRewards.grant(profile: &p).isEmpty, "once")
        for id in LevelRewards.byLevel.values { XCTAssertNotNil(Catalog.cosmetic(id)) }
    }

    // 16
    func testReminderDaysOff() throws {
        let sat = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 17)))   // Saturday
        let plan = (0..<7).map { PlannedReminder(date: sat.addingTimeInterval(Double($0) * 86400), templateId: "short", body: "x") }
        let kept = SmartReminders.respectingDaysOff(plan, daysOff: [1, 7], calendar: cal)
        XCTAssertEqual(kept.count, 5)
        XCTAssertFalse(kept.contains { [1, 7].contains(cal.component(.weekday, from: $0.date)) })
    }

    // 17
    func testEarnAFreezeOnceAWeekUpToThree() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let mon = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 18)))
        Streak.recordPractice(&p, now: mon, calendar: cal)          // the week starts with 2 freezes
        XCTAssertEqual(Streak.state(p).freezesLeft, Streak.freezesPerWeek)
        XCTAssertTrue(Streak.earnFreeze(&p, now: mon, calendar: cal))
        XCTAssertEqual(Streak.state(p).freezesLeft, 3)
        XCTAssertFalse(Streak.earnFreeze(&p, now: mon.addingTimeInterval(3600), calendar: cal), "once a week")
        // Next week the 2 refill; earning makes 3, never more.
        XCTAssertTrue(Streak.earnFreeze(&p, now: mon.addingTimeInterval(7 * 86400), calendar: cal))
        XCTAssertEqual(Streak.state(p).freezesLeft, Streak.maxFreezes)
    }

    // 18
    func testPracticeTimes() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        XCTAssertNil(PracticeTimes.summary(p, calendar: cal))
        let evening = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18)))
        for d in 0..<4 { SmartReminders.noteSessionStart(&p, now: evening.addingTimeInterval(Double(d) * 86400)) }
        XCTAssertEqual(PracticeTimes.byHour(p, calendar: cal)[18].sessions, 4)
        XCTAssertEqual(PracticeTimes.summary(p, calendar: cal), "Usually practices in the evening.")
    }

    // 20 + 21 + 23
    func testOnceMessagesAndAchievements() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        XCTAssertFalse(OnceMessages.shouldShowWhatsNew(p), "new players don't need 'what's new'")
        play(lib.units[0].quests[0], &p, lib, at: t0)
        XCTAssertTrue(OnceMessages.shouldShowWhatsNew(p))
        OnceMessages.markWhatsNew(&p)
        XCTAssertFalse(OnceMessages.shouldShowWhatsNew(p))
        XCTAssertFalse(OnceMessages.tipSeen("path", in: p))
        OnceMessages.markTip("path", profile: &p); OnceMessages.markTip("path", profile: &p)
        XCTAssertEqual(p.metaOrEmpty.tipsSeen, ["path"])
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
        for id in ["a-tricky", "a-dictation", "a-path7", "a-freeze"] { XCTAssertTrue(Achievement.all.contains { $0.id == id }) }
    }
}
