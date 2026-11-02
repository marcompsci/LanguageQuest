import XCTest
@testable import LQCore

final class V05Tests: XCTestCase {
    func libs() throws -> [String: ContentLibrary] {
        Dictionary(uniqueKeysWithValues: try ContentLibrary.bundledCourseIds.map { ($0, try ContentLibrary.bundled($0)) })
    }

    func testMenuSections() throws {
        let l = try libs()
        let p = PlayerProfile(nickname: "", ageBand: .age11to12, variant: "es-MX")
        let s = CourseOverview.summaries(p, libraries: l, order: ContentLibrary.bundledCourseIds)
        func ids(_ c: CourseCategory) -> [String] { s.filter { $0.category == c }.map(\.courseId) }
        XCTAssertEqual(ids(.modern), ["en-es", "en-fr", "en-ja", "en-de", "en-it", "en-zh"])
        XCTAssertEqual(ids(.african), ["en-yo", "en-he", "en-egy", "en-am"])
        XCTAssertEqual(ids(.ancient), ["en-grc", "en-la", "en-hbo"])
        XCTAssertEqual(CourseCategory.african.title, "African Languages")
        XCTAssertEqual(CourseCategory.ancient.title, "Old Languages")
        XCTAssertEqual(l["en-es"]?.course.nativeName, "Español")
        for sum in s { XCTAssertNotEqual(sum.language, sum.nativeName, sum.courseId) }
    }

    /// Every string a learner sees in a non-Latin course has a pronunciation line.
    func testEveryNonLatinStringRomanizes() throws {
        for lib in try libs().values where lib.course.script == .transliterated {
            let c = lib.course
            var strings: [String] = []
            for u in lib.units {
                strings += u.allItems.map { $0.target.base }
                strings += u.allItems.compactMap { $0.example?.target.base }
                for q in u.quests {
                    for n in q.dialogue.nodes {
                        strings.append(n.line.base)
                        strings += (n.choices ?? []).map { $0.text.base }
                    }
                }
                for a in u.allActivities {
                    if let t = a.target { strings.append(t.base) }
                    if a.type == .dialogueReply { strings += (a.choices ?? []).map { $0.text.base } }
                    strings += (a.pairs ?? []).map { $0.target.base }
                }
            }
            let lang = c.targetLanguage
            strings += StarterVillage.signs.map { $0.text(lang) }
            strings += StarterVillage.treasures.map { $0.word(lang).base }.filter { w in !w.unicodeScalars.allSatisfy(\.isASCII) }
            let ph = lib.phrases
            strings += [ph.helloAgain.base, ph.yesPlease.base, ph.duel.base, ph.notNow.base, ph.letsGo.base, ph.seeYou.base,
                        ph.comeBackSoon.base, ph.veryGood, ph.questComplete, ph.youWon, ph.goodDuel, ph.lostWord, ph.excellent]
            for s in strings {
                let r = c.romanize(s)
                XCTAssertNotNil(r, "\(c.id): no romanization for \(s)")
                if let r {
                    let folded = r.folding(options: .diacriticInsensitive, locale: nil)
                    XCTAssertTrue(folded.unicodeScalars.allSatisfy { $0.value < 0x0250 || $0 == "…" }, "\(c.id): \(s) → \(r) should be Latin letters")
                }
            }
        }
    }

    func testRomanizeKeepsNamePlaceholders() throws {
        let zh = try ContentLibrary.bundled("en-zh").course
        XCTAssertEqual(zh.romanize("很高兴认识你，{name}！"), "hěn gāoxìng rènshi nǐ, {name}!")
        XCTAssertNil(try ContentLibrary.bundled("en-de").course.romanize("Hallo"))
        let he = try ContentLibrary.bundled("en-he").course
        XCTAssertEqual(he.romanize("שלום"), "shalom")
        XCTAssertTrue(he.rightToLeft ?? false)
    }

    func testTypedAnswersAcceptScriptOrRomanization() throws {
        let zh = try ContentLibrary.bundled("en-zh")
        let thanks: [VText] = ["谢谢", "xièxie"]
        XCTAssertEqual(AnswerChecker.check("谢谢", accepted: thanks, variant: "zh-CN", context: zh.checkContext), .correct)
        XCTAssertEqual(AnswerChecker.check("xièxie", accepted: thanks, variant: "zh-CN", context: zh.checkContext), .correct)
        XCTAssertTrue(AnswerChecker.check("xiexie", accepted: thanks, variant: "zh-CN", context: zh.checkContext).isCorrect, "tones optional, with a note")
        let yo: [VText] = ["O ṣé"]
        XCTAssertTrue(AnswerChecker.check("o se", accepted: yo, variant: "yo-NG").isCorrect, "Yoruba without tone marks still counts")
    }

    func testRecentLessonCardAcrossLanguages() throws {
        let l = try libs()
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: "en-de", variant: "de-DE")
        let t0 = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertNil(RecentLessonCard.compute(p, libraries: l, now: t0, seed: 1))
        let de = l["en-de"]!
        let prog = Progression(library: de)
        let q1 = de.allQuests[0]
        for a in q1.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: t0) }
        XCTAssertEqual(p.recentLesson?.questId, q1.id)
        var card = try XCTUnwrap(RecentLessonCard.compute(p, libraries: l, now: t0, seed: 1))
        XCTAssertEqual(card.language, "German")
        XCTAssertEqual(card.flag, "🇩🇪")
        let fc = try XCTUnwrap(card.card)
        XCTAssertNotNil(p.knowledge[fc.itemId], "quick card uses a word already practiced")

        // Switch to Italian: the card still shows German and records into German.
        p.switchCourse(to: "en-it", defaultVariant: "it-IT")
        card = try XCTUnwrap(RecentLessonCard.compute(p, libraries: l, now: t0.addingTimeInterval(86400 * 3), seed: 2))
        XCTAssertEqual(card.courseId, "en-de")
        let c2 = try XCTUnwrap(card.card)
        let before = p.otherCourses?["en-de"]?.knowledge[c2.itemId]?.comprehension.reviewCount ?? 0
        RecentLessonCard.record(c2, courseId: "en-de", knewIt: true, profile: &p, libraries: l, now: t0.addingTimeInterval(86400 * 3))
        XCTAssertEqual(p.courseId, "en-it", "stays in Italian")
        XCTAssertEqual(p.otherCourses?["en-de"]?.knowledge[c2.itemId]?.comprehension.reviewCount, before + 1)
        XCTAssertTrue(p.knowledge.isEmpty, "nothing leaked into Italian")
        let back = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.recentLesson, p.recentLesson)
    }

    func testSpeechFallbackIsDeclared() throws {
        for id in ["en-am", "en-yo", "en-egy"] {
            let v = try XCTUnwrap(ContentLibrary.bundled(id).course.variants.first)
            XCTAssertFalse(v.romanizedVoiceLocales?.isEmpty ?? true, "\(id) needs a voice to read its romanization")
        }
    }
}
