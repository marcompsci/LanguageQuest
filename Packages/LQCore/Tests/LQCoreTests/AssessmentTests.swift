import XCTest
@testable import LQCore

final class AnswerCheckerTests: XCTestCase {
    let accepted: [VText] = [VText("el jugo", overrides: ["es-ES": "el zumo"]), "jugo"]

    func testExactAndPunctuationInsensitive() {
        XCTAssertEqual(AnswerChecker.check("El jugo", accepted: accepted, variant: "es-MX"), .correct)
        XCTAssertEqual(AnswerChecker.check("  ¡el   JUGO!  ", accepted: accepted, variant: "es-MX"), .correct)
        XCTAssertEqual(AnswerChecker.check("¿Cuánto cuesta?", accepted: ["¿Cuánto cuesta?"], variant: "es-MX"), .correct)
    }

    func testMissingAccentsCountAsCorrectWithNote() {
        let v = AnswerChecker.check("cuanto cuesta", accepted: ["¿Cuánto cuesta?"], variant: "es-MX")
        XCTAssertEqual(v, .correctMissingAccents(expected: "¿Cuánto cuesta?"))
        XCTAssertTrue(v.isCorrect)
        XCTAssertTrue(AnswerChecker.check("dieciseis", accepted: ["dieciséis"], variant: "es-MX").isCorrect)
    }

    func testOtherRegionFormIsAcceptedAndExplained() {
        let v = AnswerChecker.check("el zumo", accepted: accepted, variant: "es-MX")
        XCTAssertEqual(v, .correctOtherRegion(expected: "el jugo", variant: "es-ES"))
        XCTAssertTrue(v.isCorrect)
        // And the Latin American base is accepted for a Spain learner.
        XCTAssertEqual(AnswerChecker.check("el jugo", accepted: [accepted[0]], variant: "es-ES"),
                       .correctOtherRegion(expected: "el zumo", variant: "es-419"))
    }

    func testOneTypoIsAlmostNotCorrect() {
        let v = AnswerChecker.check("amarilo", accepted: ["amarillo"], variant: "es-MX")
        XCTAssertEqual(v, .almost(expected: "amarillo"))
        XCTAssertFalse(v.isCorrect)
        // Short words get no typo leeway (dos vs tos would change meaning).
        XCTAssertEqual(AnswerChecker.check("tos", accepted: ["dos"], variant: "es-MX"), .incorrect(expected: "dos"))
    }

    func testWrongAndEmpty() {
        XCTAssertFalse(AnswerChecker.check("leche", accepted: accepted, variant: "es-MX").isCorrect)
        XCTAssertFalse(AnswerChecker.check("   ", accepted: accepted, variant: "es-MX").isCorrect)
    }

    func testTiles() {
        let tiles: [VText] = ["Tengo", "un", "perro"]
        XCTAssertEqual(AnswerChecker.checkTiles(["Tengo", "un", "perro"], correct: tiles, variant: "es-MX"), .correct)
        XCTAssertEqual(AnswerChecker.checkTiles(["un", "Tengo", "perro"], correct: tiles, variant: "es-MX"), .almost(expected: "Tengo un perro"))
        XCTAssertFalse(AnswerChecker.checkTiles(["Tengo", "una", "perro"], correct: tiles, variant: "es-MX").isCorrect)
    }

    func testFeedbackIsNeverEmptyAndNeverPunitive() {
        let verdicts: [AnswerVerdict] = [.correct, .correctMissingAccents(expected: "x"), .correctOtherRegion(expected: "x", variant: "es-ES"),
                                         .almost(expected: "x"), .incorrect(expected: "x")]
        for v in verdicts {
            let f = AnswerChecker.feedback(for: v) { _ in "Spain" }
            XCTAssertFalse(f.isEmpty)
            for bad in ["wrong!", "fail", "you lose", "game over", "stupid"] { XCTAssertFalse(f.lowercased().contains(bad)) }
        }
    }
}

final class SchedulerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func days(_ n: Double) -> Date { t0.addingTimeInterval(n * SpacedScheduler.day) }

    func testGrades() {
        XCTAssertEqual(SpacedScheduler.grade(.init(correct: true, attempts: 1, responseSeconds: 3)), 5)
        XCTAssertEqual(SpacedScheduler.grade(.init(correct: true, attempts: 1, responseSeconds: 20)), 4)
        XCTAssertEqual(SpacedScheduler.grade(.init(correct: true, attempts: 2)), 3)
        XCTAssertEqual(SpacedScheduler.grade(.init(correct: true, attempts: 1, usedHint: true)), 3)
        XCTAssertEqual(SpacedScheduler.grade(.init(correct: false)), 1)
    }

    func testIntervalsGrowWithSuccess() {
        var m = MemoryState(due: t0)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: t0)
        XCTAssertEqual(m.intervalDays, 1)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: days(1))
        XCTAssertEqual(m.intervalDays, 3)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: days(4))
        XCTAssertGreaterThanOrEqual(m.intervalDays, 7)
        XCTAssertEqual(m.due, days(4).addingTimeInterval(m.intervalDays * SpacedScheduler.day))
    }

    func testMissComesBackSoonAndLowersEase() {
        var m = MemoryState(due: t0)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: t0)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: days(1))
        let ease = m.ease
        m = SpacedScheduler.update(m, with: .init(correct: false), now: days(4))
        XCTAssertEqual(m.reps, 0)
        XCTAssertEqual(m.lapses, 1)
        XCTAssertLessThan(m.ease, ease)
        XCTAssertEqual(m.due, days(4).addingTimeInterval(SpacedScheduler.relearnDelay))
    }

    func testEffortfulAnswerGrowsLessThanEasyOne() {
        var a = MemoryState(due: t0), b = MemoryState(due: t0)
        for (i, d) in [0.0, 1, 4].enumerated() {
            a = SpacedScheduler.update(a, with: .init(correct: true, attempts: 1, responseSeconds: 2), now: days(d))
            b = SpacedScheduler.update(b, with: .init(correct: true, attempts: i == 2 ? 3 : 1, responseSeconds: 2), now: days(d))
        }
        XCTAssertGreaterThan(a.intervalDays, b.intervalDays)
    }

    func testDelayedRetentionCountsOnlyAfterADay() {
        var m = MemoryState(due: t0)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: t0)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: t0.addingTimeInterval(3600))
        XCTAssertEqual(m.delayedChecks, 0)
        m = SpacedScheduler.update(m, with: .init(correct: true), now: days(2))
        XCTAssertEqual(m.delayedChecks, 1)
        XCTAssertEqual(m.delayedCorrect, 1)
        m = SpacedScheduler.update(m, with: .init(correct: false), now: days(9))
        XCTAssertEqual(m.delayedRetention, 0.5)
    }

    func testIntervalCapped() {
        var m = MemoryState(due: t0)
        var now = t0
        for _ in 0..<40 {
            m = SpacedScheduler.update(m, with: .init(correct: true), now: now)
            now = m.due
        }
        XCTAssertLessThanOrEqual(m.intervalDays, SpacedScheduler.maxIntervalDays)
        XCTAssertGreaterThanOrEqual(m.ease, SpacedScheduler.minEase)
        XCTAssertLessThanOrEqual(m.ease, SpacedScheduler.maxEase)
    }

    func testComprehensionAndProductionAreSeparate() {
        var k = ItemKnowledge(now: t0)
        for d in [0.0, 1, 4, 12] { k.record(.init(correct: true), track: .comprehension, now: days(d)) }
        XCTAssertTrue(k.comprehensionMastered)
        XCTAssertFalse(k.productionMastered)
        XCTAssertEqual(k.level, .understood)
        // Guided production (tiles) never counts as spontaneous use.
        for d in [13.0, 14, 18] { k.record(.init(correct: true), track: .guidedProduction, now: days(d)) }
        XCTAssertFalse(k.productionMastered)
        k.record(.init(correct: true), track: .spontaneousProduction, now: days(30))
        k.record(.init(correct: true), track: .spontaneousProduction, now: days(30.01))
        XCTAssertTrue(k.productionMastered)
        XCTAssertEqual(k.level, .canUse)
    }

    func testCrammingInOneSittingDoesNotCountAsMastery() {
        var k = ItemKnowledge(now: t0)
        for i in 0..<20 {
            k.record(.init(correct: true), track: .comprehension, now: t0.addingTimeInterval(Double(i) * 60))
            k.record(.init(correct: true), track: .spontaneousProduction, now: t0.addingTimeInterval(Double(i) * 60))
        }
        XCTAssertFalse(k.comprehensionMastered)
        XCTAssertFalse(k.productionMastered)
        XCTAssertLessThan(k.level, .understood)
    }

    func testTrackClassification() {
        func a(_ t: ActivityType, _ p: PracticeKind) -> Activity {
            Activity(id: "x", type: t, skill: .reading, mode: .interpretive, practice: p, prompt: "p", target: nil, targetEnglish: nil,
                     choices: nil, answer: nil, tiles: nil, distractors: nil, accepted: nil, pairs: nil, sentence: nil, items: ["i"], hint: "h", explanation: "e")
        }
        XCTAssertEqual(PracticeTrack.of(a(.listenChoose, .independent)), .comprehension)
        XCTAssertEqual(PracticeTrack.of(a(.buildSentence, .guided)), .guidedProduction)
        XCTAssertEqual(PracticeTrack.of(a(.typeAnswer, .independent)), .spontaneousProduction)
        XCTAssertEqual(PracticeTrack.of(a(.speak, .guided)), .guidedProduction)
        XCTAssertEqual(PracticeTrack.of(a(.speak, .independent)), .spontaneousProduction)
    }

    func testDueQueueAndRetentionCandidates() {
        var k: [String: ItemKnowledge] = [:]
        var a = ItemKnowledge(now: t0); a.record(.init(correct: true), track: .comprehension, now: t0); a.record(.init(correct: true), track: .comprehension, now: days(1))
        var b = ItemKnowledge(now: t0); b.record(.init(correct: false), track: .comprehension, now: t0)
        k["a"] = a; k["b"] = b
        let due = ReviewPlanner.dueItems(k, now: days(1).addingTimeInterval(60))
        XCTAssertTrue(due.contains("b"))
        XCTAssertTrue(ReviewPlanner.retentionCandidates(k, now: days(3)).isEmpty)
        XCTAssertEqual(ReviewPlanner.retentionCandidates(k, now: days(9)), ["a"])
        XCTAssertEqual(ReviewPlanner.dueItems(k, now: days(30)), ReviewPlanner.dueItems(k, now: days(30)), "deterministic")
    }
}

final class AssessmentFlowTests: XCTestCase {
    var lib: ContentLibrary!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    override func setUpWithError() throws { lib = try ContentLibrary.bundledSpanish() }

    func testPlacementBeginner() {
        var s = PlacementSession(library: lib)
        while !s.finished { s.answer(correct: false) }
        XCTAssertTrue(s.placedOut.isEmpty)
        XCTAssertEqual(s.answers.count, PlacementSession.questionsPerUnit)
    }

    func testPlacementPlacesOutKnownUnitsOnly() {
        var s = PlacementSession(library: lib)
        // Ace unit 1, miss unit 2.
        while !s.finished { s.answer(correct: s.currentUnit?.order == 1) }
        XCTAssertEqual(s.placedOut, ["u1-saludos"])
        var p = PlayerProfile(nickname: "A", ageBand: .age16plus, variant: "es-MX", now: t0)
        s.apply(to: &p, now: t0)
        XCTAssertEqual(p.assessments.last?.kind, .baseline)
        let prog = Progression(library: lib)
        XCTAssertTrue(prog.isUnitUnlocked(lib.units[1], p.progress, plan: .explorer))
        XCTAssertFalse(prog.isUnitUnlocked(lib.units[2], p.progress, plan: .explorer))
    }

    func testPlacementAllCorrectFinishesCourse() {
        var s = PlacementSession(library: lib)
        while !s.finished { s.answer(correct: true) }
        XCTAssertEqual(s.placedOut.count, 3)
    }

    func testPlacementIgnoresAgeAndCanBeSkipped() {
        var s = PlacementSession(library: lib)
        s.skip()
        XCTAssertTrue(s.finished)
        XCTAssertNil(s.currentQuestion)
    }

    func testPlacementNeverAsksSpeakingWithoutMicrophone() {
        for u in lib.units {
            for a in u.masteryCheck.activities.prefix(PlacementSession.questionsPerUnit) { XCTAssertNotEqual(a.type, .speak, a.id) }
        }
    }

    func testMasteryCheckGrading() throws {
        let u = lib.units[0]
        let answers = u.masteryCheck.activities.enumerated().map { AssessmentAnswer(activity: $1, correct: $0 != 0) }
        let r = MasteryCheckGrader.grade(unit: u, answers: answers, now: t0)
        XCTAssertEqual(r.passed, true) // 4/5 = 80%
        var p = PlayerProfile(nickname: "", ageBand: .age11to12, variant: "es-MX", now: t0)
        MasteryCheckGrader.apply(r, unit: u, badge: Catalog.masteryBadge(forUnitOrder: 1), profile: &p)
        XCTAssertTrue(p.progress.passedMasteryChecks.contains(u.masteryCheck.id))
        XCTAssertTrue(p.rewards.badges.contains("badge-mastery-u1"))
        let fail = MasteryCheckGrader.grade(unit: u, answers: answers.map { AssessmentAnswer(activity: $0.activity, correct: false) }, now: t0)
        XCTAssertEqual(fail.passed, false)
        XCTAssertEqual(fail.overall.total, 5)
    }

    func testRetentionCheckBecomesDueAfterAWeek() {
        var p = PlayerProfile(nickname: "", ageBand: .age11to12, variant: "es-MX", now: t0)
        let prog = Progression(library: lib)
        let q = lib.allQuests[0]
        for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) }
        for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0.addingTimeInterval(86_400)) }
        XCTAssertFalse(RetentionCheck.isDue(p, now: t0.addingTimeInterval(2 * 86_400)))
        let later = t0.addingTimeInterval(10 * 86_400)
        XCTAssertTrue(RetentionCheck.isDue(p, now: later))
        let quiz = RetentionCheck.build(p, library: lib, now: later)
        XCTAssertFalse(quiz.isEmpty)
        XCTAssertTrue(quiz.allSatisfy { PracticeTrack.of($0) == .comprehension })
        p.assessments.append(AssessmentResult(kind: .retention, date: later, unitId: nil, bySkill: [:], passed: nil))
        XCTAssertFalse(RetentionCheck.isDue(p, now: later.addingTimeInterval(86_400)))
    }

    func testParentReportSeparatesActivityFromMastery() {
        var p = PlayerProfile(nickname: "", ageBand: .age11to12, variant: "es-MX", now: t0)
        let prog = Progression(library: lib)
        // Lots of play in one day: XP and activity rise, mastery does not.
        for q in lib.units[0].quests { for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) } }
        let r = ParentReport.build(p, library: lib, now: t0)
        XCTAssertGreaterThan(r.usage.xp, 0)
        XCTAssertGreaterThan(r.usage.activitiesLast7Days, 0)
        XCTAssertTrue(r.mastery.understood.isEmpty)
        XCTAssertTrue(r.mastery.canUse.isEmpty)
        XCTAssertEqual(r.units[0].questsDone, 5)
        XCTAssertFalse(r.offlineSuggestions.isEmpty)
    }
}
