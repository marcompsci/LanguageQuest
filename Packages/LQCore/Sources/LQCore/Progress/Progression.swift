import Foundation

public enum QuestStatus: String, Sendable { case locked, available, inProgress, complete }

/// What finishing an activity produced, for the reward toast.
public struct ActivityCompletion: Equatable, Sendable {
    public var xpGained: Int
    public var questCompleted: String?
    public var cosmeticUnlocked: String?
    public var badgeEarned: String?
    public var firstTime: Bool
}

/// Unlocks, quest state, XP and rewards. XP is a play measure only: it never
/// feeds mastery (see ItemKnowledge) or the parent dashboard's skill view.
public struct Progression: Sendable {
    public let library: ContentLibrary
    public init(library: ContentLibrary) { self.library = library }

    public static let xpFirstCompletion = 10
    public static let xpFirstTryBonus = 5
    public static let xpReplay = 2

    // MARK: Unlocks

    public func isUnitUnlocked(_ unit: Unit, _ p: CourseProgress, plan: Plan, config: StoreConfig = .default) -> Bool {
        guard FeatureGate.isAvailable(.lessons(unitOrder: unit.order), plan: plan, config: config) else { return false }
        if p.placedOutUnits.contains(unit.id) { return true }
        guard let prev = library.units.last(where: { $0.order < unit.order }) else { return true }
        return isUnitFinished(prev, p)
    }

    /// All quests done (or placed out). The mastery check is encouraged, never a wall.
    public func isUnitFinished(_ unit: Unit, _ p: CourseProgress) -> Bool {
        p.placedOutUnits.contains(unit.id) || unit.quests.allSatisfy { p.completedQuests.contains($0.id) }
    }

    public func status(of quest: Quest, in unit: Unit, _ p: CourseProgress, plan: Plan) -> QuestStatus {
        if p.completedQuests.contains(quest.id) { return .complete }
        guard isUnitUnlocked(unit, p, plan: plan) else { return .locked }
        let sorted = unit.quests.sorted { $0.order < $1.order }
        if let i = sorted.firstIndex(of: quest), i > 0 {
            let prev = sorted[i - 1]
            if !p.completedQuests.contains(prev.id) && !p.placedOutUnits.contains(unit.id) { return .locked }
        }
        return p.startedQuests.contains(quest.id) ? .inProgress : .available
    }

    /// The next quest to do, in course order.
    public func nextQuest(_ p: CourseProgress, plan: Plan) -> Quest? {
        for u in library.units {
            for q in u.quests.sorted(by: { $0.order < $1.order }) {
                let s = status(of: q, in: u, p, plan: plan)
                if s == .available || s == .inProgress { return q }
            }
        }
        return nil
    }

    /// The quest an NPC offers right now (the first open one they host), if any.
    public func quest(offeredBy npc: String, _ p: CourseProgress, plan: Plan) -> Quest? {
        for u in library.units {
            for q in u.quests.sorted(by: { $0.order < $1.order }) where q.npc == npc {
                let s = status(of: q, in: u, p, plan: plan)
                if s == .available || s == .inProgress { return q }
            }
        }
        return nil
    }

    public func isExitOpen(_ e: MapExit, _ p: CourseProgress) -> Bool {
        guard let need = e.requiresUnitOrder else { return true }
        guard let u = library.units.first(where: { $0.order == need }) else { return false }
        return isUnitFinished(u, p)
    }

    // MARK: Recording

    public func start(_ quest: Quest, profile: inout PlayerProfile) {
        profile.progress.startedQuests.insert(quest.id)
    }

    /// Records an activity attempt sequence that ended in completion.
    /// Wrong attempts are not punished; they just mean the item comes back sooner.
    @discardableResult
    public func complete(activity a: Activity, outcome o: ReviewOutcome, profile: inout PlayerProfile, now: Date) -> ActivityCompletion {
        let track = PracticeTrack.of(a)
        for item in a.items {
            var k = profile.knowledge[item] ?? ItemKnowledge(now: now)
            k.record(o, track: track, now: now)
            profile.knowledge[item] = k
        }

        let firstTry = o.correct && o.attempts == 1 && !o.usedHint
        let existing = profile.progress.completedActivities[a.id]
        let firstTime = existing == nil
        var xp = firstTime ? Self.xpFirstCompletion + (firstTry ? Self.xpFirstTryBonus : 0) : Self.xpReplay
        profile.progress.completedActivities[a.id] = ActivityRecord(
            firstTryCorrect: (existing?.firstTryCorrect ?? false) || firstTry,
            bestAttempts: min(existing?.bestAttempts ?? .max, o.attempts),
            completions: (existing?.completions ?? 0) + 1,
            lastCompleted: now)

        let day = ActivityLog.dayKey(now)
        profile.log.activitiesByDay[day, default: 0] += 1

        var result = ActivityCompletion(xpGained: 0, questCompleted: nil, cosmeticUnlocked: nil, badgeEarned: nil, firstTime: firstTime)
        if let (_, quest) = library.quest(containing: a.id), !profile.progress.completedQuests.contains(quest.id) {
            profile.progress.startedQuests.insert(quest.id)
            let done = quest.activities.allSatisfy { profile.progress.completedActivities[$0.id] != nil }
            if done {
                profile.progress.completedQuests.insert(quest.id)
                xp += quest.reward.xp
                result.questCompleted = quest.id
                if let c = quest.reward.cosmetic, profile.rewards.ownedCosmetics.insert(c).inserted { result.cosmeticUnlocked = c }
                if let b = quest.reward.badge, profile.rewards.badges.insert(b).inserted { result.badgeEarned = b }
            }
        }
        profile.rewards.xp += xp
        result.xpGained = xp
        return result
    }
}

extension ContentLibrary {
    public func quest(containing activityId: String) -> (unit: Unit, quest: Quest)? {
        for u in units { for q in u.quests where q.activities.contains(where: { $0.id == activityId }) { return (u, q) } }
        return nil
    }
}
