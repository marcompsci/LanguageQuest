import Foundation

public struct ContentProblem: CustomStringConvertible, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var message: String
    public var description: String { "[\(severity.rawValue)] \(message)" }
}

/// Checks authored content before it can load. The rules mirror the
/// curriculum requirements in docs/CURRICULUM.md.
public enum ContentValidator {
    public static let minQuestsPerUnit = 5
    public static let minActivityTypesPerQuest = 3
    public static let placeholderMarkers = ["todo", "tbd", "lorem", "xxx", "placeholder", "fixme", "???"]

    /// - Parameter releaseBuild: when true, content below `released` is an error.
    public static func validate(_ lib: ContentLibrary, releaseBuild: Bool = false) -> [ContentProblem] {
        var p: [ContentProblem] = []
        func err(_ m: String) { p.append(.init(severity: .error, message: m)) }
        func warn(_ m: String) { p.append(.init(severity: .warning, message: m)) }

        let course = lib.course
        let variantIds = Set(course.variants.map(\.id))
        if !variantIds.contains(course.defaultVariant) { err("Default variant \(course.defaultVariant) is not in the variant list") }
        if Set(course.variants.map(\.id)).count != course.variants.count { err("Duplicate variant ids") }

        var ids = Set<String>()
        func claim(_ id: String, _ what: String) {
            if id.isEmpty { err("Empty id on \(what)") }
            if !ids.insert(id).inserted { err("Duplicate id \(id) (\(what))") }
        }

        func checkText(_ t: VText, _ ctx: String) {
            for form in t.allForms {
                if form.trimmingCharacters(in: .whitespaces).isEmpty { err("Empty text in \(ctx)") }
                let lower = form.lowercased()
                for m in placeholderMarkers where lower.contains(m) { err("Placeholder text \"\(form)\" in \(ctx)") }
            }
            for v in t.regionalVariants where !variantIds.contains(v) { err("Unknown variant \(v) in \(ctx)") }
        }
        func checkEnglish(_ s: String, _ ctx: String) {
            if s.trimmingCharacters(in: .whitespaces).isEmpty { err("Empty English in \(ctx)") }
            let lower = s.lowercased()
            for m in placeholderMarkers where lower.contains(m) { err("Placeholder text \"\(s)\" in \(ctx)") }
        }

        if lib.units.isEmpty { err("Course has no units") }

        for unit in lib.units {
            let u = "unit \(unit.id)"
            claim(unit.id, u)
            checkText(unit.targetTitle, "\(u) title")
            checkEnglish(unit.objective, "\(u) objective")
            if unit.canDo.isEmpty { err("\(u) has no can-do statements") }
            if unit.actfl.modes.isEmpty { err("\(u) has no ACTFL modes") }
            if unit.ageBands.isEmpty { err("\(u) has no age bands") }
            if unit.culturalNotes.isEmpty { err("\(u) has no cultural notes") }
            if releaseBuild && unit.review.text < .released { err("\(u) text is \(unit.review.text.rawValue), not released") }
            if releaseBuild && unit.review.audio < .released { err("\(u) audio is \(unit.review.audio.rawValue), not released") }
            if unit.review.text == .released && unit.review.reviewers.isEmpty { err("\(u) is released but lists no reviewer") }
            if unit.review.text < .linguistReviewed { warn("\(u) text has not had a linguist review (\(unit.review.text.rawValue))") }

            var itemIds = Set<String>()
            for item in unit.allItems {
                claim(item.id, "\(u) item")
                itemIds.insert(item.id)
                checkText(item.target, "item \(item.id)")
                checkEnglish(item.english, "item \(item.id)")
                if item.picture != nil && (item.altText ?? "").isEmpty { err("Item \(item.id) has a picture but no alt text") }
                if let ex = item.example { checkText(ex.target, "item \(item.id) example"); checkEnglish(ex.english, "item \(item.id) example") }
            }
            for note in unit.culturalNotes {
                claim(note.id, "\(u) note")
                checkEnglish(note.body, "note \(note.id)")
                for v in (note.byVariant ?? [:]).keys where !variantIds.contains(v) { err("Unknown variant \(v) in note \(note.id)") }
            }

            if unit.quests.count < minQuestsPerUnit { err("\(u) has \(unit.quests.count) quests; needs \(minQuestsPerUnit)") }
            if Set(unit.quests.map(\.order)).count != unit.quests.count { err("\(u) has duplicate quest order numbers") }

            var skills = Set<Skill>()
            var usedItems = Set<String>()
            for quest in unit.quests {
                let q = "quest \(quest.id)"
                claim(quest.id, q)
                checkEnglish(quest.title, "\(q) title")
                checkEnglish(quest.objective, "\(q) objective")
                if quest.reward.xp <= 0 { err("\(q) gives no XP") }
                let types = Set(quest.activities.map(\.type))
                if types.count < minActivityTypesPerQuest { err("\(q) uses \(types.count) activity types; needs \(minActivityTypesPerQuest)") }
                p += validateDialogue(quest.dialogue, ctx: q, variantIds: variantIds)
                for a in quest.activities {
                    claim(a.id, "activity")
                    skills.insert(a.skill)
                    usedItems.formUnion(a.items)
                    p += validateActivity(a, knownItems: Set(lib.allItems.map(\.id)), variantIds: variantIds)
                }
            }
            for s in Skill.allCases where !skills.contains(s) { err("\(u) never practices \(s.rawValue)") }
            for id in itemIds.subtracting(usedItems) { warn("Item \(id) in \(u) is never practiced in a quest") }

            claim(unit.masteryCheck.id, "mastery check")
            if unit.masteryCheck.activities.count < 4 { err("\(u) mastery check needs at least 4 activities") }
            if !(50...100).contains(unit.masteryCheck.passPercent) { err("\(u) mastery pass percent must be 50–100") }
            for a in unit.masteryCheck.activities {
                claim(a.id, "mastery activity")
                if a.practice != .independent { err("Mastery activity \(a.id) must be independent practice") }
                p += validateActivity(a, knownItems: Set(lib.allItems.map(\.id)), variantIds: variantIds)
            }
        }
        return p
    }

    static func validateActivity(_ a: Activity, knownItems: Set<String>, variantIds: Set<String>) -> [ContentProblem] {
        var p: [ContentProblem] = []
        func err(_ m: String) { p.append(.init(severity: .error, message: "activity \(a.id): \(m)")) }
        func checkVariants(_ t: VText) { for v in t.regionalVariants where !variantIds.contains(v) { err("unknown variant \(v)") } }

        if a.items.isEmpty { err("practices no items") }
        for i in a.items where !knownItems.contains(i) { err("unknown item \(i)") }
        if a.prompt.trimmingCharacters(in: .whitespaces).isEmpty { err("empty prompt") }
        if a.hint.isEmpty { err("needs a hint (errors get feedback, not punishment)") }
        if a.explanation.isEmpty { err("needs an explanation") }
        if let t = a.target { checkVariants(t) }

        // Skill must match what the activity actually asks the learner to do.
        let expected: [ActivityType: Set<Skill>] = [
            .listenChoose: [.listening], .readChoose: [.reading], .match: [.reading],
            .buildSentence: [.writing, .reading], .fillBlank: [.reading, .writing],
            .typeAnswer: [.writing], .speak: [.speaking], .dialogueReply: [.listening, .reading]
        ]
        if let ok = expected[a.type], !ok.contains(a.skill) { err("skill \(a.skill.rawValue) doesn't fit type \(a.type.rawValue)") }

        switch a.type {
        case .listenChoose, .readChoose, .fillBlank, .dialogueReply:
            guard let choices = a.choices, choices.count >= 2 else { err("needs 2+ choices"); break }
            if Set(choices.map(\.id)).count != choices.count { err("duplicate choice ids") }
            guard let ans = a.answer, choices.contains(where: { $0.id == ans }) else { err("answer is not one of the choices"); break }
            for c in choices {
                checkVariants(c.text)
                if c.picture != nil && (c.altText ?? "").isEmpty { err("choice \(c.id) picture needs alt text") }
            }
            // No two choices may read the same in any variant (would be two right answers).
            let forms = choices.map { $0.text.base.lowercased() }
            if Set(forms).count != forms.count { err("two choices have the same text") }
            if a.type == .listenChoose || a.type == .readChoose || a.type == .dialogueReply, a.target == nil { err("needs target text") }
            if a.type == .fillBlank {
                guard let s = a.sentence else { err("needs a sentence"); break }
                for f in s.allForms where !f.contains("___") { err("sentence form \"\(f)\" has no ___ blank") }
            }
        case .match:
            guard let pairs = a.pairs, pairs.count >= 3 else { err("needs 3+ pairs"); break }
            if Set(pairs.map(\.english)).count != pairs.count { err("duplicate English in pairs") }
            if Set(pairs.map { $0.target.base }).count != pairs.count { err("duplicate Spanish in pairs") }
        case .buildSentence:
            guard let tiles = a.tiles, tiles.count >= 2 else { err("needs 2+ tiles"); break }
            tiles.forEach(checkVariants)
            let tileForms = Set(tiles.map(\.base))
            for d in a.distractors ?? [] where tileForms.contains(d.base) { err("distractor \(d.base) is also a tile") }
            if a.targetEnglish == nil { err("needs targetEnglish (what to build)") }
        case .typeAnswer, .speak:
            guard let acc = a.accepted, !acc.isEmpty else { err("needs accepted answers"); break }
            acc.forEach(checkVariants)
            if a.type == .speak && a.target == nil { err("speak needs target text to model") }
            if a.targetEnglish == nil && a.type == .typeAnswer { err("needs targetEnglish (what to write)") }
        }
        return p
    }

    static func validateDialogue(_ d: Dialogue, ctx: String, variantIds: Set<String>) -> [ContentProblem] {
        var p: [ContentProblem] = []
        func err(_ m: String) { p.append(.init(severity: .error, message: "\(ctx) dialogue: \(m)")) }
        let byId = Dictionary(d.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if byId.count != d.nodes.count { err("duplicate node ids") }
        guard byId[d.start] != nil else { err("start node \(d.start) missing"); return p }

        for n in d.nodes {
            for v in n.line.regionalVariants where !variantIds.contains(v) { err("unknown variant \(v) in \(n.id)") }
            if n.gloss.isEmpty { err("node \(n.id) has no English gloss") }
            if let next = n.next, byId[next] == nil { err("node \(n.id) points to missing \(next)") }
            if let cs = n.choices {
                if cs.isEmpty { err("node \(n.id) has an empty choice list") }
                if n.next != nil { err("node \(n.id) has both next and choices") }
                if cs.allSatisfy({ $0.correct == false }) { err("node \(n.id): every choice is wrong") }
                for c in cs where byId[c.next] == nil { err("node \(n.id) choice points to missing \(c.next)") }
                for c in cs where c.correct == false && (c.feedback ?? "").isEmpty { err("node \(n.id): wrong choice needs gentle feedback") }
            }
        }
        // Reachability + guaranteed ending: from every reachable node some end node is reachable.
        var reachable = Set<String>()
        var stack = [d.start]
        while let id = stack.popLast() {
            guard reachable.insert(id).inserted, let n = byId[id] else { continue }
            if let nx = n.next { stack.append(nx) }
            for c in n.choices ?? [] { stack.append(c.next) }
        }
        for n in d.nodes where !reachable.contains(n.id) { err("node \(n.id) is unreachable") }
        let ends = Set(d.nodes.filter { $0.next == nil && ($0.choices ?? []).isEmpty }.map(\.id))
        if ends.isEmpty { err("no ending node") }
        // Reverse search from ends.
        var canEnd = ends
        var changed = true
        while changed {
            changed = false
            for n in d.nodes where !canEnd.contains(n.id) {
                let outs = (n.next.map { [$0] } ?? []) + (n.choices ?? []).map(\.next)
                if outs.contains(where: canEnd.contains) { canEnd.insert(n.id); changed = true }
            }
        }
        for id in reachable where !canEnd.contains(id) { err("node \(id) can never reach an ending") }
        return p
    }
}
