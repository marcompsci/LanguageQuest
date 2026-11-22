import XCTest
@testable import LQCore

final class V13Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_900_000_000)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func learner(_ lib: ContentLibrary) -> PlayerProfile {
        PlayerProfile(nickname: "", ageBand: .age13to15, courseId: lib.course.id, variant: lib.course.defaultVariant, now: t0)
    }
    func play(_ q: Quest, _ p: inout PlayerProfile, _ lib: ContentLibrary, at: Date) {
        let prog = Progression(library: lib)
        for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: at) }
    }
    func meaningQuestion(_ id: String, _ lib: ContentLibrary) -> RetentionQuestion {
        var rng = SeededRandom(seed: 1)
        return RetentionQuiz.question(lib.item(id)!, kind: .meaning, variant: lib.course.defaultVariant, distractors: lib.allItems, reason: "", rng: &rng)
    }

    // 1 + 2
    func testGuessesAndSlowAnswersComeBackSooner() throws {
        let lib = try ContentLibrary.bundled("en-es")
        let id = lib.units[0].vocabulary[0].id
        let q = meaningQuestion(id, lib)
        var sure = learner(lib), guessed = learner(lib), slow = learner(lib)
        for day in 0..<3 {
            let at = t0.addingTimeInterval(Double(day) * 3 * 86400)
            RetentionQuiz.record(q, correct: true, seconds: 2, profile: &sure, now: at)
            RetentionQuiz.record(q, correct: true, guessed: day == 2, seconds: 2, profile: &guessed, now: at)
            RetentionQuiz.record(q, correct: true, seconds: day == 2 ? 30 : 2, profile: &slow, now: at)
        }
        let i = { (p: PlayerProfile) in p.knowledge[id]!.comprehension.intervalDays }
        XCTAssertLessThan(i(guessed), i(sure))
        XCTAssertLessThanOrEqual(i(slow), i(sure))
        XCTAssertLessThan(slow.knowledge[id]!.comprehension.ease, sure.knowledge[id]!.comprehension.ease, "a slow answer makes the gaps grow more slowly")
        XCTAssertEqual(AnswerTiming.effectiveSeconds(nil, kind: .meaning), AnswerTiming.defaultSeconds)
        XCTAssertEqual(AnswerTiming.effectiveSeconds(16, kind: .typeIt), 8, "typing gets twice as long")
        XCTAssertEqual(AnswerTiming.effectiveSeconds(9999, kind: .meaning), 120)
        // A wrong answer is never treated as a guess bonus.
        var wrong = learner(lib)
        RetentionQuiz.record(q, correct: false, guessed: true, profile: &wrong, now: t0)
        XCTAssertEqual(wrong.knowledge[id]!.comprehension.lapses, 1)
    }

    // 3
    func testForecastByDay() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        let days = DailyForecast.days(p, now: t0, calendar: cal)
        XCTAssertEqual(days.count, 7)
        let practised = p.knowledge.values.filter { $0.comprehension.lastReviewed != nil || $0.production.lastReviewed != nil }.count
        XCTAssertGreaterThan(practised, 0)
        XCTAssertLessThanOrEqual(days.reduce(0) { $0 + $1.count }, practised)
        XCTAssertGreaterThan(days.reduce(0) { $0 + $1.count }, 0)
    }

    // 4
    func testUnitMastery() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        XCTAssertTrue(UnitMastery.rows(p, library: lib).allSatisfy { $0.strong == 0 && $0.total > 0 })
        let id = lib.units[0].allItems[0].id
        var k = ItemKnowledge(now: t0)
        for d in 0..<6 { k.record(ReviewOutcome(correct: true, responseSeconds: 2), track: .comprehension, now: t0.addingTimeInterval(Double(d * d + d) * 86400)) }
        p.knowledge[id] = k
        if k.level >= .understood {
            XCTAssertEqual(UnitMastery.rows(p, library: lib)[0].strong, 1)
            XCTAssertGreaterThan(UnitMastery.rows(p, library: lib)[0].fraction, 0)
        }
    }

    // 5
    func testLookAlikesFindNearSpellings() throws {
        XCTAssertEqual(LookAlikes.distance(Array("pero"), Array("perro")), 1)
        XCTAssertEqual(LookAlikes.distance(Array("casa"), Array("cosa")), 1)
        XCTAssertEqual(LookAlikes.distance(Array(""), Array("abc")), 3)
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        for u in lib.units { for q in u.quests { play(q, &p, lib, at: t0) } }
        let pairs = LookAlikes.pairs(p, library: lib, limit: 50)
        let v = lib.course.defaultVariant
        for pr in pairs {
            let a = AnswerChecker.normalize(lib.item(pr.a)!.target.text(for: v)), b = AnswerChecker.normalize(lib.item(pr.b)!.target.text(for: v))
            XCTAssertNotEqual(a, b)
            XCTAssertLessThanOrEqual(LookAlikes.distance(Array(a), Array(b)), 2)
        }
        let ids = LookAlikes.drillIds(pairs)
        XCTAssertEqual(ids.count, Set(ids).count)
        LookAlikes.markDrillDone(&p)
        XCTAssertTrue(Achievement.v13.first { $0.id == "a-lookalike" }!.isMetV13(p) == true)
    }

    // 6
    func testLightningRoundScoresAndBest() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        let before = p.knowledge
        var r = LightningRound(profile: p, library: lib, seed: 3)
        for _ in 0..<12 { guard let q = r.current else { break }; r.answer(choice: q.answerIndex) }
        if let q = r.current { r.answer(choice: (q.answerIndex + 1) % q.options.count) }
        XCTAssertEqual(r.score, 12)
        XCTAssertEqual(r.answered, 13)
        XCTAssertTrue(LightningRound.finish(r, profile: &p))
        XCTAssertEqual(LightningRound.best(p), 12)
        var worse = LightningRound(profile: p, library: lib, seed: 4)
        if let q = worse.current { worse.answer(choice: q.answerIndex) }
        XCTAssertFalse(LightningRound.finish(worse, profile: &p))
        XCTAssertEqual(LightningRound.best(p), 12)
        XCTAssertEqual(p.knowledge, before, "the speed game doesn't change the review schedule")
    }

    // 7 + 8
    func testListeningAndQuickChecks() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        let listen = RetentionQuiz(kind: .listening, profile: p, library: lib, now: t0.addingTimeInterval(86400), seed: 1)
        XCTAssertFalse(listen.questions.isEmpty)
        XCTAssertTrue(listen.questions.allSatisfy { $0.kind == .listen })
        var quick = RetentionQuiz(kind: .quick, profile: p, library: lib, now: t0.addingTimeInterval(86400), seed: 1, count: 3)
        XCTAssertEqual(quick.total, 3)
        let v = lib.course.defaultVariant
        while let c = quick.current {
            if c.kind == .typeIt { quick.answer(typed: c.word.text(for: v), variant: v, context: lib.checkContext) }
            else { quick.answer(choice: c.answerIndex, variant: v, context: lib.checkContext) }
        }
        XCTAssertEqual(quick.reviewRows.count, 3)
        XCTAssertTrue(quick.reviewRows.allSatisfy(\.correct))
        RetentionQuiz.finish(quick, profile: &p, library: lib, now: t0.addingTimeInterval(86400))
        XCTAssertEqual(p.metaOrEmpty.counters[MetaEvent.quickDone], 1)
        XCTAssertNil(p.metaOrEmpty.counters[MetaEvent.memoryCheckDone], "a quick 3 isn't a full memory check")
    }

    // 9 + 19
    func testSentenceOfTheDayUsesTheWord() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        for q in lib.units[0].quests { play(q, &p, lib, at: t0) }
        var found = 0
        for d in 0..<20 {
            if let s = SentenceOfTheDay.make(p, library: lib, now: t0.addingTimeInterval(Double(d) * 86400), calendar: cal) {
                found += 1
                XCTAssertFalse(s.text.contains(Cloze.blank))
                XCTAssertTrue(s.text.localizedCaseInsensitiveContains(s.word.target.text(for: lib.course.defaultVariant)))
            }
        }
        XCTAssertGreaterThan(found, 0)
    }

    // 10
    func testBedtimeReviewOnlyInTheEvening() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let morning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: t0)!
        let evening = cal.date(bySettingHour: 20, minute: 0, second: 0, of: t0)!
        play(lib.units[0].quests[0], &p, lib, at: morning)
        XCTAssertTrue(BedtimeReview.ids(p, now: morning, calendar: cal).isEmpty)
        let ids = BedtimeReview.ids(p, now: evening, calendar: cal)
        XCTAssertGreaterThanOrEqual(ids.count, 3)
        XCTAssertLessThanOrEqual(ids.count, BedtimeReview.size)
        XCTAssertTrue(BedtimeReview.isAvailable(p, now: evening, calendar: cal))
        BedtimeReview.markDone(&p, now: evening, calendar: cal)
        XCTAssertFalse(BedtimeReview.isAvailable(p, now: evening, calendar: cal))
        XCTAssertTrue(BedtimeReview.ids(p, now: evening.addingTimeInterval(86400), calendar: cal).isEmpty, "nothing practised the next day")
    }

    // 11
    func testReviewSoonPinsWithoutAMistake() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        let id = p.knowledge.keys.sorted()[0]
        let now = t0.addingTimeInterval(3600)
        let lapses = p.knowledge[id]!.comprehension.lapses
        ReviewSoon.pin(id, profile: &p, now: now)
        XCTAssertTrue(ReviewSoon.isDue(id, profile: p, now: now))
        XCTAssertTrue(ReviewPlanner.dueItems(p.knowledge, now: now, limit: 99).contains(id))
        XCTAssertEqual(p.knowledge[id]!.comprehension.lapses, lapses)
        let newId = lib.units[1].vocabulary[0].id
        ReviewSoon.pin(newId, profile: &p, now: now)
        XCTAssertTrue(ReviewPlanner.dueItems(p.knowledge, now: now, limit: 99).contains(newId))
    }

    // 14 + 15
    func testDailyAndWeeklyGoals() throws {
        var s = LearnerSettings()
        XCTAssertNil(DailyGoal.goal(s))
        s.dailyGoalMinutes = 10
        XCTAssertEqual(DailyGoal.goal(s), 10)
        s.dailyGoalMinutes = 7
        XCTAssertNil(DailyGoal.goal(s), "only offered choices")
        XCTAssertEqual(DailyGoal.progress(minutesToday: 5, goal: 10), 0.5)
        XCTAssertEqual(DailyGoal.progress(minutesToday: 50, goal: 10), 1)
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        p.updateExtras { $0.quizHistory = (0..<10).map { QuizRecord(date: self.t0.addingTimeInterval(Double($0) * 3600), courseId: "en-es", isLesson: false, questId: nil, correct: 4, total: 5, missed: []) } }
        XCTAssertEqual(WeeklyQuestions.answered(p, now: t0, calendar: cal), 50)
        XCTAssertEqual(WeeklyQuestions.answered(p, now: t0.addingTimeInterval(30 * 86400), calendar: cal), 0)
        XCTAssertEqual(WeeklyQuestions.bestWeek(p, calendar: cal), 50)
    }

    // 17
    func testParentBedtime() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        var parent = ParentSettings()
        let late = cal.date(bySettingHour: 21, minute: 30, second: 0, of: t0)!
        let early = cal.date(bySettingHour: 3, minute: 0, second: 0, of: t0)!
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: t0)!
        XCTAssertFalse(Bedtime.isPast(parent: parent, profile: p, now: late, calendar: cal))
        parent.bedtimeHour = 21
        XCTAssertTrue(Bedtime.isPast(parent: parent, profile: p, now: late, calendar: cal))
        XCTAssertTrue(Bedtime.isPast(parent: parent, profile: p, now: early, calendar: cal))
        XCTAssertFalse(Bedtime.isPast(parent: parent, profile: p, now: noon, calendar: cal))
        TimeLimit.allowMoreToday(profile: &p, now: late, calendar: cal)
        XCTAssertFalse(Bedtime.isPast(parent: parent, profile: p, now: late, calendar: cal), "a parent can allow more for the day")
        parent.bedtimeHour = 3
        XCTAssertFalse(Bedtime.isPast(parent: parent, profile: learner(lib), now: noon, calendar: cal), "only offered choices")
    }

    // 18
    func testWordListExport() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        let text = WordListExport.text(p, library: lib)
        XCTAssertTrue(text.contains("Unit 1"))
        let id = p.knowledge.keys.sorted()[0]
        XCTAssertTrue(text.contains(lib.item(id)!.english))
        XCTAssertFalse(text.contains("Unit 3"), "only units with words met")
    }

    // 20
    func testTodayReport() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        XCTAssertEqual(TodayReport.compute(p, now: t0, calendar: cal).wordsPractised, 0)
        XCTAssertNil(TodayReport.compute(p, now: t0, calendar: cal).accuracy)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        p.updateExtras { $0.quizHistory = [QuizRecord(date: self.t0, courseId: "en-es", isLesson: true, questId: nil, correct: 3, total: 4, missed: [])] }
        let r = TodayReport.compute(p, now: t0, calendar: cal)
        XCTAssertGreaterThan(r.wordsPractised, 0)
        XCTAssertEqual(r.quizzes, 1)
        XCTAssertEqual(r.accuracy, 75)
    }

    // 21
    func testCombo() {
        var c = ComboCounter()
        XCTAssertNil(c.record(true)); XCTAssertNil(c.record(true))
        XCTAssertEqual(c.record(true), 3)
        XCTAssertNil(c.record(false))
        XCTAssertEqual(c.run, 0)
        XCTAssertEqual(c.best, 3)
        for _ in 0..<4 { _ = c.record(true) }
        XCTAssertEqual(c.record(true), 5)
    }

    // 22 + settings
    func testOlderSettingsLoadWithNewDefaults() throws {
        let s = try JSONDecoder().decode(LearnerSettings.self, from: JSONEncoder().encode(LearnerSettings()))
        XCTAssertTrue(s.hapticsOn)
        XCTAssertFalse(s.bigButtonsOn)
        XCTAssertNil(s.dailyGoalMinutes)
    }

    // 23 + 24
    func testAchievementsAndWhatsNew() throws {
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count, "ids are unique")
        for id in ["a-lightning", "a-lookalike", "a-bedtime", "a-week50"] { XCTAssertTrue(Achievement.all.contains { $0.id == id }) }
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        p.updateMeta { $0.counters[MetaEvent.lightningBest] = 15 }
        XCTAssertTrue(Achievement.all.first { $0.id == "a-lightning" }!.isMetV13(p) == true)
        XCTAssertFalse(OnceMessages.currentVersion.isEmpty)
        XCTAssertEqual(OnceMessages.whatsNew.count, 8)
    }
}
