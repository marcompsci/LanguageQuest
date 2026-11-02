import Foundation

/// One line per language on the menu and in the language switcher.
public struct CourseSummary: Hashable, Identifiable, Sendable {
    public var id: String { courseId }
    public var courseId: String
    public var language: String
    public var nativeName: String
    public var flag: String
    public var isActive: Bool
    public var started: Bool
    public var questsDone: Int
    public var questsTotal: Int
    public var wordsMet: Int
    public var wordsUnderstood: Int

    public var fraction: Double { questsTotal == 0 ? 0 : Double(questsDone) / Double(questsTotal) }
}

public enum CourseOverview {
    /// Summaries for every bundled course, in the given order, using the parked
    /// snapshot for courses that aren't active.
    public static func summaries(_ p: PlayerProfile, libraries: [String: ContentLibrary], order: [String]) -> [CourseSummary] {
        order.compactMap { id -> CourseSummary? in
            guard let lib = libraries[id] else { return nil }
            let active = p.courseId == id
            let snap = p.otherCourses?[id]
            let progress = active ? p.progress : snap?.progress ?? CourseProgress()
            let knowledge = active ? p.knowledge : snap?.knowledge ?? [:]
            let variant = active ? p.variant : snap?.variant ?? lib.course.defaultVariant
            let quests = lib.allQuests
            return CourseSummary(
                courseId: id, language: lib.course.displayLanguage, nativeName: lib.course.nativeName ?? lib.course.displayLanguage,
                flag: lib.course.variant(variant)?.flagEmoji ?? lib.course.variants.first?.flagEmoji ?? "🌐",
                isActive: active, started: active || snap != nil,
                questsDone: quests.filter { progress.completedQuests.contains($0.id) }.count,
                questsTotal: quests.count,
                wordsMet: knowledge.count,
                wordsUnderstood: knowledge.values.filter(\.comprehensionMastered).count)
        }
    }
}

/// Today's activity, for a friendly note on the menu. Deliberately no streaks.
public struct TodaySummary: Equatable, Sendable {
    public var activities: Int
    public var minutes: Int

    public static func compute(_ p: PlayerProfile, now: Date, calendar: Calendar = .current) -> TodaySummary {
        let key = ActivityLog.dayKey(now, calendar: calendar)
        return TodaySummary(activities: p.log.activitiesByDay[key] ?? 0, minutes: Int((p.log.minutesByDay[key] ?? 0).rounded()))
    }

    /// An encouraging line that never guilts.
    public var message: String {
        switch activities {
        case 0: return "Ready when you are. Every quest counts!"
        case 1...4: return "Nice start today: \(activities) activit\(activities == 1 ? "y" : "ies") done."
        case 5...14: return "Great work today: \(activities) activities done!"
        default: return "Wow, \(activities) activities today! Remember to take breaks."
        }
    }
}

/// Time of day in the village, from the device clock (no location needed).
public enum DayPhase: String, CaseIterable, Sendable {
    case morning, day, evening, night

    public static func of(hour: Int) -> DayPhase {
        switch hour {
        case 5..<9: return .morning
        case 9..<17: return .day
        case 17..<20: return .evening
        default: return .night
        }
    }

    public static func now(_ date: Date = Date(), calendar: Calendar = .current) -> DayPhase {
        of(hour: calendar.component(.hour, from: date))
    }

    /// Overlay color and strength for the village.
    public var tint: (color: RGB, alpha: Double) {
        switch self {
        case .morning: return (RGB(0xFFD9A0), 0.10)
        case .day: return (RGB(0xFFFFFF), 0)
        case .evening: return (RGB(0xFF8A50), 0.16)
        case .night: return (RGB(0x1B2A6B), 0.32)
        }
    }

    public var greeting: String {
        switch self {
        case .morning: return "Good morning"
        case .day: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Good night, night owl"
        }
    }
}

// MARK: - Per-language badges

extension Catalog {
    /// Spanish keeps the original badge ids; other courses prefix them ("en-fr:badge-u1").
    public static func badgeId(_ base: String, courseId: String) -> String {
        courseId == "en-es" ? base : "\(courseId):\(base)"
    }

    public static func masteryBadge(forUnitOrder n: Int, courseId: String) -> String {
        badgeId(masteryBadge(forUnitOrder: n), courseId: courseId)
    }

    static let heroNames: [String: (unit1: String, unit2: String, unit3: String, lang: String)] = [
        "en-es": ("Hola Hero", "Family Friend", "Market Pro", "Spanish"),
        "en-fr": ("Bonjour Hero", "Ami de la Famille", "Marché Master", "French"),
        "en-ja": ("Konnichiwa Hero", "Kazoku Friend", "Kaimono Pro", "Japanese"),
    ]

    /// Looks up a badge by id, including language-prefixed ids.
    public static func badge(anyId id: String) -> Badge? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let (course, base) = parts.count == 2 ? (parts[0], parts[1]) : ("en-es", id)
        guard var b = badge(base), let names = heroNames[course] else { return nil }
        b.id = id
        switch base {
        case "badge-u1": b.name = names.unit1
        case "badge-u2": b.name = names.unit2
        case "badge-u3": b.name = names.unit3
        default: break
        }
        b.detail = "\(names.lang): \(b.detail)"
        return b
    }
}
