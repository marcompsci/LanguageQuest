import XCTest
@testable import LQCore

final class V10Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_900_000_000)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func libs() throws -> [String: ContentLibrary] {
        Dictionary(uniqueKeysWithValues: try ContentLibrary.bundledCourseIds.map { ($0, try ContentLibrary.bundled($0)) })
    }
    func learner(_ lib: ContentLibrary) -> PlayerProfile {
        PlayerProfile(nickname: "", ageBand: .age13to15, courseId: lib.course.id, variant: lib.course.defaultVariant, now: t0)
    }
    /// Plays a quest's activities so its words are in the memory model.
    func play(_ q: Quest, _ p: inout PlayerProfile, _ lib: ContentLibrary, correct: Bool = true, at: Date) {
        let prog = Progression(library: lib)
        for a in q.activities { prog.complete(activity: a, outcome: .init(correct: correct), profile: &p, now: at) }
    }

    // 1. Recall model
    func testRecallHalvesEveryHalfLife() throws {
        var m = MemoryState(due: t0)
        XCTAssertNil(RecallModel.probability(m, now: t0), "never practiced")
        m.lastReviewed = t0; m.intervalDays = 2
        XCTAssertEqual(RecallModel.probability(m, now: t0)!, 1, accuracy: 1e-9)
        XCTAssertEqual(RecallModel.probability(m, now: t0.addingTimeInterval(2 * 86400))!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(RecallModel.probability(m, now: t0.addingTimeInterval(4 * 86400))!, 0.25, accuracy: 1e-9)
    }

    // 2. Lesson quiz: 5 questions, mostly the lesson's words, easier to harder
    func testLessonQuizInEveryLanguage() throws {
        for (id, lib) in try libs() {
            var p = learner(lib)
            let q = lib.units[0].quests[0]
            play(q, &p, lib, at: t0)
            let quiz = RetentionQuiz(kind: .lesson(questId: q.id), profile: p, library: lib, now: t0, seed: 3)
            XCTAssertEqual(quiz.questions.count, RetentionQuiz.size, id)
            let lessonSet = Set(RetentionQuiz.lessonItems(q))
            XCTAssertGreaterThanOrEqual(quiz.questions.filter { lessonSet.contains($0.itemId) }.count, min(3, lessonSet.count), id)
            XCTAssertEqual(quiz.questions.map(\.kind), [.meaning, .listen, .pickWord, .typeIt, .typeIt], id)
            XCTAssertEqual(Set(quiz.questions.map(\.itemId)).count, quiz.questions.count, "\(id): no word twice")
            for qq in quiz.questions where qq.kind != .typeIt {
                XCTAssertEqual(Set(qq.options).count, qq.options.count, "\(id) duplicate options")
                XCTAssertGreaterThanOrEqual(qq.options.count, 3, id)
            }
        }
    }

    func testQuizPrioritizesFadingAndMissedWords() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let early = lib.units[0].quests[0]
        play(early, &p, lib, at: t0)
        // One word was missed several times and is long overdue: it must be in the memory check.
        let weak = RetentionQuiz.lessonItems(early)[0]
        for _ in 0..<3 { PracticeRecorder.record(itemId: weak, outcome: ReviewOutcome(correct: false), track: .comprehension, profile: &p, now: t0) }
        let later = t0.addingTimeInterval(20 * 86400)
        let check = RetentionQuiz(kind: .memoryCheck, profile: p, library: lib, now: later, seed: 1)
        XCTAssertTrue(check.questions.contains { $0.itemId == weak })
        XCTAssertGreaterThan(RetentionQuiz.priority(weak, profile: p, lessonItems: [], now: later),
                             RetentionQuiz.priority(RetentionQuiz.lessonItems(early).last!, profile: p, lessonItems: [], now: t0))
    }

    // 3. Successive relearning inside the quiz + scoring on first try only
    func testMissedQuestionsComeBackUntilRight() throws {
        let lib = try ContentLibrary.bundled("en-fr")
        var p = learner(lib)
        let q = lib.units[0].quests[0]
        play(q, &p, lib, at: t0)
        var quiz = RetentionQuiz(kind: .lesson(questId: q.id), profile: p, library: lib, now: t0, seed: 7)
        let v = lib.course.defaultVariant
        // Miss the first question, get the rest right.
        let first = try XCTUnwrap(quiz.current)
        XCTAssertFalse(quiz.answer(choice: (first.answerIndex + 1) % first.options.count, variant: v, context: lib.checkContext))
        while quiz.index < quiz.total, let cur = quiz.current {
            if cur.kind == .typeIt { quiz.answer(typed: cur.word.text(for: v), variant: v, context: lib.checkContext) }
            else { quiz.answer(choice: cur.answerIndex, variant: v, context: lib.checkContext) }
        }
        XCTAssertTrue(quiz.isRelearning)
        XCTAssertEqual(quiz.current?.itemId, first.itemId)
        let retry = try XCTUnwrap(quiz.current)
        quiz.answer(choice: retry.answerIndex, variant: v, context: lib.checkContext)
        XCTAssertTrue(quiz.isFinished)
        XCTAssertEqual(quiz.correctCount, quiz.total - 1, "the score counts first tries")
        XCTAssertEqual(quiz.missedIds, [first.itemId])
        let rec = RetentionQuiz.finish(quiz, profile: &p, library: lib, now: t0)
        XCTAssertEqual(rec.record.percent, 80)
        XCTAssertEqual(p.extrasOrEmpty.quizHistory?.count, 1)
        XCTAssertEqual(Streak.state(p).current, 1, "a finished quiz counts for the streak")
    }

    func testRetriesEndEvenIfAlwaysWrong() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let q = lib.units[0].quests[0]
        play(q, &p, lib, at: t0)
        var quiz = RetentionQuiz(kind: .lesson(questId: q.id), profile: p, library: lib, now: t0, seed: 9)
        let v = lib.course.defaultVariant
        var steps = 0
        while let cur = quiz.current, steps < 100 {
            if cur.kind == .typeIt { quiz.answer(typed: "", variant: v, context: lib.checkContext) }
            else { quiz.answer(choice: (cur.answerIndex + 1) % cur.options.count, variant: v, context: lib.checkContext) }
            steps += 1
        }
        XCTAssertTrue(quiz.isFinished)
        XCTAssertLessThanOrEqual(steps, RetentionQuiz.size * (1 + RetentionQuiz.maxRetries))
        XCTAssertEqual(quiz.correctCount, 0)
    }

    func testTypedAnswersForgiveAccents() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let q = lib.units[0].quests[0]
        play(q, &p, lib, at: t0)
        var quiz = RetentionQuiz(kind: .lesson(questId: q.id), profile: p, library: lib, now: t0, seed: 2)
        let v = lib.course.defaultVariant
        while let cur = quiz.current, cur.kind != .typeIt { quiz.answer(choice: cur.answerIndex, variant: v, context: lib.checkContext) }
        let typed = try XCTUnwrap(quiz.current)
        let plain = typed.word.text(for: v).folding(options: .diacriticInsensitive, locale: nil)
        XCTAssertTrue(quiz.answer(typed: plain, variant: v, context: lib.checkContext))
    }

    // 4. Progress over time
    func testRetentionReportTracksWeeksAndLockedInWords() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let q = lib.units[0].quests[0]
        play(q, &p, lib, at: t0)
        for w in 0..<3 {
            let when = t0.addingTimeInterval(Double(w) * 7 * 86400)
            var quiz = RetentionQuiz(kind: .memoryCheck, profile: p, library: lib, now: when, seed: UInt64(w + 1))
            let v = lib.course.defaultVariant
            while let cur = quiz.current {
                if cur.kind == .typeIt { quiz.answer(typed: cur.word.text(for: v), variant: v, context: lib.checkContext) }
                else { quiz.answer(choice: cur.answerIndex, variant: v, context: lib.checkContext) }
            }
            RetentionQuiz.finish(quiz, profile: &p, library: lib, now: when)
        }
        let r = RetentionReport.make(p, now: t0.addingTimeInterval(14 * 86400 + 60), calendar: cal)
        XCTAssertEqual(r.memoryChecks, 3)
        XCTAssertEqual(r.weeks.count, 8)
        XCTAssertEqual(r.weeks.compactMap(\.averagePercent).count, 3)
        XCTAssertEqual(r.averageLast10, 100)
        XCTAssertGreaterThan(r.wordsMet, 0)
        XCTAssertNotNil(r.predictedRetention)
        var k = ItemKnowledge(now: t0)
        k.comprehension.delayedCorrect = 3; k.comprehension.lastReviewed = t0; k.comprehension.intervalDays = 10
        XCTAssertTrue(RecallModel.isLockedIn(k, now: t0.addingTimeInterval(86400)))
        XCTAssertFalse(RecallModel.isLockedIn(k, now: t0.addingTimeInterval(40 * 86400)), "a locked-in word can fade again")
    }

    // 5. Gentle streak
    func testStreakCountsFreezesAndRestartsKindly() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let mon = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 18)))
        func day(_ n: Int) -> Date { mon.addingTimeInterval(Double(n) * 86400) }
        XCTAssertEqual(Streak.status(p, now: mon, calendar: cal), .none)
        XCTAssertEqual(Streak.recordPractice(&p, now: day(0), calendar: cal), nil)
        XCTAssertNil(Streak.recordPractice(&p, now: day(0).addingTimeInterval(60), calendar: cal), "twice a day counts once")
        Streak.recordPractice(&p, now: day(1), calendar: cal)
        XCTAssertEqual(Streak.recordPractice(&p, now: day(2), calendar: cal), 3, "3-day milestone")
        XCTAssertEqual(Streak.status(p, now: day(3), calendar: cal), .waitingToday)
        // Miss Thu + Fri: two freezes cover it.
        Streak.recordPractice(&p, now: day(5), calendar: cal)
        XCTAssertEqual(Streak.state(p).current, 4)
        XCTAssertEqual(Streak.state(p).freezesLeft, 0)
        XCTAssertEqual(Streak.state(p).frozenDays.count, 2)
        // A new week refills freezes.
        Streak.recordPractice(&p, now: day(7), calendar: cal)
        XCTAssertEqual(Streak.state(p).current, 5)
        XCTAssertEqual(Streak.state(p).freezesLeft, 1)
        // A long break restarts at 1, keeps the best, and the message is kind.
        XCTAssertEqual(Streak.current(p, now: day(20), calendar: cal), 0)
        let msg = Streak.message(p, now: day(20), calendar: cal).lowercased()
        XCTAssertTrue(msg.contains("fresh start"))
        XCTAssertFalse(msg.contains("lost") || msg.contains("lose") || msg.contains("broke"))
        Streak.recordPractice(&p, now: day(20), calendar: cal)
        XCTAssertEqual(Streak.state(p).current, 1)
        XCTAssertEqual(Streak.state(p).longest, 5)
    }

    // 6. Smart reminders
    func testReminderPlanFollowsHabitsAndBacksOff() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let base = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 7, minute: 15)))
        // Plays around 7:15 am, 7:30 am... → reminders at the usual time, never before 8:00.
        for d in 0..<5 { SmartReminders.noteSessionStart(&p, now: base.addingTimeInterval(Double(d) * 86400 + Double(d) * 300)) }
        XCTAssertEqual(SmartReminders.preferredMinutes(p, calendar: cal), 8 * 60)
        // Late-night players get reminded by 8:30 pm at the latest.
        var night = learner(lib)
        for d in 0..<5 { SmartReminders.noteSessionStart(&night, now: base.addingTimeInterval(Double(d) * 86400 + 15 * 3600)) }
        XCTAssertEqual(SmartReminders.preferredMinutes(night, calendar: cal), 20 * 60 + 30)

        let now = base.addingTimeInterval(4 * 86400 + 3600)
        let plan = SmartReminders.plan(p, now: now, dueWords: 4, hasNewLesson: true, calendar: cal)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.date > now })
        XCTAssertEqual(plan.count, SmartReminders.dayOffsets.count - 1, "today's time already passed")
        for r in plan {
            let h = cal.component(.hour, from: r.date)
            XCTAssertTrue((8...20).contains(h))
            XCTAssertFalse(r.body.lowercased().contains("lose"))
        }
        // Days 3+ away use the comeback message.
        XCTAssertEqual(plan.last?.templateId, "comeback")
        // Practicing today means no reminder today.
        Streak.recordPractice(&p, now: now, calendar: cal)
        let morning = cal.startOfDay(for: now).addingTimeInterval(60)
        XCTAssertFalse(SmartReminders.plan(p, now: morning, dueWords: 0, hasNewLesson: false, calendar: cal)
            .contains { cal.isDate($0.date, inSameDayAs: now) })
    }

    func testReminderPickerLearnsAndRests() {
        var stats: [String: TemplateStats] = [:]
        var f = TemplateStats(); f.sent = 10; f.opened = 6; stats["friend"] = f
        var sh = TemplateStats(); sh.sent = 10; sh.opened = 1; stats["short"] = sh
        let t = SmartReminders.pick([.any], stats: stats, at: t0, used: [])
        XCTAssertEqual(t.id, "friend", "the message that brings this player back wins")
        let rested = SmartReminders.pick([.any], stats: stats, at: t0, used: ["friend"])
        XCTAssertNotEqual(rested.id, "friend", "a message used last time rests")
        XCTAssertEqual(SmartReminders.pick([.dueWords], stats: [:], at: t0, used: []).id, "due")
        // Only reminders whose time passed count as sent; tapping one counts as opened.
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX", now: t0)
        let plan = [PlannedReminder(date: t0.addingTimeInterval(3600), templateId: "due", body: "x"),
                    PlannedReminder(date: t0.addingTimeInterval(86400 * 3), templateId: "friend", body: "y")]
        SmartReminders.storePlan(plan, profile: &p, now: t0)
        SmartReminders.storePlan([], profile: &p, now: t0.addingTimeInterval(7200))
        XCTAssertEqual(p.metaOrEmpty.reminderStats?["due"]?.sent, 1)
        XCTAssertNil(p.metaOrEmpty.reminderStats?["friend"])
        SmartReminders.noteOpened("due", profile: &p)
        XCTAssertEqual(p.metaOrEmpty.reminderStats?["due"]?.opened, 1)
    }

    // 7. Plus
    func testPlusGamesAndWelcomeBack() throws {
        XCTAssertFalse(FeatureGate.isGameAvailable("memory", plan: .explorer))
        XCTAssertTrue(FeatureGate.isGameAvailable("memory", plan: .familyPlus))
        XCTAssertTrue(FeatureGate.isGameAvailable("listenType", plan: .explorer), "learning games stay free")
        XCTAssertTrue(PlusOffer.alwaysFree.joined().contains("Reviews, lesson quizzes"))

        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        Streak.recordPractice(&p, now: t0, calendar: cal)
        XCTAssertNil(WelcomeBack.make(p, now: t0.addingTimeInterval(86400), calendar: cal))
        let w = try XCTUnwrap(WelcomeBack.make(p, now: t0.addingTimeInterval(9 * 86400), calendar: cal))
        XCTAssertEqual(w.daysAway, 9)
        XCTAssertGreaterThan(w.fadingWords, 0)
    }

    // 8. Achievements + old saves
    func testAchievementsAndOldSaveLoads() throws {
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
        XCTAssertTrue(Achievement.all.contains { $0.id == "a-streak7" })
        var save = FamilySave()
        save.profiles = [PlayerProfile(nickname: "", ageBand: .age11to12, variant: "es-MX")]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(save)) as! [String: Any]
        var parent = json["parent"] as! [String: Any]; parent.removeValue(forKey: "remindersBlocked"); json["parent"] = parent
        let back = try JSONDecoder().decode(FamilySave.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.parent.remindersBlocked)
        XCTAssertFalse(back.profiles[0].settings.smartRemindersOn)
    }
}
