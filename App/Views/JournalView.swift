import SwiftUI
import LQCore

/// Quest journal: units, can-do goals, quests and their status, mastery checks.
struct JournalView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let lib = model.library, let prof = model.profile, let prog = model.progression {
                    if let next = prog.nextQuest(prof.progress, plan: model.plan) {
                        Section {
                            Label("Next: \(next.title). Find \(StarterVillage.npc(next.npc)?.name ?? "") at \(next.location).",
                                  systemImage: "location.north.circle.fill")
                        }
                    }
                    ForEach(lib.units) { u in
                        let unlocked = prog.isUnitUnlocked(u, prof.progress, plan: model.plan)
                        Section {
                            DisclosureGroup("I can…") {
                                ForEach(u.canDo, id: \.self) { Text("• \($0)").font(.subheadline) }
                            }
                            ForEach(u.quests.sorted { $0.order < $1.order }) { q in
                                questRow(q, status: prog.status(of: q, in: u, prof.progress, plan: model.plan))
                            }
                            if prog.isUnitFinished(u, prof.progress) {
                                let passed = prof.progress.passedMasteryChecks.contains(u.masteryCheck.id)
                                Button { model.sheet = .mastery(u.id) } label: {
                                    Label(passed ? "Mastery check passed. Take it again?" : "Take the mastery check",
                                          systemImage: passed ? "rosette" : "checkmark.seal")
                                }
                            }
                            DisclosureGroup("Culture notes") {
                                ForEach(u.culturalNotes) { CulturalNoteCard(note: $0).listRowInsets(EdgeInsets()) }
                            }
                        } header: {
                            HStack {
                                Text("Unit \(u.order): \(u.title)")
                                Spacer()
                                if !unlocked { Image(systemName: "lock.fill").accessibilityLabel("Locked") }
                            }
                        } footer: {
                            if !unlocked { Text("Finish the unit before to open this one, or take the placement test.") }
                        }
                    }
                    Section {
                        Button { model.sheet = .placement } label: {
                            Label("Already know some \(model.languageName)? Take the placement test", systemImage: "graduationcap")
                        }
                    }
                }
            }
            .navigationTitle("Quest journal")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func questRow(_ q: Quest, status: QuestStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(status))
                .foregroundStyle(status == .complete ? Color(p.success) : Color(p.secondaryText))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(q.title).font(.headline)
                Text("\(StarterVillage.npc(q.npc)?.name ?? q.npc) · \(q.location)").font(.caption).foregroundStyle(Color(p.secondaryText))
            }
            Spacer()
            if status == .complete {
                Button("Replay") { model.startQuest(q) }.buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(label(status))
    }

    private func icon(_ s: QuestStatus) -> String {
        switch s {
        case .locked: return "lock.circle"
        case .available: return "exclamationmark.circle.fill"
        case .inProgress: return "ellipsis.circle.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private func label(_ s: QuestStatus) -> String {
        switch s {
        case .locked: return "Locked"
        case .available: return "Ready to start"
        case .inProgress: return "In progress"
        case .complete: return "Complete"
        }
    }
}

/// Bag: equip cosmetic rewards and see badges. Purely visual; no gameplay effect.
struct BagView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: PixelArt.avatarImage(prof.avatar, scale: 8))
                                .interpolation(.none)
                                .accessibilityLabel("Your explorer")
                            Spacer()
                        }
                    }
                    Section("Items") {
                        let owned = Catalog.cosmetics.filter { prof.rewards.ownedCosmetics.contains($0.id) }
                        if owned.isEmpty { Text("Finish quests to earn items.") }
                        ForEach(owned) { c in
                            let on = prof.avatar.hat == c.id || prof.avatar.accessory == c.id
                            Button {
                                model.updateProfile { p in
                                    switch c.slot {
                                    case .hat: p.avatar.hat = on ? nil : c.id
                                    case .accessory: p.avatar.accessory = on ? nil : c.id
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(c.name)
                                        if model.activeCourseId == "en-es" { Text(c.spanishName).font(.caption) }
                                    }
                                    Spacer()
                                    if on { Label("Wearing", systemImage: "checkmark") }
                                }
                            }
                            .accessibilityValue(on ? "Wearing" : "Not wearing")
                        }
                    }
                    Section("Badges") {
                        let earned = Catalog.badges.filter { prof.rewards.badges.contains($0.id) }
                        if earned.isEmpty { Text("Badges appear here when you finish a unit or pass a mastery check.") }
                        ForEach(earned) { b in Label("\(b.name): \(b.detail)", systemImage: "rosette") }
                    }
                }
            }
            .navigationTitle("Bag")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
