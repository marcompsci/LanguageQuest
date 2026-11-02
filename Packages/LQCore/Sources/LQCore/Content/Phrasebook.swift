import Foundation

/// The player's phrasebook: every word and phrase they've met, searchable in
/// Spanish (accent-insensitive, any region's form) or English, with mastery level
/// and how other regions say it.
public struct PhrasebookEntry: Hashable, Identifiable, Sendable {
    public var id: String { item.id }
    public var item: LexItem
    public var unitTitle: String
    public var unitOrder: Int
    public var level: MasteryLevel
    /// (variant name, form) for regions that say it differently from the learner's variant.
    public var otherRegions: [RegionalForm]
}

public struct RegionalForm: Hashable, Sendable {
    public var variantName: String
    public var form: String
}

public enum Phrasebook {
    public static func entries(_ p: PlayerProfile, library: ContentLibrary, query: String = "", includeUnmet: Bool = false) -> [PhrasebookEntry] {
        let q = AnswerChecker.fold(query)
        var out: [PhrasebookEntry] = []
        for u in library.units {
            for item in u.allItems {
                let k = p.knowledge[item.id]
                guard includeUnmet || k != nil else { continue }
                if !q.isEmpty {
                    let hay = (item.target.allForms + [item.english]).map(AnswerChecker.fold)
                    guard hay.contains(where: { $0.contains(q) }) else { continue }
                }
                let mine = item.target.text(for: p.variant)
                var others: [RegionalForm] = []
                var seen: Set<String> = [mine]
                for v in library.course.variants where v.id != p.variant {
                    let f = item.target.text(for: v.id)
                    if seen.insert(f).inserted { others.append(RegionalForm(variantName: v.name, form: f)) }
                }
                out.append(PhrasebookEntry(item: item, unitTitle: u.title, unitOrder: u.order,
                                           level: k?.level ?? .new, otherRegions: others))
            }
        }
        return out
    }
}
