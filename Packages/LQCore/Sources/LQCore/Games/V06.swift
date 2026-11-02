import Foundation

// MARK: - Flashcard multiple choice

/// Four English meanings for a flashcard, one of them right.
public struct FlashcardChoices: Hashable, Sendable {
    public var options: [String]
    public var answerIndex: Int

    /// Distractors come from the same course, preferring the same kind of word
    /// (numbers with numbers, phrases with phrases) so the choice takes real thought.
    public static func make(for card: Flashcard, library: ContentLibrary, seed: UInt64) -> FlashcardChoices {
        var rng = SeededRandom(seed: seed)
        let me = library.item(card.itemId)
        let right = card.back
        let pool = library.allItems.filter { $0.id != card.itemId && $0.english != right }
        let similar = pool.filter { $0.kind == me?.kind && $0.partOfSpeech == me?.partOfSpeech }.shuffled(using: &rng)
        let rest = pool.shuffled(using: &rng)
        var picked: [String] = []
        for c in similar + rest where picked.count < 3 {
            let e = c.english
            if !picked.contains(e) && AnswerChecker.normalize(e) != AnswerChecker.normalize(right) { picked.append(e) }
        }
        var options = picked + [right]
        options.shuffle(using: &rng)
        return FlashcardChoices(options: options, answerIndex: options.firstIndex(of: right) ?? 0)
    }
}

// MARK: - Bonus lesson

/// A short daily lesson in the active language: a few activities from finished
/// quests (due words first) plus a sneak peek at words from the next quest.
/// Its bonus XP can be claimed once per day per language.
public struct BonusLesson: Sendable {
    public static let size = 6
    public static let bonusXP = 25

    public var title: String
    public var activities: [Activity]
    public var dayKey: String

    public static func build(_ p: PlayerProfile, library: ContentLibrary, plan: Plan, now: Date,
                             calendar: Calendar = .current) -> BonusLesson {
        let day = ActivityLog.dayKey(now, calendar: calendar)
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: (day + library.course.id).hashValueStable))
        let due = Set(ReviewPlanner.dueItems(p.knowledge, now: now, limit: 30))
        let finished = library.allQuests.filter { p.progress.completedQuests.contains($0.id) }
        // Speaking activities need a quiet place; the bonus lesson stays tap-and-type.
        let fromQuests = finished.flatMap(\.activities).filter { $0.type != .speak }
        let dueFirst = fromQuests.filter { !Set($0.items).isDisjoint(with: due) }.shuffled(using: &rng)
        let others = fromQuests.filter { Set($0.items).isDisjoint(with: due) }.shuffled(using: &rng)
        var acts = Array((dueFirst + others).prefix(finished.isEmpty ? 0 : 4))

        // Sneak peek: new words from the next quest (or the first unit for new learners).
        let next = Progression(library: library).nextQuest(p.progress, plan: plan)
        let peekIds = (next.map { Array(Set($0.activities.flatMap(\.items))).sorted() } ?? [])
            + (library.units.first?.allItems.map(\.id) ?? [])
        var seen = Set<String>()
        let fresh = peekIds.filter { p.knowledge[$0] == nil && seen.insert($0).inserted }.compactMap { library.item($0) }
        for (i, item) in fresh.shuffled(using: &rng).enumerated() where acts.count < size {
            acts.append(preview(item, library: library, index: i, day: day, rng: &rng))
        }
        // Everything known and no new words left: fill from finished quests.
        if acts.count < size { acts += others.filter { a in !acts.contains(where: { $0.id == a.id }) }.prefix(size - acts.count) }
        let title = finished.isEmpty ? "First words" : (next.map { "Warm-up for “\($0.title)”" } ?? "Review mix")
        return BonusLesson(title: title, activities: acts, dayKey: day)
    }

    static func preview(_ item: LexItem, library: ContentLibrary, index: Int, day: String, rng: inout SeededRandom) -> Activity {
        let wrong = Array(library.allItems.filter { $0.id != item.id && $0.english != item.english && $0.kind == item.kind }
            .map(\.english).uniqued().shuffled(using: &rng).prefix(2))
        var opts = (wrong + [item.english])
        opts.shuffle(using: &rng)
        let letters = ["a", "b", "c", "d"]
        let choices = opts.enumerated().map { ChoiceOption(id: letters[$0.offset], text: VText($0.element)) }
        let ans = letters[opts.firstIndex(of: item.english) ?? 0]
        let listen = index % 2 == 0
        return Activity(id: "bonus-\(day)-\(item.id)", type: listen ? .listenChoose : .readChoose,
                        skill: listen ? .listening : .reading, mode: .interpretive, practice: .guided,
                        prompt: "Sneak peek! \(listen ? "Listen" : "Read"). What does it mean?",
                        target: item.target, targetEnglish: item.english, choices: choices, answer: ans,
                        items: [item.id], hint: item.picture.map { "Picture clue: \($0)" } ?? "Take a guess. New words are allowed to be tricky!",
                        explanation: "\(item.target.base) = \(item.english). You'll meet it in a quest soon.")
    }

    public static func claimed(_ p: PlayerProfile, day: String) -> Bool { p.extrasOrEmpty.bonusDays?.contains(day) ?? false }

    /// Adds the bonus XP once per day; returns the XP given (0 if already claimed).
    @discardableResult
    public static func claim(_ p: inout PlayerProfile, day: String) -> Int {
        guard !claimed(p, day: day) else { return 0 }
        p.updateExtras { e in
            var days = e.bonusDays ?? []
            days.append(day)
            e.bonusDays = Array(days.suffix(60))
        }
        p.rewards.xp += bonusXP
        return bonusXP
    }
}

// MARK: - Write Out

public struct WriteOutWord: Hashable, Identifiable, Sendable {
    public var id: String { itemId }
    public var itemId: String
    public var text: String
    public var romanized: String?
    public var english: String
}

public enum WriteOut {
    /// Cursive guides exist for Latin-alphabet languages.
    public static func supportsCursive(_ course: Course) -> Bool { course.script == .latin }

    /// Words to write: ones you've met first, then the first unit. Short enough to fit a line.
    public static func words(_ p: PlayerProfile, library: ContentLibrary, limit: Int = 40) -> [WriteOutWord] {
        let v = p.courseId == library.course.id ? p.variant : library.course.defaultVariant
        let met = library.allItems.filter { p.knowledge[$0.id] != nil }
        let first = library.units.first?.allItems ?? []
        var seen = Set<String>()
        return (met + first).compactMap { item -> WriteOutWord? in
            let t = item.target.text(for: v).replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.count <= 16, seen.insert(item.id).inserted else { return nil }
            return WriteOutWord(itemId: item.id, text: t, romanized: library.course.romanize(t), english: item.english)
        }.prefix(limit).map { $0 }
    }

    /// True when any recognized line reads as the word (accents, case, spaces and one slip forgiven).
    public static func matches(recognized: [String], word: String) -> Bool {
        let key = squash(word)
        guard !key.isEmpty else { return false }
        return recognized.contains { r in
            let k = squash(r)
            return k == key || (key.count >= 4 && AnswerChecker.editDistance(k, key) <= 1)
        }
    }

    static func squash(_ s: String) -> String { AnswerChecker.fold(s).replacingOccurrences(of: " ", with: "") }

    /// Records a written word (once) for the Write Out progress count.
    public static func record(_ itemId: String, profile p: inout PlayerProfile) {
        p.updateExtras { e in
            var w = e.wordsWritten ?? []
            if !w.contains(itemId) { w.append(itemId) }
            e.wordsWritten = w
        }
    }
}

// MARK: - Helpers

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var s = Set<Element>(); return filter { s.insert($0).inserted } }
}

extension String {
    /// A hash that is the same on every launch (Swift's hashValue is randomized per process).
    var hashValueStable: UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
}
