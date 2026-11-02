import XCTest
@testable import LQCore

final class ContentTests: XCTestCase {
    var lib: ContentLibrary!

    override func setUpWithError() throws {
        lib = try ContentLibrary.bundledSpanish()
    }

    func testLoadsThreeUnitsAndFifteenQuests() {
        XCTAssertEqual(lib.units.count, 3)
        XCTAssertEqual(lib.allQuests.count, 15)
        XCTAssertEqual(lib.units.map(\.order), [1, 2, 3])
    }

    func testValidatorFindsNoErrors() {
        let problems = ContentValidator.validate(lib)
        let errors = problems.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, errors.map(\.message).joined(separator: "\n"))
    }

    func testEveryQuestHasThreeActivityTypes() {
        for q in lib.allQuests {
            XCTAssertGreaterThanOrEqual(Set(q.activities.map(\.type)).count, 3, q.id)
        }
    }

    func testEveryUnitCoversAllFourSkillsAndThreeModes() {
        for u in lib.units {
            let acts = u.quests.flatMap(\.activities)
            XCTAssertEqual(Set(acts.map(\.skill)), Set(Skill.allCases), u.id)
            XCTAssertEqual(Set(acts.map(\.mode)), Set(CommunicationMode.allCases), u.id)
            XCTAssertTrue(acts.contains { $0.practice == .guided }, u.id)
            XCTAssertTrue(acts.contains { $0.practice == .independent }, u.id)
        }
    }

    func testContentIsMarkedUnreviewedSoReleaseValidationFails() {
        // Honesty check: authored content must not pass release validation until linguists sign off.
        let release = ContentValidator.validate(lib, releaseBuild: true).filter { $0.severity == .error }
        XCTAssertFalse(release.isEmpty)
        XCTAssertTrue(lib.units.allSatisfy { $0.review.text < .linguistReviewed })
    }

    func testEveryDialogueCanBePlayedToTheEnd() {
        for q in lib.allQuests {
            var r = DialogueRunner(q.dialogue)
            r.autoplay()
            XCTAssertTrue(r.isFinished, q.id)
            XCTAssertTrue(r.effects.contains(DialogueEffect(kind: .startQuest, value: q.id)), "\(q.id) dialogue should start its quest")
        }
    }

    func testWrongDialogueReplyStaysOnLineWithFeedback() throws {
        let q = try XCTUnwrap(lib.quest("u1-q1")?.quest)
        var r = DialogueRunner(q.dialogue)
        r.advance()
        XCTAssertTrue(r.awaitingChoice)
        let wrong = try XCTUnwrap(r.current?.choices?.firstIndex { $0.correct == false })
        XCTAssertFalse(r.choose(wrong))
        XCTAssertEqual(r.current?.id, "n2")
        XCTAssertNotNil(r.lastFeedback)
        let right = try XCTUnwrap(r.current?.choices?.firstIndex { $0.correct == true })
        XCTAssertTrue(r.choose(right))
        XCTAssertNil(r.lastFeedback)
    }

    func testVariantsResolve() throws {
        let banana = try XCTUnwrap(lib.item("platano"))
        XCTAssertEqual(banana.target.text(for: "es-MX"), "el plátano")
        XCTAssertEqual(banana.target.text(for: "es-AR"), "la banana")
        XCTAssertEqual(banana.target.text(for: "es-PR"), "el guineo")
        XCTAssertEqual(banana.target.text(for: "es-CO"), "el banano")
        XCTAssertEqual(try XCTUnwrap(lib.item("jugo")).target.text(for: "es-ES"), "el zumo")
        XCTAssertEqual(try XCTUnwrap(lib.item("como-te-llamas")).target.text(for: "es-AR"), "¿Cómo te llamás?")
        XCTAssertEqual(lib.course.variants.count, 6)
        XCTAssertTrue(lib.course.variant("es-AR")?.usesVoseo == true)
    }

    func testCurrencyFollowsVariant() throws {
        let a = try XCTUnwrap(lib.activity("u3-q4-a2"))
        XCTAssertTrue(a.target!.text(for: "es-MX").contains("pesos"))
        XCTAssertTrue(a.target!.text(for: "es-ES").contains("euros"))
        XCTAssertTrue(a.target!.text(for: "es-PR").contains("dólares"))
    }

    func testEveryPictureHasAltText() {
        for i in lib.allItems where i.picture != nil { XCTAssertFalse((i.altText ?? "").isEmpty, i.id) }
        for a in lib.units.flatMap(\.allActivities) {
            for c in a.choices ?? [] where c.picture != nil { XCTAssertFalse((c.altText ?? "").isEmpty, a.id) }
        }
    }

    func testEveryListeningActivityHasTextForSubtitlesAndDeafLearners() {
        for a in lib.units.flatMap(\.allActivities) where a.type == .listenChoose || a.type == .dialogueReply || a.type == .speak {
            XCTAssertNotNil(a.target, a.id)
            XCTAssertNotNil(a.targetEnglish, a.id)
        }
    }

    func testEveryAnswerKeyIsAcceptedByItsOwnChecker() {
        // Every accepted answer and every built sentence must check as correct in every variant.
        for a in lib.units.flatMap(\.allActivities) {
            for v in lib.course.variants.map(\.id) {
                if let acc = a.accepted {
                    for x in acc {
                        XCTAssertTrue(AnswerChecker.check(x.text(for: v), accepted: acc, variant: v).isCorrect, "\(a.id) \(v)")
                    }
                }
                if let tiles = a.tiles {
                    XCTAssertEqual(AnswerChecker.checkTiles(tiles.map { $0.text(for: v) }, correct: tiles, variant: v), .correct, "\(a.id) \(v)")
                }
            }
        }
    }

    func testNoTwoChoicesMatchTheSameAnswerInAnyVariant() {
        for a in lib.units.flatMap(\.allActivities) {
            guard let cs = a.choices else { continue }
            for v in lib.course.variants.map(\.id) {
                let forms = cs.map { AnswerChecker.normalize($0.text.text(for: v)) }
                XCTAssertEqual(Set(forms).count, forms.count, "\(a.id) \(v)")
            }
        }
    }

    func testValidatorCatchesBrokenContent() throws {
        var u = lib.units[0]
        u.quests[0].activities[0].answer = "zzz"
        u.quests[1].activities = Array(u.quests[1].activities.prefix(1))
        u.quests[2].dialogue.nodes[0].next = "missing"
        u.vocabulary[0].target = VText("TODO")
        let broken = ContentLibrary(course: lib.course, units: [u] + lib.units.dropFirst())
        let msgs = ContentValidator.validate(broken).filter { $0.severity == .error }.map(\.message).joined(separator: "\n")
        XCTAssertTrue(msgs.contains("answer is not one of the choices"))
        XCTAssertTrue(msgs.contains("activity types"))
        XCTAssertTrue(msgs.contains("missing"))
        XCTAssertTrue(msgs.contains("Placeholder"))
    }

    func testVTextDecodesBothShapesAndRoundTrips() throws {
        let json = #"["hola", {"base": "el jugo", "es-ES": "el zumo"}]"#.data(using: .utf8)!
        let v = try JSONDecoder().decode([VText].self, from: json)
        XCTAssertEqual(v[0].base, "hola")
        XCTAssertEqual(v[1].text(for: "es-ES"), "el zumo")
        let again = try JSONDecoder().decode([VText].self, from: JSONEncoder().encode(v))
        XCTAssertEqual(again, v)
        XCTAssertThrowsError(try JSONDecoder().decode(VText.self, from: #"{"es-ES": "x"}"#.data(using: .utf8)!))
    }
}
