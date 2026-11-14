import Foundation

// v0.9: fifteen improvements. Everything stays on the device.

extension MetaEvent {
    static let listenPerfect = "listenPerfect"      // 8+ right in Listen & Type
    static let rightOrWrongPerfect = "rowPerfect"   // 10/10 in Right or Wrong
    static let replayedChat = "replayedChat"
}

// MARK: - 1. Listen & Type: hear a word, type it

public struct ListenTypeGame: Sendable {
    public static let rounds = 10
    public static let goodScore = 8
    public let items: [LexItem]
    public private(set) var index = 0
    public private(set) var correct = 0
    public private(set) var missed: [LexItem] = []

    public init(profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let v = profile.variant(for: library)
        var seen = Set<String>()
        // Short words and phrases only: typing a whole sentence from audio is no fun.
        let pool = MiniGamePool.items(profile, library: library, maxLength: 16)
            .filter { seen.insert(AnswerChecker.normalize($0.target.text(for: v))).inserted }
        items = Array(pool.prefix(40).shuffled(using: &rng).prefix(Self.rounds))
    }

    public var current: LexItem? { index < items.count ? items[index] : nil }
    public var isFinished: Bool { index >= items.count }
    public var stars: Int { GameHelpers.stars(correct: correct, of: items.count) }

    /// Checks what was typed (accents and small typos are forgiven; any listed spelling counts).
    @discardableResult
    public mutating func submit(_ typed: String, variant: String, context: CheckContext) -> AnswerVerdict {
        guard let item = current else { return .incorrect(expected: "") }
        let verdict = AnswerChecker.check(typed, accepted: [item.target], variant: variant, context: context)
        if verdict.isCorrect { correct += 1 } else { missed.append(item) }
        index += 1
        return verdict
    }

    public static func finish(_ g: ListenTypeGame, profile p: inout PlayerProfile) {
        p.updateExtras { $0.listenBest = max($0.listenBest ?? 0, g.correct) }
        if g.correct >= goodScore { p.updateMeta { $0.counters[MetaEvent.listenPerfect, default: 0] += 1 } }
    }
}

// MARK: - 2. Right or Wrong: is this the right meaning?

public struct RightOrWrongRound: Hashable, Sendable {
    public var itemId: String
    public var word: VText
    public var shownMeaning: String
    public var isRight: Bool
    public var realMeaning: String
}

public struct RightOrWrongGame: Sendable {
    public static let rounds = 10
    public let rounds: [RightOrWrongRound]
    public private(set) var index = 0
    public private(set) var correct = 0

    public init(profile: PlayerProfile, library: ContentLibrary, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let pool = MiniGamePool.items(profile, library: library)
        var seen = Set<String>()
        let picks = pool.filter { seen.insert(AnswerChecker.normalize($0.english)).inserted }.prefix(40).shuffled(using: &rng).prefix(Self.rounds)
        let meanings = Array(Set(library.allItems.map(\.english)))
        var out: [RightOrWrongRound] = []
        for (n, item) in picks.enumerated() {
            // About half are right; the order of right and wrong is mixed by the seed.
            let showRight = (n + Int(seed % 2)) % 2 == 0
            var shown = item.english
            if !showRight {
                let others = meanings.filter { AnswerChecker.normalize($0) != AnswerChecker.normalize(item.english) }
                shown = others.randomElement(using: &rng) ?? item.english
            }
            out.append(RightOrWrongRound(itemId: item.id, word: item.target, shownMeaning: shown,
                                         isRight: AnswerChecker.normalize(shown) == AnswerChecker.normalize(item.english), realMeaning: item.english))
        }
        rounds = out.shuffled(using: &rng)
    }

    public var current: RightOrWrongRound? { index < rounds.count ? rounds[index] : nil }
    public var isFinished: Bool { index >= rounds.count }
    public var stars: Int { GameHelpers.stars(correct: correct, of: rounds.count) }

    @discardableResult
    public mutating func answer(saysRight: Bool) -> Bool {
        guard let r = current else { return false }
        let ok = saysRight == r.isRight
        if ok { correct += 1 }
        index += 1
        return ok
    }

    public static func finish(_ g: RightOrWrongGame, profile p: inout PlayerProfile) {
        p.updateExtras { $0.rightOrWrongBest = max($0.rightOrWrongBest ?? 0, g.correct) }
        if g.correct == g.rounds.count && !g.rounds.isEmpty { p.updateMeta { $0.counters[MetaEvent.rightOrWrongPerfect, default: 0] += 1 } }
    }
}

// MARK: - 3. Slow replay

public enum SlowSpeech {
    /// The slow rate (the slowest the speech slider allows).
    public static let rate = 0.3
    public static func settings(_ s: LearnerSettings) -> LearnerSettings { var c = s; c.speechRate = rate; return c }
}

// MARK: - 4. Unit progress map

public struct UnitProgress: Hashable, Identifiable, Sendable {
    public var id: String
    public var order: Int
    public var title: String
    public var questsDone: Int
    public var questsTotal: Int
    public var wordsTotal: Int
    public var wordsMet: Int
    /// Words at "understood" or better.
    public var wordsStrong: Int
    public var quizBest: Int?
    public var unlocked: Bool
    public var fractionDone: Double { questsTotal == 0 ? 0 : Double(questsDone) / Double(questsTotal) }
    public var fractionStrong: Double { wordsTotal == 0 ? 0 : Double(wordsStrong) / Double(wordsTotal) }
}

public enum UnitMap {
    public static func units(_ p: PlayerProfile, library: ContentLibrary, progression: Progression, plan: Plan) -> [UnitProgress] {
        library.units.sorted { $0.order < $1.order }.map { u in
            let ids = Set(u.allItems.map(\.id))
            let ks = ids.compactMap { p.knowledge[$0] }
            return UnitProgress(id: u.id, order: u.order, title: u.title,
                                questsDone: u.quests.filter { p.progress.completedQuests.contains($0.id) }.count,
                                questsTotal: u.quests.count, wordsTotal: ids.count, wordsMet: ks.count,
                                wordsStrong: ks.filter { $0.level >= .understood }.count,
                                quizBest: p.extrasOrEmpty.quizBest?[u.id],
                                unlocked: progression.isUnitUnlocked(u, p.progress, plan: plan))
        }
    }
}

// MARK: - 5. Review forecast

public struct ReviewForecast: Hashable, Sendable {
    public var dueNow: Int
    public var tomorrow: Int
    public var nextSevenDays: Int

    /// How many words come up for review: now, by the end of tomorrow, and within a week.
    public static func make(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> ReviewForecast {
        let startToday = calendar.startOfDay(for: now)
        let endTomorrow = calendar.date(byAdding: .day, value: 2, to: startToday) ?? now
        let week = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let dues = p.knowledge.values.map(\.nextDue)
        return ReviewForecast(dueNow: dues.filter { $0 <= now }.count,
                              tomorrow: dues.filter { $0 > now && $0 < endTomorrow }.count,
                              nextSevenDays: dues.filter { $0 > now && $0 <= week }.count)
    }
}

// MARK: - 6. Quiz review: what was missed

public struct MissedAnswer: Hashable, Sendable, Identifiable {
    public var id: String { itemId + prompt }
    public var itemId: String
    public var prompt: String
    public var picked: String
    public var right: String
}

extension QuizQuestion {
    public func missed(picked i: Int) -> MissedAnswer? {
        guard i != answerIndex, options.indices.contains(i), options.indices.contains(answerIndex) else { return nil }
        return MissedAnswer(itemId: itemId, prompt: prompt, picked: options[i], right: options[answerIndex])
    }
}

// MARK: - 7. Sentence Builder hint

extension SentenceBuilder {
    /// The next tile index (into `tiles`) that continues a correct start, or nil if the start is already wrong.
    /// Using a hint means the sentence no longer counts as right first time.
    public static func hint(for puzzle: SentencePuzzle, placed: [Int]) -> Int? {
        let soFar = placed.map { puzzle.tiles[$0] }
        guard soFar.count < puzzle.answer.count, Array(puzzle.answer.prefix(soFar.count)) == soFar else { return nil }
        let want = puzzle.answer[soFar.count]
        return puzzle.tiles.indices.first { !placed.contains($0) && puzzle.tiles[$0] == want }
    }

}

// MARK: - 8. Conversation replay

public struct ReplayLine: Hashable, Sendable, Identifiable {
    public var id: String
    public var speaker: String
    public var text: VText
    public var english: String
    public var isYou: Bool
}

public enum ConversationReplay {
    /// The conversation of a finished quest, in order: what the villager said, then the right reply.
    public static func lines(_ quest: Quest, npcName: String) -> [ReplayLine] {
        var out: [ReplayLine] = []
        var seen = Set<String>()
        var nodeId: String? = quest.dialogue.start
        while let id = nodeId, seen.insert(id).inserted, let n = quest.dialogue.node(id) {
            out.append(ReplayLine(id: n.id, speaker: npcName, text: n.line, english: n.gloss, isYou: false))
            let reply = (n.choices ?? []).first { $0.correct != false }
            if let r = reply { out.append(ReplayLine(id: n.id + "-you", speaker: "You", text: r.text, english: r.gloss, isYou: true)) }
            nodeId = reply?.next ?? n.next
        }
        // Lines not reached by the walk (branches) are added at the end so nothing is lost.
        for n in quest.dialogue.nodes where !seen.contains(n.id) {
            out.append(ReplayLine(id: n.id, speaker: npcName, text: n.line, english: n.gloss, isYou: false))
        }
        return out
    }

    public static func available(_ quest: Quest, progress: CourseProgress) -> Bool { progress.completedQuests.contains(quest.id) }

    /// Counts a replay (for the Encore achievement).
    public static func recordReplay(profile p: inout PlayerProfile) { p.updateMeta { $0.counters[MetaEvent.replayedChat, default: 0] += 1 } }
}

// MARK: - 9. Personal word notes (private, on this device)

public enum WordNotes {
    public static let maxLength = 200

    public static func note(_ id: String, in p: PlayerProfile) -> String? { p.extrasOrEmpty.wordNotes?[id] }

    /// Saves a note (trimmed, at most 200 characters); an empty note removes it.
    public static func set(_ text: String, for id: String, profile p: inout PlayerProfile) {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        p.updateExtras { e in
            var notes = e.wordNotes ?? [:]
            notes[id] = clean.isEmpty ? nil : clean
            e.wordNotes = notes
        }
    }

    static func total(_ p: PlayerProfile) -> Int { p.allCourseStates.reduce(0) { $0 + ($1.extras?.wordNotes?.count ?? 0) } }
}

extension WordLibrary {
    /// Notes are searchable too.
    public static func matchesNote(_ e: WordEntry, query: String, profile: PlayerProfile) -> Bool {
        let q = AnswerChecker.normalize(query)
        guard !q.isEmpty, let n = WordNotes.note(e.id, in: profile) else { return false }
        return AnswerChecker.normalize(n).contains(q)
    }
}

// MARK: - 10. Pinned languages

public enum PinnedLanguages {
    public static let max = 3

    public static func pinned(_ p: PlayerProfile) -> [String] { p.metaOrEmpty.pinnedCourses ?? [] }

    /// Pins or unpins a language (at most 3; pinning a 4th replaces the oldest). Returns whether it is now pinned.
    @discardableResult
    public static func toggle(_ courseId: String, profile p: inout PlayerProfile) -> Bool {
        var list = pinned(p)
        var nowPinned = false
        if let i = list.firstIndex(of: courseId) { list.remove(at: i) } else {
            list.append(courseId); nowPinned = true
            if list.count > max { list.removeFirst(list.count - max) }
        }
        p.updateMeta { $0.pinnedCourses = list }
        return nowPinned
    }
}

// MARK: - 11. High-contrast theme

extension ThemePalette {
    /// Black and white with a bright accent: every text pair is well above WCAG AAA (7:1).
    public static let highContrast = ThemePalette(background: RGB(0x000000), surface: RGB(0x111111), text: RGB(0xFFFFFF),
                                                  secondaryText: RGB(0xE6E6E6), accent: RGB(0xFFD60A), onAccent: RGB(0x000000),
                                                  success: RGB(0x7CFF9B), retry: RGB(0xFFB86B),
                                                  dialogueBox: RGB(0x000000), dialogueText: RGB(0xFFFFFF))
}

extension LearnerSettings {
    public var highContrastOn: Bool { highContrast ?? false }
    public var leftHandedOn: Bool { leftHanded ?? false }
}

// MARK: - 13. 30-day activity calendar

public struct ActivityDay: Hashable, Identifiable, Sendable {
    public var id: String { day }
    public var day: String
    public var date: Date
    public var activities: Int
    public var minutes: Double
    /// 0 = none, 1 = a little, 2 = some, 3 = lots (for shading).
    public var intensity: Int {
        let score = Double(activities) + minutes / 5
        return score == 0 ? 0 : score < 3 ? 1 : score < 8 ? 2 : 3
    }
}

extension PlayerStats {
    /// The last 30 days, oldest first.
    public static func lastMonth(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> [ActivityDay] {
        (0..<30).reversed().map { back in
            let d = calendar.date(byAdding: .day, value: -back, to: now) ?? now
            let k = ActivityLog.dayKey(d, calendar: calendar)
            return ActivityDay(day: k, date: d, activities: p.log.activitiesByDay[k] ?? 0, minutes: p.log.minutesByDay[k] ?? 0)
        }
    }

    public static func activeDays(_ days: [ActivityDay]) -> Int { days.filter { $0.intensity > 0 }.count }
}

// MARK: - 14. Achievement progress

public struct AchievementProgress: Hashable, Sendable {
    public var current: Int
    public var target: Int
    public var fraction: Double { target == 0 ? 0 : min(1, Double(current) / Double(target)) }
}

extension Achievement {
    /// How close the explorer is, for achievements that count something (nil for yes/no ones).
    public func progress(_ p: PlayerProfile, libraries: [String: ContentLibrary]) -> AchievementProgress? {
        let c = p.metaOrEmpty.counters
        let states = p.allCourseStates
        func prog(_ n: Int, _ t: Int) -> AchievementProgress { AchievementProgress(current: min(n, t), target: t) }
        switch id {
        case "a-three-langs": return prog(p.startedCourses.count, 3)
        case "a-50-words": return prog(states.reduce(0) { $0 + $1.knowledge.count }, 50)
        case "a-scribe": return prog(c[MetaEvent.wordWritten.rawValue] ?? 0, 10)
        case "a-treasure": return prog(states.map { $0.extras?.treasuresFound.count ?? 0 }.max() ?? 0, StarterVillage.treasures.count)
        case "a-level5": return prog(ExplorerLevel.level(forXP: p.rewards.xp), 5)
        case "a-flash100": return prog(c[MetaEvent.flashcardRight.rawValue] ?? 0, 100)
        case "a-starred": return prog(StarredWords.totalStarred(p), 5)
        case "a-notes": return prog(WordNotes.total(p), 3)
        case "a-replay": return prog(c[MetaEvent.replayedChat] ?? 0, 3)
        default: return nil
        }
    }

    static let v09: [Achievement] = [
        Achievement(id: "a-listener", title: "Good Listener", detail: "Get 8 or more right in Listen & Type.", icon: "ear.fill"),
        Achievement(id: "a-sharp", title: "Sharp Eye", detail: "Get 10 of 10 in Right or Wrong.", icon: "eye.fill"),
        Achievement(id: "a-notes", title: "Note Taker", detail: "Write notes on 3 words.", icon: "note.text"),
        Achievement(id: "a-replay", title: "Encore", detail: "Replay 3 conversations.", icon: "text.bubble.fill"),
    ]

    func isMetV09(_ p: PlayerProfile) -> Bool? {
        let c = p.metaOrEmpty.counters
        switch id {
        case "a-listener": return (c[MetaEvent.listenPerfect] ?? 0) >= 1
        case "a-sharp": return (c[MetaEvent.rightOrWrongPerfect] ?? 0) >= 1
        case "a-notes": return WordNotes.total(p) >= 3
        case "a-replay": return (c[MetaEvent.replayedChat] ?? 0) >= 3
        default: return nil
        }
    }
}
