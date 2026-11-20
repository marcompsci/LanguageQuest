import XCTest
@testable import LQCore

final class V11Tests: XCTestCase {
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
    func answerAll(_ quiz: inout RetentionQuiz, _ lib: ContentLibrary) {
        let v = lib.course.defaultVariant
        while let cur = quiz.current {
            if cur.kind == .typeIt { quiz.answer(typed: cur.word.text(for: v), variant: v, context: lib.checkContext) }
            else { quiz.answer(choice: cur.answerIndex, variant: v, context: lib.checkContext) }
        }
    }

    // 1
    func testTodayPathTicksOff() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let prog = Progression(library: lib)
        var steps = TodayPath.steps(p, library: lib, progression: prog, plan: .explorer, now: t0, calendar: cal)
        XCTAssertEqual(steps.map(\.kind), [.memoryCheck, .quest, .review])
        XCTAssertTrue(steps[0].done, "nothing to check before any words are met")
        XCTAssertFalse(steps[1].done)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        var quiz = RetentionQuiz(kind: .lesson(questId: lib.units[0].quests[0].id), profile: p, library: lib, now: t0, seed: 1)
        answerAll(&quiz, lib)
        RetentionQuiz.finish(quiz, profile: &p, library: lib, now: t0)
        steps = TodayPath.steps(p, library: lib, progression: prog, plan: .explorer, now: t0, calendar: cal)
        XCTAssertTrue(steps[1].done, "a lesson quiz today ticks the quest step")
        XCTAssertFalse(steps[0].done)
        TodayPath.mark(.memoryCheck, profile: &p, now: t0, calendar: cal)
        XCTAssertTrue(TodayPath.steps(p, library: lib, progression: prog, plan: .explorer, now: t0, calendar: cal)[0].done)
        XCTAssertFalse(TodayPath.steps(p, library: lib, progression: prog, plan: .explorer, now: t0.addingTimeInterval(86400), calendar: cal)[1].done, "a new day starts fresh")
    }

    // 2
    func testWarmUpUsesOnlyNewWordsAndRecordsNothing() throws {
        for (id, lib) in try libs() {
            var p = learner(lib)
            let q = lib.units[0].quests[0]
            XCTAssertTrue(WarmUp.isOffered(q, profile: p), id)
            let qs = WarmUp.questions(q, profile: p, library: lib, seed: 3)
            XCTAssertFalse(qs.isEmpty, id)
            XCTAssertLessThanOrEqual(qs.count, WarmUp.count)
            XCTAssertTrue(qs.allSatisfy { RetentionQuiz.lessonItems(q).contains($0.itemId) && $0.kind == .meaning })
            WarmUp.finished(profile: &p)
            XCTAssertTrue(p.knowledge.isEmpty, "\(id): guesses are not mistakes")
            play(q, &p, lib, at: t0)
            p.progress.completedQuests.insert(q.id)
            XCTAssertFalse(WarmUp.isOffered(q, profile: p))
        }
    }

    // 4
    func testNextReviewText() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let id = lib.allItems[0].id
        XCTAssertNil(RetentionQuiz.nextReviewDays(id, profile: p, now: t0))
        PracticeRecorder.record(itemId: id, outcome: ReviewOutcome(correct: true), track: .comprehension, profile: &p, now: t0)
        let d = try XCTUnwrap(RetentionQuiz.nextReviewDays(id, profile: p, now: t0, calendar: cal))
        XCTAssertNotNil(RetentionQuiz.nextReviewText(d))
        XCTAssertEqual(RetentionQuiz.nextReviewText(1), "You'll see this again tomorrow.")
        XCTAssertEqual(RetentionQuiz.nextReviewText(4), "You'll see this again in 4 days.")
    }

    // 5
    func testMemoryHookCountsOnce() throws {
        let lib = try ContentLibrary.bundled("en-fr")
        var p = learner(lib)
        let id = lib.allItems[0].id
        WordNotes.addHook("sounds like 'bone jure'", for: id, profile: &p)
        WordNotes.addHook("changed my mind", for: id, profile: &p)
        XCTAssertEqual(p.metaOrEmpty.counters[MetaEvent.hookWritten], 1)
        XCTAssertEqual(WordNotes.note(id, in: p), "changed my mind")
    }

    // 6 + 7
    func testMemoryCheckUsesSentencesAndCanBeLonger() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        for q in lib.units[0].quests { p.progress.startedQuests.insert(q.id); play(q, &p, lib, at: t0) }
        // Some word has a sentence to blank out.
        let withSentence = lib.units[0].allItems.compactMap { item in Cloze.sentence(for: item, profile: p, library: lib).map { (item, $0) } }
        XCTAssertFalse(withSentence.isEmpty)
        for (item, c) in withSentence.prefix(10) {
            XCTAssertTrue(c.text.contains(Cloze.blank), item.id)
            XCTAssertFalse(c.text.lowercased().contains(item.target.text(for: lib.course.defaultVariant).lowercased() + " "), "\(item.id) word removed")
        }
        let later = t0.addingTimeInterval(10 * 86400)
        var found = false
        for seed in UInt64(1)...40 {
            let check = RetentionQuiz(kind: .memoryCheck, profile: p, library: lib, now: later, seed: seed)
            if let c = check.questions.first(where: { $0.kind == .cloze }) {
                found = true
                XCTAssertNotNil(c.context); XCTAssertTrue(c.context!.contains(Cloze.blank))
                XCTAssertEqual(c.options[c.answerIndex], c.word.text(for: lib.course.defaultVariant))
                break
            }
        }
        XCTAssertTrue(found, "memory checks include fill-in-the-blank questions")
        var long = RetentionQuiz(kind: .memoryCheck, profile: p, library: lib, now: later, seed: 2, count: MemoryCheckLength.long.rawValue)
        XCTAssertEqual(long.questions.count, 10)
        answerAll(&long, lib)
        XCTAssertEqual(long.correctCount, 10)
    }

    // 8 + 9
    func testStreakCalendarAndRewardOutfits() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let mon = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 18)))
        for d in 0..<7 {
            let m = Streak.recordPractice(&p, now: mon.addingTimeInterval(Double(d) * 86400), calendar: cal)
            if let m { StreakRewards.grant(m, profile: &p) }
        }
        XCTAssertTrue(p.rewards.ownedCosmetics.contains("scarf-flame"))
        XCTAssertNotNil(Catalog.cosmetic("scarf-flame"))
        XCTAssertNotNil(Catalog.cosmetic("laurel-gold"))
        XCTAssertNil(StreakRewards.grant(7, profile: &p), "given once")
        let days = Streak.calendarDays(p, now: mon.addingTimeInterval(6 * 86400), calendar: cal)
        XCTAssertEqual(days.count, 28)
        XCTAssertEqual(days.last?.mark, .practiced)
    }

    // 10
    func testWeeklyRecapShowsEarlyInWeekUntilClosed() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let lastWed = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12)))
        p.log.activitiesByDay[ActivityLog.dayKey(lastWed, calendar: cal)] = 3
        let thisMon = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let r = try XCTUnwrap(WeeklyRecap.make(p, now: thisMon, calendar: cal))
        XCTAssertEqual(r.daysPracticed, 1)
        XCTAssertTrue(r.line.hasPrefix("Last week: 1 day"))
        XCTAssertNil(WeeklyRecap.make(p, now: thisMon.addingTimeInterval(4 * 86400), calendar: cal), "only early in the week")
        WeeklyRecap.dismiss(r, profile: &p)
        XCTAssertNil(WeeklyRecap.make(p, now: thisMon, calendar: cal))
    }

    // 11 + 12
    func testPersonalBestsAndParentSummary() throws {
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        play(lib.units[0].quests[0], &p, lib, at: t0)
        for i in 0..<3 {
            var q = RetentionQuiz(kind: .memoryCheck, profile: p, library: lib, now: t0.addingTimeInterval(Double(i) * 3600), seed: UInt64(i + 1))
            answerAll(&q, lib)
            RetentionQuiz.finish(q, profile: &p, library: lib, now: t0.addingTimeInterval(Double(i) * 3600))
        }
        let b = PersonalBests.make(p, now: t0.addingTimeInterval(4 * 3600), calendar: cal)
        XCTAssertEqual(b.perfectRun, 3)
        XCTAssertEqual(b.longestStreak, 1)
        XCTAssertGreaterThan(b.mostWordsInADay, 0)
        XCTAssertTrue(Achievement.evaluate(&p, libraries: try libs(), now: t0).contains { $0.id == "a-perfect3" })
        let s = LearningSummary.make(p, now: t0.addingTimeInterval(4 * 3600), calendar: cal)
        XCTAssertEqual(s.quizzesThisWeek, 3)
        XCTAssertEqual(s.averageThisWeek, 100)
        XCTAssertNotNil(s.rememberedNow)
    }

    // 13
    func testTrialNoticeTiming() {
        let end = t0.addingTimeInterval(7 * 86400)
        XCTAssertEqual(TrialNotice.reminderDate(trialEnds: end, isTrial: true, now: t0), end.addingTimeInterval(-2 * 86400))
        XCTAssertNil(TrialNotice.reminderDate(trialEnds: end, isTrial: false, now: t0), "paid periods don't get it")
        XCTAssertNil(TrialNotice.reminderDate(trialEnds: t0.addingTimeInterval(86400), isTrial: true, now: t0), "too late")
        XCTAssertTrue(TrialNotice.body.contains("cancel"))
    }

    // 16 + 17
    func testAccentKeysAndFirstLetterHint() throws {
        XCTAssertTrue(AccentKeys.keys(for: "en-es").contains("ñ"))
        XCTAssertTrue(AccentKeys.keys(for: "en-de").contains("ß"))
        XCTAssertTrue(AccentKeys.keys(for: "en-ja").isEmpty)
        let lib = try ContentLibrary.bundled("en-es")
        var p = learner(lib)
        let q = lib.units[0].quests[0]
        play(q, &p, lib, at: t0)
        var quiz = RetentionQuiz(kind: .lesson(questId: q.id), profile: p, library: lib, now: t0, seed: 5)
        let v = lib.course.defaultVariant
        while let cur = quiz.current, cur.kind != .typeIt { quiz.answer(choice: cur.answerIndex, variant: v, context: lib.checkContext) }
        let typed = try XCTUnwrap(quiz.current)
        let hint = RetentionQuiz.firstLetterHint(typed, variant: v)
        XCTAssertEqual(hint.first, typed.word.text(for: v).first)
        quiz.useHint()
        XCTAssertTrue(quiz.answer(typed: typed.word.text(for: v), variant: v, context: lib.checkContext))
        XCTAssertEqual(quiz.firstTry[typed.itemId], false, "hinted answers don't score")
        XCTAssertFalse(quiz.relearnQueue.contains { $0.itemId == typed.itemId }, "but they aren't retried either")
    }

    // 19 + saves
    func testAchievementsAndOldSavesLoad() throws {
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
        for id in ["a-warmup", "a-hooks", "a-streak30", "a-perfect3"] { XCTAssertTrue(Achievement.all.contains { $0.id == id }) }
        var k = ItemKnowledge(now: t0)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(k)) as! [String: Any]
        json.removeValue(forKey: "firstSeen")
        k = try JSONDecoder().decode(ItemKnowledge.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(k.firstSeen)
    }
}
