import XCTest
@testable import LQCore

final class MultiCourseTests: XCTestCase {
    func allCourses() throws -> [ContentLibrary] { try ContentLibrary.bundledCourseIds.map { try ContentLibrary.bundled($0) } }

    func testEveryCourseLoadsAndValidates() throws {
        let libs = try allCourses()
        XCTAssertEqual(libs.map(\.course.targetLanguage), ["es", "fr", "ja"])
        for lib in libs {
            let errors = ContentValidator.validate(lib).filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "\(lib.course.id):\n" + errors.map(\.message).joined(separator: "\n"))
            XCTAssertEqual(lib.units.count, 3, lib.course.id)
            XCTAssertEqual(lib.allQuests.count, 15, lib.course.id)
            XCTAssertNotNil(lib.course.variant(lib.course.defaultVariant))
            XCTAssertFalse(ContentValidator.validate(lib, releaseBuild: true).filter { $0.severity == .error }.isEmpty,
                           "\(lib.course.id) is unreviewed, so release validation must fail")
            for u in lib.units {
                let acts = u.quests.flatMap(\.activities)
                XCTAssertEqual(Set(acts.map(\.skill)), Set(Skill.allCases), u.id)
                for q in u.quests { XCTAssertGreaterThanOrEqual(Set(q.activities.map(\.type)).count, 3, q.id) }
            }
        }
    }

    func testEveryDialogueFinishesAndStartsItsQuest() throws {
        for lib in try allCourses() {
            for q in lib.allQuests {
                var r = DialogueRunner(q.dialogue)
                r.autoplay()
                XCTAssertTrue(r.isFinished, q.id)
                XCTAssertTrue(r.effects.contains(DialogueEffect(kind: .startQuest, value: q.id)), q.id)
                XCTAssertNotNil(StarterVillage.npc(q.npc), q.id)
            }
        }
    }

    func testEveryAnswerKeyPassesItsOwnCheckerInEveryVariant() throws {
        for lib in try allCourses() {
            let ctx = lib.checkContext
            for a in lib.units.flatMap(\.allActivities) {
                for v in lib.course.variants.map(\.id) {
                    for x in a.accepted ?? [] {
                        XCTAssertTrue(AnswerChecker.check(x.text(for: v), accepted: a.accepted!, variant: v, context: ctx).isCorrect, "\(a.id) \(v)")
                    }
                    if let tiles = a.tiles {
                        XCTAssertEqual(AnswerChecker.checkTiles(tiles.map { $0.text(for: v) }, correct: tiles, variant: v), .correct, "\(a.id) \(v)")
                    }
                    if let cs = a.choices {
                        let forms = cs.map { AnswerChecker.normalize($0.text.text(for: v)) }
                        XCTAssertEqual(Set(forms).count, forms.count, "\(a.id) \(v) duplicate choices")
                    }
                }
            }
        }
    }

    func testJapaneseRomanizesCompletely() throws {
        let lib = try ContentLibrary.bundled("en-ja")
        XCTAssertEqual(lib.course.script, .kana)
        var texts: [String] = lib.allItems.flatMap(\.target.allForms)
        for a in lib.units.flatMap(\.allActivities) {
            texts += [a.target, a.sentence].compactMap { $0?.base }
            texts += (a.tiles ?? []).map(\.base) + (a.choices ?? []).map(\.text.base) + (a.accepted ?? []).map(\.base)
        }
        for q in lib.allQuests { for n in q.dialogue.nodes { texts.append(n.line.base); texts += (n.choices ?? []).map(\.text.base) } }
        for t in texts where Kana.containsKana(t) {
            let r = try XCTUnwrap(lib.course.romanize(t))
            XCTAssertFalse(Kana.containsKana(r), "\(t) → \(r)")
            XCTAssertFalse(r.isEmpty)
        }
        XCTAssertNil(try ContentLibrary.bundled("en-fr").course.romanize("bonjour"))
    }

    func testKanaToRomaji() {
        XCTAssertEqual(Kana.word("ありがとう"), "arigatou")
        XCTAssertEqual(Kana.word("きゃく"), "kyaku")
        XCTAssertEqual(Kana.word("しゃしん"), "shashin")
        XCTAssertEqual(Kana.word("ちょっと"), "chotto")
        XCTAssertEqual(Kana.word("がっこう"), "gakkou")
        XCTAssertEqual(Kana.word("まっちゃ"), "matcha")
        XCTAssertEqual(Kana.word("じゅう"), "juu")
        XCTAssertEqual(Kana.word("チーズ"), "chiizu")
        XCTAssertEqual(Kana.word("ジュース"), "juusu")
        XCTAssertEqual(Kana.romanize("わたし は マテオ です。"), "watashi wa mateo desu.")
        XCTAssertEqual(Kana.romanize("パン を ください"), "pan o kudasai")
        XCTAssertEqual(Kana.romanize("むら へ ようこそ！"), "mura e youkoso!")
        XCTAssertEqual(Kana.romanize("こんにちは", overrides: ["こんにちは": "konnichiwa"]), "konnichiwa")
        XCTAssertEqual(Kana.romanize("「おはよう」 と"), "ohayou to")
    }

    func testJapaneseAcceptsKanaOrRomajiAndForgivesLongVowels() throws {
        let ctx = try ContentLibrary.bundled("en-ja").checkContext
        let acc: [VText] = ["ありがとう"]
        for input in ["ありがとう", "arigatou", "arigato", "Arigatō", "ARIGATOO"] {
            XCTAssertTrue(AnswerChecker.check(input, accepted: acc, variant: "ja-JP", context: ctx).isCorrect, input)
        }
        XCTAssertFalse(AnswerChecker.check("sayounara", accepted: acc, variant: "ja-JP", context: ctx).isCorrect)
        XCTAssertTrue(AnswerChecker.check("konnichiwa", accepted: ["こんにちは"], variant: "ja-JP", context: ctx).isCorrect)
        XCTAssertTrue(AnswerChecker.check("ikura desu ka", accepted: ["いくら です か？"], variant: "ja-JP", context: ctx).isCorrect)
        XCTAssertTrue(AnswerChecker.check("onesan", accepted: ["おねえさん"], variant: "ja-JP", context: ctx).isCorrect)
        XCTAssertEqual(AnswerChecker.check("arigoto", accepted: acc, variant: "ja-JP", context: ctx), .almost(expected: "ありがとう"))
        // Dakuten matter: か (ka) is not が (ga).
        XCTAssertFalse(AnswerChecker.equivalent("かめ", "がめ", context: ctx))
        XCTAssertTrue(AnswerChecker.equivalent("かめ", "kame", context: ctx))
    }

    func testFrenchVariantsAndAccents() throws {
        let lib = try ContentLibrary.bundled("en-fr")
        let ctx = lib.checkContext
        XCTAssertEqual(lib.item("de-rien")?.target.text(for: "fr-CA"), "bienvenue")
        XCTAssertEqual(lib.item("desayuno")?.target.text(for: "fr-CA"), "le déjeuner")
        XCTAssertEqual(AnswerChecker.check("le dejeuner", accepted: [lib.item("desayuno")!.target], variant: "fr-CA", context: ctx),
                       .correctMissingAccents(expected: "le déjeuner"))
        XCTAssertEqual(AnswerChecker.check("le petit-déjeuner", accepted: [lib.item("desayuno")!.target], variant: "fr-CA", context: ctx),
                       .correctOtherRegion(expected: "le déjeuner", variant: "fr-FR"))
        XCTAssertTrue(lib.activity("fu3-q4-a2")!.target!.text(for: "fr-CA").contains("dollars"))
    }

    func testSideGamesWorkInEveryCourse() throws {
        for lib in try allCourses() {
            let variant = lib.course.defaultVariant
            let p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: lib.course.id, variant: variant)
            for g in MarketRush.goods { XCTAssertNotNil(lib.item(g), "\(lib.course.id) needs market item \(g)") }
            var m = MarketRush(library: lib, seed: 4)
            while let o = m.current { XCTAssertTrue(m.checkPayment(MarketRush.fewestCoins(for: o.total))); m.completeRound() }
            var s = WordScramble(library: lib, profile: p, seed: 5)
            XCTAssertEqual(s.puzzles.count, WordScramble.rounds, lib.course.id)
            while let pz = s.current { XCTAssertTrue(s.submit(pz.answer), "\(lib.course.id) \(pz.answer)") }
            for o in BattleRoster.opponents {
                var b = WordBattle(opponent: o, library: lib, profile: p, seed: 6)
                XCTAssertEqual(b.questions.count, WordBattle.rounds)
                while let q = b.current { b.answer(q.answerIndex, library: lib, variant: variant) }
                XCTAssertTrue(b.playerWon)
                XCTAssertNotNil(lib.phrases.duelGreetings[o.id], "\(lib.course.id) greeting for \(o.id)")
            }
            XCTAssertFalse(lib.phrases.offlineIdeas.isEmpty)
        }
    }

    func testSignsAndTreasuresSpeakEveryLanguage() {
        for lang in ["es", "fr", "ja"] {
            for s in StarterVillage.signs { XCTAssertFalse(s.text(lang).isEmpty) }
            for t in StarterVillage.treasures {
                XCTAssertFalse(t.word(lang).base.isEmpty)
                XCTAssertFalse(t.fact(lang).isEmpty)
                if lang != "es" { XCTAssertNotEqual(t.word(lang), t.spanish, "\(t.id) has a \(lang) word") }
            }
        }
    }

    func testSwitchingCoursesKeepsEachCoursesProgress() throws {
        var p = PlayerProfile(nickname: "Mo", ageBand: .age10to12, variant: "es-MX")
        p.progress.completedQuests = ["u1-q1"]
        p.knowledge["hola"] = ItemKnowledge(now: Date())
        p.rewards.xp = 50
        p.switchCourse(to: "en-ja", defaultVariant: "ja-JP")
        XCTAssertEqual(p.courseId, "en-ja")
        XCTAssertEqual(p.variant, "ja-JP")
        XCTAssertTrue(p.progress.completedQuests.isEmpty)
        XCTAssertTrue(p.knowledge.isEmpty)
        XCTAssertEqual(p.rewards.xp, 50, "XP and rewards are shared")
        p.progress.completedQuests = ["ju1-q1"]
        p.switchCourse(to: "en-es", defaultVariant: "es-419")
        XCTAssertEqual(p.variant, "es-MX", "returns to the learner's chosen variant")
        XCTAssertEqual(p.progress.completedQuests, ["u1-q1"])
        XCTAssertNotNil(p.knowledge["hola"])
        XCTAssertEqual(p.startedCourses, ["en-es", "en-ja"])
        // Round-trips through a save.
        let back = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.otherCourses?["en-ja"]?.progress.completedQuests, ["ju1-q1"])
    }

    func testYenPricesScale() throws {
        let yen = try XCTUnwrap(ContentLibrary.bundled("en-ja").course.variants.first?.currency)
        XCTAssertEqual(yen.scale, 100)
        XCTAssertEqual(try XCTUnwrap(ContentLibrary.bundled("en-es").course.variants.first?.currency).scale, 1)
    }
}
