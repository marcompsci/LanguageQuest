import Foundation

/// The last quest the learner practiced, in any language.
public struct RecentLesson: Codable, Hashable, Sendable {
    public var courseId: String
    public var questId: String
    public var at: Date
    public init(courseId: String, questId: String, at: Date) {
        self.courseId = courseId; self.questId = questId; self.at = at
    }
}

/// The menu's "Recent lesson" card: the last quest plus one quick flashcard from
/// words practiced in earlier lessons of that language.
public struct RecentLessonCard: Sendable {
    public var courseId: String
    public var questId: String
    public var questTitle: String
    public var language: String
    public var flag: String
    public var card: Flashcard?

    /// nil until the learner has practiced something.
    public static func compute(_ p: PlayerProfile, libraries: [String: ContentLibrary], now: Date, seed: UInt64) -> RecentLessonCard? {
        guard let recent = p.recentLesson, let lib = libraries[recent.courseId],
              let (_, quest) = lib.quest(recent.questId) else { return nil }
        let active = p.courseId == recent.courseId
        let snap = p.otherCourses?[recent.courseId]
        let knowledge = active ? p.knowledge : snap?.knowledge ?? [:]
        let variant = active ? p.variant : snap?.variant ?? lib.course.defaultVariant
        return RecentLessonCard(courseId: recent.courseId, questId: quest.id, questTitle: quest.title,
                                language: lib.course.displayLanguage,
                                flag: lib.course.variant(variant)?.flagEmoji ?? "🌐",
                                card: pick(knowledge: knowledge, quest: quest, library: lib, now: now, seed: seed))
    }

    /// Prefers a due word from any earlier lesson, then a word from this quest.
    static func pick(knowledge: [String: ItemKnowledge], quest: Quest, library: ContentLibrary, now: Date, seed: UInt64) -> Flashcard? {
        var rng = SeededRandom(seed: seed)
        let due = ReviewPlanner.dueItems(knowledge, now: now, limit: 20).filter { library.item($0) != nil }
        let questItems = Array(Set(quest.activities.flatMap(\.items))).sorted().filter { library.item($0) != nil }
        let met = knowledge.keys.sorted().filter { library.item($0) != nil }
        let id = due.first ?? questItems.filter { knowledge[$0] != nil }.randomElement(using: &rng)
            ?? met.randomElement(using: &rng) ?? questItems.randomElement(using: &rng)
        guard let id, let item = library.item(id) else { return nil }
        return Flashcard(itemId: id, front: item.target, back: item.english, picture: item.picture)
    }

    /// Records the quick card in the right language, even if another language is active.
    public static func record(_ card: Flashcard, courseId: String, knewIt: Bool, profile p: inout PlayerProfile,
                              libraries: [String: ContentLibrary], now: Date) {
        if p.courseId == courseId {
            FlashcardDeck.record(card, knewIt: knewIt, profile: &p, now: now)
            return
        }
        guard let lib = libraries[courseId], let back = libraries[p.courseId] else { return }
        let returnTo = p.courseId
        p.switchCourse(to: courseId, defaultVariant: lib.course.defaultVariant)
        FlashcardDeck.record(card, knewIt: knewIt, profile: &p, now: now)
        p.switchCourse(to: returnTo, defaultVariant: back.course.defaultVariant)
    }
}
