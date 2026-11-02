import XCTest
@testable import LQCore

final class V04Tests: XCTestCase {
    func libs() throws -> [String: ContentLibrary] {
        Dictionary(uniqueKeysWithValues: try ContentLibrary.bundledCourseIds.map { ($0, try ContentLibrary.bundled($0)) })
    }

    func testCourseSummariesUseParkedProgress() throws {
        let l = try libs()
        var p = PlayerProfile(nickname: "", ageBand: .age10to12, variant: "es-AR")
        let prog = Progression(library: l["en-es"]!)
        for a in l["en-es"]!.units[0].quests[0].activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: Date()) }
        p.switchCourse(to: "en-fr", defaultVariant: "fr-CA")
        let s = CourseOverview.summaries(p, libraries: l, order: ContentLibrary.bundledCourseIds)
        XCTAssertEqual(s.map(\.courseId), ["en-es", "en-fr", "en-ja"])
        XCTAssertEqual(s[0].questsDone, 1, "Spanish progress shown while French is active")
        XCTAssertEqual(s[0].flag, "🇦🇷", "flag follows the parked variant")
        XCTAssertGreaterThan(s[0].wordsMet, 0)
        XCTAssertTrue(s[1].isActive && s[1].started)
        XCTAssertEqual(s[1].flag, "🇨🇦")
        XCTAssertFalse(s[2].started)
        XCTAssertEqual(s[2].questsTotal, 15)
    }

    func testTodaySummaryNeverGuilts() {
        var p = PlayerProfile(nickname: "", ageBand: .age10to12, variant: "es-MX")
        let now = Date()
        XCTAssertEqual(TodaySummary.compute(p, now: now).activities, 0)
        XCTAssertFalse(TodaySummary.compute(p, now: now).message.lowercased().contains("streak"))
        p.log.activitiesByDay[ActivityLog.dayKey(now)] = 6
        XCTAssertEqual(TodaySummary.compute(p, now: now).activities, 6)
        for n in [0, 1, 3, 8, 30] {
            let m = TodaySummary(activities: n, minutes: 0).message.lowercased()
            for bad in ["lose", "miss", "streak", "don't forget", "only"] { XCTAssertFalse(m.contains(bad), m) }
        }
    }

    func testDayPhases() {
        XCTAssertEqual(DayPhase.of(hour: 6), .morning)
        XCTAssertEqual(DayPhase.of(hour: 12), .day)
        XCTAssertEqual(DayPhase.of(hour: 18), .evening)
        XCTAssertEqual(DayPhase.of(hour: 23), .night)
        XCTAssertEqual(DayPhase.of(hour: 2), .night)
        XCTAssertEqual(DayPhase.day.tint.alpha, 0)
        XCTAssertLessThanOrEqual(DayPhase.night.tint.alpha, 0.35, "night stays readable")
    }

    func testBadgesArePerLanguage() throws {
        let l = try libs()
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: "en-fr", variant: "fr-FR")
        let prog = Progression(library: l["en-fr"]!)
        for q in l["en-fr"]!.units[0].quests { for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: Date()) } }
        XCTAssertTrue(p.rewards.badges.contains("en-fr:badge-u1"))
        XCTAssertFalse(p.rewards.badges.contains("badge-u1"))
        XCTAssertEqual(Catalog.badge(anyId: "en-fr:badge-u1")?.name, "Bonjour Hero")
        XCTAssertEqual(Catalog.badge(anyId: "badge-u1")?.name, "Hola Hero")
        XCTAssertEqual(Catalog.badge(anyId: "en-ja:badge-mastery-u2")?.detail.hasPrefix("Japanese"), true)
        XCTAssertEqual(Catalog.masteryBadge(forUnitOrder: 3, courseId: "en-ja"), "en-ja:badge-mastery-u3")
        XCTAssertNil(Catalog.badge(anyId: "en-xx:badge-u1"))
    }

    func testKanaDojo() {
        XCTAssertEqual(KanaDojo.hiragana.count, 46)
        let kata = KanaDojo.characters(.katakana)
        XCTAssertEqual(kata.first, "ア")
        XCTAssertEqual(kata.last, "ン")
        for script in KanaScript.allCases {
            for seed in 1...25 as ClosedRange<UInt64> {
                var d = KanaDojo(script: script, seed: seed)
                XCTAssertEqual(d.questions.count, KanaDojo.rounds)
                for q in d.questions {
                    XCTAssertEqual(Set(q.options).count, 4)
                    XCTAssertEqual(q.options[q.answerIndex], q.readKana ? q.romaji : q.kana)
                    XCTAssertFalse(q.romaji.isEmpty)
                    XCTAssertFalse(Kana.containsKana(q.romaji))
                }
                while let q = d.current { d.answer(q.answerIndex) }
                XCTAssertEqual(d.stars, 3)
            }
        }
    }

    func testFlashcardsDueFirstAndRecord() throws {
        let lib = try ContentLibrary.bundled("en-ja")
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: "en-ja", variant: "ja-JP")
        let fresh = FlashcardDeck.build(p, library: lib, now: Date(), seed: 1)
        XCTAssertEqual(fresh.count, FlashcardDeck.size, "new learners still get a deck")
        let t0 = Date(timeIntervalSince1970: 1_900_000_000)
        PracticeRecorder.record(itemId: "neko", outcome: .init(correct: false), track: .comprehension, profile: &p, now: t0)
        let deck = FlashcardDeck.build(p, library: lib, now: t0.addingTimeInterval(3600), seed: 1)
        XCTAssertEqual(deck.first?.itemId, "neko", "due words come first")
        FlashcardDeck.record(deck[0], knewIt: true, profile: &p, now: t0.addingTimeInterval(3600))
        XCTAssertEqual(p.knowledge["neko"]?.comprehension.reviewCount, 2)
        XCTAssertEqual(p.extrasOrEmpty.flashcardsReviewed, 1)
    }

    func testOlderExtrasStillDecode() throws {
        let old = #"{"battleStars":{"duel-mateo":2},"scrambleBestStars":1,"marketBestStars":0,"treasuresFound":["t-sol"]}"#
        let e = try JSONDecoder().decode(ExtrasProgress.self, from: Data(old.utf8))
        XCTAssertEqual(e.battleStars["duel-mateo"], 2)
        XCTAssertNil(e.kanaBestStars)
        let s = #"{"reducedMotion":false,"soundEffects":true,"music":true,"voiceVolume":1,"speechRate":0.42,"subtitles":true,"readAloudInstructions":false,"textScale":1,"colorBlindSymbols":true}"#
        let settings = try JSONDecoder().decode(LearnerSettings.self, from: Data(s.utf8))
        XCTAssertEqual(settings.musicLevel, LearnerSettings.defaultMusicVolume)
        XCTAssertTrue(settings.romanizationOn)
    }

    func testLanguageMusic() {
        XCTAssertEqual(GameMusic.lessons(for: "es"), .reggaeton)
        XCTAssertEqual(GameMusic.lessons(for: "fr"), .paris)
        XCTAssertEqual(GameMusic.lessons(for: "ja"), .tokyo)
        XCTAssertEqual(GameMusic.paris.song.lengthBeats, 24, "8 bars of 3/4")
        XCTAssertEqual(GameMusic.tokyo.song.lengthBeats, 32)
        for m in GameMusic.allCases {
            XCTAssertEqual(Set(m.song.tracks.map(\.lengthBeats)).count, 1, "\(m) tracks loop in sync")
            var v = ChipVoice(m.song)
            var peak: Float = 0
            for _ in 0..<44100 * 2 { peak = max(peak, abs(v.next(sampleRate: 44100))) }
            XCTAssertGreaterThan(peak, 0.03, "\(m)")
            XCTAssertLessThan(peak, 1, "\(m)")
        }
    }
}
