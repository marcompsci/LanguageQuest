import XCTest
@testable import LQCore

final class V06Tests: XCTestCase {
    func testFlashcardChoicesInEveryCourse() throws {
        for id in ContentLibrary.bundledCourseIds {
            let lib = try ContentLibrary.bundled(id)
            for item in lib.allItems {
                let card = Flashcard(itemId: item.id, front: item.target, back: item.english, picture: item.picture)
                let c = FlashcardChoices.make(for: card, library: lib, seed: 7)
                XCTAssertEqual(c.options.count, 4, "\(id) \(item.id)")
                XCTAssertEqual(Set(c.options.map(AnswerChecker.normalize)).count, 4, "\(id) \(item.id) duplicate meanings")
                XCTAssertEqual(c.options[c.answerIndex], item.english)
            }
        }
        // Numbers get number distractors.
        let lib = try ContentLibrary.bundled("en-de")
        let n3 = try XCTUnwrap(lib.item("n3"))
        let c = FlashcardChoices.make(for: Flashcard(itemId: "n3", front: n3.target, back: n3.english, picture: nil), library: lib, seed: 1)
        XCTAssertTrue(c.options.allSatisfy { $0.contains("(") }, "\(c.options)")
    }

    func testBonusLessonForNewAndReturningLearners() throws {
        for id in ContentLibrary.bundledCourseIds {
            let lib = try ContentLibrary.bundled(id)
            var p = PlayerProfile(nickname: "", ageBand: .age11to12, courseId: id, variant: lib.course.defaultVariant)
            let t0 = Date(timeIntervalSince1970: 1_900_000_000)
            let fresh = BonusLesson.build(p, library: lib, plan: .explorer, now: t0)
            XCTAssertEqual(fresh.activities.count, BonusLesson.size, id)
            XCTAssertTrue(fresh.activities.allSatisfy { $0.id.hasPrefix("bonus-") }, "new learners don't skip quests")
            for a in fresh.activities {
                let cs = try XCTUnwrap(a.choices)
                XCTAssertEqual(Set(cs.map { $0.text.base }).count, cs.count, "\(id) \(a.id)")
                XCTAssertTrue(cs.contains { $0.id == a.answer && $0.text.base == a.targetEnglish })
            }
            // Same day → same lesson.
            XCTAssertEqual(BonusLesson.build(p, library: lib, plan: .explorer, now: t0).activities.map(\.id), fresh.activities.map(\.id))

            let prog = Progression(library: lib)
            for a in lib.allQuests[0].activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) }
            let back = BonusLesson.build(p, library: lib, plan: .explorer, now: t0.addingTimeInterval(86400 * 4))
            XCTAssertEqual(back.activities.count, BonusLesson.size, id)
            XCTAssertTrue(back.activities.contains { !$0.id.hasPrefix("bonus-") }, "returning learners review finished quests")
            XCTAssertFalse(back.activities.contains { $0.type == .speak })
            let finishedIds = Set(lib.allQuests[0].activities.map(\.id))
            XCTAssertTrue(back.activities.filter { !$0.id.hasPrefix("bonus-") }.allSatisfy { finishedIds.contains($0.id) }, "never pulls from unstarted quests")
        }
    }

    func testBonusXPOncePerDay() {
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        XCTAssertEqual(BonusLesson.claim(&p, day: "2030-01-01"), BonusLesson.bonusXP)
        XCTAssertEqual(BonusLesson.claim(&p, day: "2030-01-01"), 0)
        XCTAssertEqual(BonusLesson.claim(&p, day: "2030-01-02"), BonusLesson.bonusXP)
        XCTAssertEqual(p.rewards.xp, BonusLesson.bonusXP * 2)
    }

    func testWriteOut() throws {
        let de = try ContentLibrary.bundled("en-de")
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: "en-de", variant: "de-DE")
        p.knowledge["n5"] = ItemKnowledge(now: Date())
        let words = WriteOut.words(p, library: de)
        XCTAssertEqual(words.first?.itemId, "n5", "met words first")
        XCTAssertTrue(words.allSatisfy { $0.text.count <= 16 && !$0.text.contains("…") })
        XCTAssertTrue(WriteOut.supportsCursive(de.course))
        XCTAssertFalse(WriteOut.supportsCursive(try ContentLibrary.bundled("en-zh").course))
        XCTAssertNotNil(WriteOut.words(p, library: try ContentLibrary.bundled("en-am")).first?.romanized)

        XCTAssertTrue(WriteOut.matches(recognized: ["Funf"], word: "fünf"))
        XCTAssertTrue(WriteOut.matches(recognized: ["noise", "Guten Morgan"], word: "Guten Morgen"), "one slip forgiven")
        XCTAssertFalse(WriteOut.matches(recognized: ["drei"], word: "zwei"))
        XCTAssertFalse(WriteOut.matches(recognized: [], word: "eins"))
        WriteOut.record("n5", profile: &p); WriteOut.record("n5", profile: &p)
        XCTAssertEqual(p.extrasOrEmpty.wordsWritten, ["n5"])
    }
}

final class SpeedDuelTests: XCTestCase {
    func testSpeedDuelRewardsFastAnswersAndNeedsThem() throws {
        let lib = try ContentLibrary.bundled("en-es")
        let p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        let o = BattleRoster.opponents[0]
        var fast = WordBattle(opponent: o, library: lib, profile: p, seed: 3)
        fast.mode = .speed
        while let q = fast.current { fast.answer(q.answerIndex, library: lib, variant: "es-MX", seconds: 2) }
        XCTAssertTrue(fast.playerWon)
        var slow = WordBattle(opponent: o, library: lib, profile: p, seed: 3)
        slow.mode = .speed
        while let q = slow.current { slow.answer(q.answerIndex, library: lib, variant: "es-MX", seconds: 9) }
        XCTAssertFalse(slow.playerWon, "the speed rival is tougher: slow perfect answers aren't enough")
        XCTAssertEqual(slow.stars, 3, "stars still count right answers, not speed")
        var classic = WordBattle(opponent: o, library: lib, profile: p, seed: 3)
        while let q = classic.current { classic.answer(q.answerIndex, library: lib, variant: "es-MX", seconds: 60) }
        XCTAssertTrue(classic.playerWon, "classic has no timer")
    }
}
