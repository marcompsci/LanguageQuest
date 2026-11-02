import XCTest
@testable import LQCore

final class ChiptuneTests: XCTestCase {
    func testNoteNamesAndFrequencies() {
        XCTAssertEqual(ChipSynth.midi("A4"), 69)
        XCTAssertEqual(ChipSynth.midi("C4"), 60)
        XCTAssertEqual(ChipSynth.midi("F#3"), 54)
        XCTAssertEqual(ChipSynth.midi("Bb4"), 70)
        XCTAssertNil(ChipSynth.midi("H2"))
        XCTAssertEqual(ChipSynth.frequency(midi: 69), 440, accuracy: 0.001)
        XCTAssertEqual(ChipSynth.frequency(midi: 81), 880, accuracy: 0.001)
    }

    func testParsingAndLengths() {
        let n = ChipSong.parse("C5:1 -:0.5 E5:0.5")
        XCTAssertEqual(n, [ChipNote(72, 1), ChipNote(nil, 0.5), ChipNote(76, 0.5)])
        XCTAssertEqual(MusicTrack.village.song.lengthBeats, 16)
        XCTAssertEqual(MusicTrack.battle.song.lengthBeats, 8)
        for t in MusicTrack.allCases {
            let lens = Set(t.song.tracks.map(\.lengthBeats))
            XCTAssertEqual(lens.count, 1, "\(t) tracks stay in sync when looping")
        }
    }

    func testEffectsPlayThenEndAndMusicLoops() {
        let mixer = ChipMixer()
        var buf = [Float](repeating: 0, count: 4410)
        mixer.play(.correct)
        buf.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: 4410, sampleRate: 44100) }
        XCTAssertGreaterThan(buf.map(abs).max() ?? 0, 0.05, "effect is audible")
        XCTAssertTrue(buf.allSatisfy { $0 >= -1 && $0 <= 1 })
        for _ in 0..<40 { buf.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: 4410, sampleRate: 44100) } }
        XCTAssertEqual(mixer.activeEffects, 0, "finished effects are removed")
        mixer.setMusic(.village)
        var long = [Float](repeating: 0, count: 44100)
        for _ in 0..<12 { long.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: 44100, sampleRate: 44100) } }
        XCTAssertGreaterThan(long.map(abs).max() ?? 0, 0.01, "music still playing after more than one loop (8.6 s)")
        mixer.setMusic(nil)
        long.withUnsafeMutableBufferPointer { mixer.render(into: $0.baseAddress!, count: 44100, sampleRate: 44100) }
        XCTAssertEqual(long.map(abs).max() ?? 1, 0)
    }

    func testEveryEffectHasSoundAndEnds() {
        for e in SoundEffect.allCases {
            var v = ChipVoice(e.song)
            var peak: Float = 0
            var n = 0
            while !v.finished && n < 44100 * 5 { peak = max(peak, abs(v.next(sampleRate: 44100))); n += 1 }
            XCTAssertTrue(v.finished, "\(e) ends")
            XCTAssertGreaterThan(peak, 0.01, "\(e) is audible")
            XCTAssertLessThan(e.song.lengthSeconds, 3, "\(e) is short")
        }
    }
}

final class WordBattleTests: XCTestCase {
    var lib: ContentLibrary!
    override func setUpWithError() throws { lib = try ContentLibrary.bundledSpanish() }
    func profile() -> PlayerProfile { PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX") }

    func testQuestionsAreWellFormed() {
        for o in BattleRoster.opponents {
            for seed in 1...30 as ClosedRange<UInt64> {
                let b = WordBattle(opponent: o, library: lib, profile: profile(), seed: seed)
                XCTAssertEqual(b.questions.count, WordBattle.rounds)
                for q in b.questions {
                    XCTAssertEqual(q.options.count, 4, o.id)
                    XCTAssertEqual(Set(q.options.map { $0.text(for: "es-MX") }).count, 4, "no duplicate options")
                    let item = lib.item(q.itemId)!
                    let right = q.options[q.answerIndex]
                    XCTAssertEqual(right, q.spanishPrompt ? VText(item.english) : item.target)
                    if let u = o.unitOrder { XCTAssertTrue(lib.units.first { $0.order == u }!.allItems.contains(item)) }
                }
            }
        }
    }

    func testAllCorrectWinsWithThreeStarsAndMistakesOnlyCostSpark() {
        let o = BattleRoster.opponents[0]
        var win = WordBattle(opponent: o, library: lib, profile: profile(), seed: 7)
        while let q = win.current { win.answer(q.answerIndex, library: lib, variant: "es-MX") }
        XCTAssertTrue(win.playerWon)
        XCTAssertEqual(win.stars, 3)
        XCTAssertEqual(win.playerSpark, 20 + 25 + 30 * 4)

        var lose = WordBattle(opponent: o, library: lib, profile: profile(), seed: 7)
        var tips = 0
        while let q = lose.current {
            let t = lose.answer((q.answerIndex + 1) % 4, library: lib, variant: "es-MX")!
            XCTAssertFalse(t.correct)
            XCTAssertEqual(t.playerGain, 0)
            if !t.coachTip.isEmpty { tips += 1 }
        }
        XCTAssertFalse(lose.playerWon)
        XCTAssertEqual(lose.stars, 0)
        XCTAssertEqual(tips, WordBattle.rounds, "every mistake gets a coaching tip")
        XCTAssertEqual(lose.playerSpark, 0, "no negative score")
    }

    func testFourInARowIsEnoughToWin() {
        var b = WordBattle(opponent: BattleRoster.opponents[1], library: lib, profile: profile(), seed: 3)
        var i = 0
        while let q = b.current { b.answer(i < 4 ? q.answerIndex : (q.answerIndex + 1) % 4, library: lib, variant: "es-MX"); i += 1 }
        XCTAssertTrue(b.playerWon)
    }

    func testOpponentsUnlockWithUnits() {
        let prog = Progression(library: lib)
        var p = CourseProgress()
        XCTAssertFalse(BattleRoster.opponents.contains { BattleRoster.isUnlocked($0, progress: p, progression: prog) })
        for q in lib.units[0].quests { p.completedQuests.insert(q.id) }
        XCTAssertTrue(BattleRoster.isUnlocked(BattleRoster.opponents[0], progress: p, progression: prog))
        XCTAssertFalse(BattleRoster.isUnlocked(BattleRoster.opponents[3], progress: p, progression: prog))
        for u in lib.units { for q in u.quests { p.completedQuests.insert(q.id) } }
        XCTAssertTrue(BattleRoster.opponents.allSatisfy { BattleRoster.isUnlocked($0, progress: p, progression: prog) })
        for o in BattleRoster.opponents { XCTAssertNotNil(StarterVillage.npc(o.npc), o.npc) }
    }

    func testPracticeRecorderFeedsLearnerModel() {
        var p = profile()
        PracticeRecorder.record(itemId: "hola", outcome: .init(correct: true), track: .comprehension, profile: &p, now: Date())
        XCTAssertEqual(p.knowledge["hola"]?.comprehension.reviewCount, 1)
    }
}

final class SideGameTests: XCTestCase {
    var lib: ContentLibrary!
    override func setUpWithError() throws { lib = try ContentLibrary.bundledSpanish() }

    func testScramblePuzzlesAreSolvableAndScrambled() {
        for v in lib.course.variants.map(\.id) {
            for seed in 1...20 as ClosedRange<UInt64> {
                var p = PlayerProfile(nickname: "", ageBand: .age10to12, variant: v)
                p.knowledge["gato"] = ItemKnowledge(now: Date())
                let s = WordScramble(library: lib, profile: p, seed: seed)
                XCTAssertEqual(s.puzzles.count, WordScramble.rounds)
                XCTAssertEqual(Set(s.puzzles.map(\.answer)).count, s.puzzles.count)
                for pz in s.puzzles {
                    XCTAssertEqual(String(pz.letters.sorted()), String(Array(pz.answer.lowercased()).sorted()))
                    XCTAssertNotEqual(String(pz.letters), pz.answer.lowercased())
                    XCTAssertFalse(pz.answer.contains(" "))
                }
                XCTAssertTrue(s.puzzles.contains { $0.itemId == "gato" }, "met words come first")
            }
        }
    }

    func testScrambleScoring() {
        let p = PlayerProfile(nickname: "", ageBand: .age10to12, variant: "es-MX")
        var s = WordScramble(library: lib, profile: p, seed: 9)
        XCTAssertFalse(s.submit("zzz"))
        XCTAssertTrue(s.submit(s.current!.answer))   // second try
        while let pz = s.current { XCTAssertTrue(s.submit(AnswerChecker.fold(pz.answer))) } // accents optional
        XCTAssertEqual(s.firstTryCorrect, WordScramble.rounds - 1)
        XCTAssertEqual(s.stars, 2)
    }

    func testMarketOrdersArePayableAndChecked() {
        for seed in 1...50 as ClosedRange<UInt64> {
            var m = MarketRush(library: lib, seed: seed)
            XCTAssertEqual(m.orders.count, MarketRush.rounds)
            while let o = m.current {
                XCTAssertEqual(o.wanted.count, MarketRush.itemsPerOrder)
                XCTAssertTrue(o.wanted.allSatisfy(o.stall.contains))
                XCTAssertEqual(Set(o.stall.map(\.itemId)).count, o.stall.count)
                XCTAssertTrue(o.stall.allSatisfy { lib.item($0.itemId) != nil && (1...6).contains($0.price) })
                XCTAssertTrue(m.checkBasket(o.wanted.map(\.itemId).reversed()))
                XCTAssertFalse(m.checkBasket(Array(o.wanted.map(\.itemId).prefix(2))))
                XCTAssertTrue(m.checkPayment(MarketRush.fewestCoins(for: o.total)))
                XCTAssertFalse(m.checkPayment([o.total + 1]))
                m.completeRound()
            }
            XCTAssertEqual(m.stars, 3)
        }
    }

    func testTreasuresAreReachableUniqueAndOffNPCs() {
        let map = StarterVillage.map()
        let reach = map.reachable(from: StarterVillage.spawn, blocked: StarterVillage.npcPositions)
        XCTAssertEqual(StarterVillage.treasures.count, 10)
        XCTAssertEqual(Set(StarterVillage.treasures.map(\.position)).count, 10)
        XCTAssertEqual(Set(StarterVillage.treasures.map(\.id)).count, 10)
        for t in StarterVillage.treasures {
            XCTAssertFalse(StarterVillage.npcPositions.contains(t.position), t.id)
            XCTAssertTrue(reach.contains(t.position) || Direction.allCases.contains { reach.contains(t.position.moved($0)) }, t.id)
            XCTAssertFalse(t.fact.isEmpty)
        }
    }

    func testCompassHeadings() {
        let o = GridPoint(10, 10)
        XCTAssertEqual(QuestCompass.heading(from: o, to: GridPoint(10, 3)), .north)
        XCTAssertEqual(QuestCompass.heading(from: o, to: GridPoint(10, 17)), .south)
        XCTAssertEqual(QuestCompass.heading(from: o, to: GridPoint(17, 10)), .east)
        XCTAssertEqual(QuestCompass.heading(from: o, to: GridPoint(3, 10)), .west)
        XCTAssertEqual(QuestCompass.heading(from: o, to: GridPoint(15, 5)), .northEast)
        XCTAssertEqual(QuestCompass.heading(from: o, to: GridPoint(5, 15)), .southWest)
        XCTAssertEqual(QuestCompass.heading(from: o, to: GridPoint(11, 10)), .here)
        let map = StarterVillage.map()
        let pepe = StarterVillage.npc("don-pepe")!.position
        XCTAssertGreaterThanOrEqual(QuestCompass.steps(from: StarterVillage.spawn, to: pepe, map: map, blocked: StarterVillage.npcPositions),
                                    StarterVillage.spawn.manhattan(to: pepe) - 1)
    }

    func testPhrasebookSearchAndRegions() {
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, variant: "es-MX")
        XCTAssertTrue(Phrasebook.entries(p, library: lib).isEmpty, "only met words by default")
        XCTAssertEqual(Phrasebook.entries(p, library: lib, includeUnmet: true).count, lib.allItems.count)
        p.knowledge["platano"] = ItemKnowledge(now: Date())
        p.knowledge["cuanto-cuesta"] = ItemKnowledge(now: Date())
        let banana = Phrasebook.entries(p, library: lib, query: "guineo")
        XCTAssertEqual(banana.map(\.item.id), ["platano"], "search matches other regions' forms")
        XCTAssertTrue(banana[0].otherRegions.contains(RegionalForm(variantName: "Argentina", form: "la banana")))
        XCTAssertFalse(banana[0].otherRegions.contains { $0.form == "el plátano" }, "own form not repeated")
        XCTAssertEqual(Phrasebook.entries(p, library: lib, query: "cuanto").map(\.item.id), ["cuanto-cuesta"], "accent-insensitive")
        XCTAssertEqual(Phrasebook.entries(p, library: lib, query: "banana").count, 1, "English search")
    }

    func testExtrasAreOptionalForOldSaves() throws {
        var p = PlayerProfile(nickname: "", ageBand: .age10to12, variant: "es-MX")
        XCTAssertNil(p.extras)
        p.updateExtras { $0.treasuresFound.insert("t-sol"); $0.battleStars["duel-mateo"] = 2 }
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(PlayerProfile.self, from: data)
        XCTAssertEqual(back.extrasOrEmpty.treasuresFound, ["t-sol"])
        // A profile encoded without the key still decodes.
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "extras")
        let old = try JSONDecoder().decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.extras)
    }
}

final class ParentPINTests: XCTestCase {
    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256.hex(Array("".utf8)), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testValidation() {
        XCTAssertEqual(ParentPIN.validateNew("12a4", confirm: "12a4"), .notDigits)
        XCTAssertEqual(ParentPIN.validateNew("123", confirm: "123"), .wrongLength)
        XCTAssertEqual(ParentPIN.validateNew("1111", confirm: "1111"), .tooSimple)
        XCTAssertEqual(ParentPIN.validateNew("1234", confirm: "1234"), .tooSimple)
        XCTAssertEqual(ParentPIN.validateNew("9876", confirm: "9876"), .tooSimple)
        XCTAssertEqual(ParentPIN.validateNew("2580", confirm: "2581"), .mismatch)
        XCTAssertNil(ParentPIN.validateNew("2580", confirm: "2580"))
    }

    func testVerifyAndLockout() {
        let r = ParentPIN.makeRecord(pin: "2580", salt: "abc123")
        XCTAssertFalse(r.hash.contains("2580"))
        XCTAssertTrue(ParentPIN.verify("2580", against: r))
        XCTAssertFalse(ParentPIN.verify("2581", against: r))
        XCTAssertNotEqual(ParentPIN.makeRecord(pin: "2580", salt: "other").hash, r.hash, "salted")
        var t = GateAttemptTracker()
        let now = Date(timeIntervalSince1970: 5000)
        for _ in 0..<3 { XCTAssertFalse(t.submitPIN("0000", record: r, now: now)) }
        XCTAssertFalse(t.submitPIN("2580", record: r, now: now), "locked")
        XCTAssertTrue(t.submitPIN("2580", record: r, now: now.addingTimeInterval(61)))
    }
}
