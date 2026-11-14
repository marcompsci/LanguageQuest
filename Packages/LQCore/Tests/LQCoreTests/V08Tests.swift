import XCTest
@testable import LQCore

final class V08Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    func libs() throws -> [String: ContentLibrary] {
        Dictionary(uniqueKeysWithValues: try ContentLibrary.bundledCourseIds.map { ($0, try ContentLibrary.bundled($0)) })
    }

    func learner(_ lib: ContentLibrary) -> PlayerProfile {
        PlayerProfile(nickname: "", ageBand: .age13to15, courseId: lib.course.id, variant: lib.course.defaultVariant, now: t0)
    }

    /// Finishes the first quest so quizzes and sentence lines open.
    func finishFirstQuest(_ p: inout PlayerProfile, _ lib: ContentLibrary) {
        let q = lib.units[0].quests[0]
        p.progress.startedQuests.insert(q.id); p.progress.completedQuests.insert(q.id)
    }

    // 1. Word Library

    func testWordLibraryListsSearchesAndFilters() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let all = WordLibrary.entries(p, library: lib)
        XCTAssertEqual(all.count, Set(lib.allItems.map(\.id)).count)
        XCTAssertEqual(all.map(\.unitOrder), all.map(\.unitOrder).sorted(), "unit order")
        XCTAssertTrue(WordLibrary.entries(p, library: lib, filter: .met).isEmpty)
        let first = all[0].item
        XCTAssertTrue(WordLibrary.entries(p, library: lib, query: first.english).contains { $0.id == first.id }, "search by meaning")
        XCTAssertTrue(WordLibrary.entries(p, library: lib, query: first.target.base.uppercased()).contains { $0.id == first.id }, "search ignores case")
        XCTAssertTrue(WordLibrary.entries(p, library: lib, query: "zzzzqq").isEmpty)
        PracticeRecorder.record(itemId: first.id, outcome: ReviewOutcome(correct: false), track: .comprehension, profile: &p, now: t0)
        XCTAssertEqual(WordLibrary.entries(p, library: lib, filter: .met, now: t0).map(\.id), [first.id])
        XCTAssertEqual(WordLibrary.entries(p, library: lib, filter: .practice, now: t0).map(\.id), [first.id])
    }

    func testWordLibrarySearchesPronunciationLine() throws {
        let lib = try ContentLibrary.bundled("en-ja")
        let p = learner(lib)
        let item = try XCTUnwrap(lib.allItems.first { lib.course.romanize($0.target.base) != nil })
        let roman = try XCTUnwrap(lib.course.romanize(item.target.base))
        XCTAssertTrue(WordLibrary.entries(p, library: lib, query: roman).contains { $0.id == item.id })
    }

    // 2. Starred

    func testStarringTogglesAndBuildsDeck() throws {
        let lib = try ContentLibrary.bundled("en-fr")
        var p = learner(lib)
        let ids = lib.allItems.prefix(3).map(\.id)
        for id in ids { XCTAssertTrue(StarredWords.toggle(id, profile: &p)) }
        XCTAssertFalse(StarredWords.toggle(ids[1], profile: &p), "second tap un-stars")
        XCTAssertEqual(Set(WordLibrary.entries(p, library: lib, filter: .starred).map(\.id)), [ids[0], ids[2]])
        XCTAssertEqual(Set(StarredWords.deck(p, library: lib, now: t0, seed: 4).map(\.itemId)), [ids[0], ids[2]])
        // Stars belong to the language: switching away and back keeps them.
        p.switchCourse(to: "en-es", defaultVariant: "es-MX")
        XCTAssertTrue(p.extrasOrEmpty.starredWords?.isEmpty ?? true)
        p.switchCourse(to: "en-fr", defaultVariant: lib.course.defaultVariant)
        XCTAssertEqual(p.extrasOrEmpty.starredWords ?? [], [ids[0], ids[2]])
    }

    // 3. Word of the day

    func testWordOfTheDayIsStableAllDayAndInReach() throws {
        for (id, lib) in try libs() {
            let p = learner(lib)
            let w = try XCTUnwrap(WordOfTheDay.pick(p, library: lib, now: t0), id)
            XCTAssertEqual(WordOfTheDay.pick(p, library: lib, now: t0.addingTimeInterval(3600))?.id, w.id, "\(id) same all day")
            XCTAssertTrue(lib.units[0].allItems.contains { $0.id == w.id }, "\(id): new learners get first-unit words")
        }
    }

    // 4. Sentence Builder

    func testSentenceBuilderWorksInEveryLanguage() throws {
        for (id, lib) in try libs() {
            var p = learner(lib)
            finishFirstQuest(&p, lib)
            XCTAssertTrue(SentenceBuilder.isAvailable(p, library: lib), id)
            var g = SentenceBuilder(profile: p, library: lib, seed: 9)
            XCTAssertFalse(g.puzzles.isEmpty, id)
            for pz in g.puzzles {
                XCTAssertTrue((SentenceBuilder.minTokens...SentenceBuilder.maxTokens).contains(pz.answer.count), "\(id): \(pz.full)")
                XCTAssertEqual(pz.tiles.sorted(), pz.answer.sorted(), "same tiles")
                if Set(pz.answer).count > 1 { XCTAssertNotEqual(pz.tiles, pz.answer, "\(id) shuffled") }
            }
            // A wrong try, then right: counts, but not as first try.
            let first = try XCTUnwrap(g.current)
            XCTAssertFalse(g.check(first.answer.reversed()))
            XCTAssertTrue(g.check(first.answer))
            while let pz = g.current { g.check(pz.answer) }
            XCTAssertTrue(g.isFinished)
            XCTAssertEqual(g.firstTryCorrect, g.puzzles.count - 1, id)
        }
    }

    func testSentenceTokensForSpacelessScript() {
        XCTAssertEqual(SentenceBuilder.tokens("你好！我是露娜。"), ["你", "好！", "我", "是", "露", "娜。"])
        XCTAssertEqual(SentenceBuilder.tokens("Ich heiße Mateo."), ["Ich", "heiße", "Mateo."])
    }

    func testSentenceBuilderPerfectGameEarnsAchievement() throws {
        let l = try libs(), lib = try XCTUnwrap(l["en-es"])
        var p = learner(lib)
        finishFirstQuest(&p, lib)
        var g = SentenceBuilder(profile: p, library: lib, seed: 2)
        while let pz = g.current { g.check(pz.answer) }
        XCTAssertEqual(g.stars, 3)
        SentenceBuilder.finish(g, profile: &p, now: t0)
        XCTAssertEqual(p.extrasOrEmpty.builderBestStars, 3)
        XCTAssertTrue(Achievement.evaluate(&p, libraries: l, now: t0).contains { $0.id == "a-builder" })
    }

    // 5. Unit quiz

    func testUnitQuizOpensAfterAQuestAndScores() throws {
        let l = try libs()
        for (id, lib) in l {
            var p = learner(lib)
            let unit = lib.units[0]
            XCTAssertFalse(UnitQuiz.isOpen(unit, progress: p.progress), id)
            finishFirstQuest(&p, lib)
            XCTAssertTrue(UnitQuiz.isOpen(unit, progress: p.progress), id)
            var quiz = UnitQuiz(unit: unit, profile: p, library: lib, seed: 3)
            XCTAssertGreaterThanOrEqual(quiz.questions.count, 5, id)
            XCTAssertLessThanOrEqual(quiz.questions.count, UnitQuiz.size)
            for q in quiz.questions {
                XCTAssertEqual(Set(q.options).count, q.options.count, "\(id): no duplicate options")
                XCTAssertGreaterThanOrEqual(q.options.count, 3, id)
            }
            XCTAssertTrue(quiz.questions.contains { $0.showsTarget } && quiz.questions.contains { !$0.showsTarget }, "both directions")
            while let q = quiz.current {
                UnitQuiz.record(q, correct: true, profile: &p, now: t0)
                quiz.answer(q.answerIndex)
            }
            XCTAssertEqual(quiz.percent, 100)
            UnitQuiz.finish(quiz, profile: &p, now: t0)
            XCTAssertEqual(p.extrasOrEmpty.quizBest?[unit.id], 100)
            XCTAssertTrue(Achievement.evaluate(&p, libraries: l, now: t0).contains { $0.id == "a-quiz" }, id)
        }
    }

    func testQuizKeepsBestScore() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        finishFirstQuest(&p, lib)
        var good = UnitQuiz(unit: lib.units[0], profile: p, library: lib, seed: 1)
        while let q = good.current { good.answer(q.answerIndex) }
        UnitQuiz.finish(good, profile: &p)
        var bad = UnitQuiz(unit: lib.units[0], profile: p, library: lib, seed: 1)
        while let q = bad.current { bad.answer((q.answerIndex + 1) % q.options.count) }
        UnitQuiz.finish(bad, profile: &p)
        XCTAssertEqual(bad.percent, 0)
        XCTAssertEqual(p.extrasOrEmpty.quizBest?[lib.units[0].id], 100)
    }

    // 6. Weekly goal

    func testWeeklyGoalCountsDaysAndPaysOncePerWeek() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let monday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        XCTAssertEqual(WeeklyGoal.goal(p), WeeklyGoal.defaultDays)
        WeeklyGoal.setGoal(2, profile: &p)
        WeeklyGoal.setGoal(4, profile: &p)   // not a choice: ignored
        XCTAssertEqual(WeeklyGoal.goal(p), 2)
        XCTAssertEqual(WeeklyGoal.daysPracticed(p, now: monday, calendar: cal), 0)
        XCTAssertEqual(WeeklyGoal.claim(&p, now: monday, calendar: cal), 0)
        let tuesday = monday.addingTimeInterval(86400)
        p.log.activitiesByDay[ActivityLog.dayKey(monday, calendar: cal)] = 2
        p.log.minutesByDay[ActivityLog.dayKey(tuesday, calendar: cal)] = 6
        XCTAssertEqual(WeeklyGoal.daysPracticed(p, now: tuesday, calendar: cal), 2)
        XCTAssertTrue(WeeklyGoal.message(p, now: tuesday, calendar: cal).contains("Claim"))
        XCTAssertEqual(WeeklyGoal.claim(&p, now: tuesday, calendar: cal), WeeklyGoal.xp)
        XCTAssertEqual(WeeklyGoal.claim(&p, now: tuesday, calendar: cal), 0, "once a week")
        let nextWeek = monday.addingTimeInterval(86400 * 7)
        XCTAssertFalse(WeeklyGoal.isClaimed(p, now: nextWeek, calendar: cal), "fresh start")
        XCTAssertFalse(WeeklyGoal.message(p, now: nextWeek, calendar: cal).lowercased().contains("miss"), "no guilt")
        let l = try libs()
        XCTAssertTrue(Achievement.evaluate(&p, libraries: l, now: tuesday).contains { $0.id == "a-weekly" })
    }

    // 7. Reminders

    func testReminderPlanDefaultsOffAndOldSavesLoad() throws {
        let plan = ReminderPlan()
        XCTAssertFalse(plan.enabled, "off until a parent turns it on")
        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.timeLabel, "5:00 PM")
        var bad = plan; bad.weekdays = []
        XCTAssertFalse(bad.isValid)
        for m in ReminderPlan.messages { XCTAssertFalse(m.contains("{")) }
        // A v0.7 save has no reminders, quizBest or weekly fields.
        var save = FamilySave()
        save.profiles = [PlayerProfile(nickname: "", ageBand: .age11to12, variant: "es-MX")]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(save)) as! [String: Any]
        var parent = json["parent"] as! [String: Any]; parent.removeValue(forKey: "reminders"); json["parent"] = parent
        let back = try JSONDecoder().decode(FamilySave.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.parent.reminders)
        XCTAssertFalse(back.parent.reminderPlan.enabled)
    }

    // 8. Weekly report

    func testWeeklyReportSummarizesWithoutPrivateDetails() throws {
        let l = try libs(), lib = try XCTUnwrap(l["en-es"])
        var p = learner(lib)
        p.nickname = "Kit"
        finishFirstQuest(&p, lib)
        p.log.minutesByDay[ActivityLog.dayKey(t0)] = 12.4
        p.log.activitiesByDay[ActivityLog.dayKey(t0)] = 5
        let r = WeeklyReport.make(p, libraries: l, now: t0)
        XCTAssertTrue(r.title.contains("Kit"))
        XCTAssertTrue(r.text.contains("Days practiced: 1 of 7"))
        XCTAssertTrue(r.text.contains("about 12 minutes"))
        XCTAssertTrue(r.text.contains("Spanish: 1/"))
        XCTAssertTrue(r.text.contains("Nothing was sent anywhere"))
    }

    // 10. Achievements

    func testNewAchievementsAreUniqueAndStarsCount() throws {
        XCTAssertGreaterThanOrEqual(Achievement.all.count, 14)
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
        let l = try libs(), lib = try XCTUnwrap(l["en-it"])
        var p = learner(lib)
        for item in lib.allItems.prefix(5) { StarredWords.toggle(item.id, profile: &p) }
        XCTAssertTrue(Achievement.evaluate(&p, libraries: l, now: t0).contains { $0.id == "a-starred" })
    }
}
