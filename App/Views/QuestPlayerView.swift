import SwiftUI
import LQCore

/// Plays a quest's activities in order, then shows rewards.
struct QuestPlayerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    let questId: String

    @State private var index = 0
    @State private var xpEarned = 0
    @State private var reward: ActivityCompletion?
    @State private var showIntro = true
    /// v1.1: up to 3 warm-up guesses before a new quest (the pretesting effect).
    @State private var warmUp: [RetentionQuestion]?
    @State private var warmUpDone = false
    /// v1.0: every finished lesson ends with a 5-question quiz on what matters most to remember.
    @State private var quizDone = false
    @State private var quizScore: QuizRecord?

    private var entry: (unit: LessonUnit, quest: Quest)? { model.library?.quest(questId) }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                if let e = entry {
                    if showIntro {
                        intro(e.unit, e.quest)
                    } else if !warmUpDone, let w = warmUp, !w.isEmpty, index == 0 {
                        WarmUpView(questions: w) { warmUpDone = true }
                    } else if index < e.quest.activities.count {
                        let a = e.quest.activities[index]
                        VStack(spacing: 0) {
                            ProgressView(value: Double(index), total: Double(e.quest.activities.count))
                                .padding(.horizontal, 20)
                                .accessibilityLabel("Activity \(index + 1) of \(e.quest.activities.count)")
                            ScrollView {
                                ActivityHost(activity: a) { result in record(a, result) }
                                    .id(a.id)
                            }
                        }
                    } else if !quizDone {
                        RetentionQuizView(kind: .lesson(questId: e.quest.id)) { rec in quizScore = rec; quizDone = true }
                    } else {
                        finish(e.quest)
                    }
                }
            }
            .navigationTitle(entry?.quest.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityHint("Your progress so far is saved")
                }
            }
        }
    }

    private func intro(_ u: LessonUnit, _ q: Quest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.display(u.targetTitle)).font(.caption.bold()).foregroundStyle(Color(p.secondaryText))
                Text(q.title).font(.largeTitle.bold())
                Text(q.summary).font(.title3)
                Card {
                    Label("Goal: \(q.objective)", systemImage: "flag.checkered")
                }
                if let note = u.culturalNotes[safe: q.order - 1] ?? u.culturalNotes.first {
                    CulturalNoteCard(note: note)
                }
                Button("Let's go!") {
                    if let prof = model.profile, let lib = model.library, WarmUp.isOffered(q, profile: prof) {
                        warmUp = WarmUp.questions(q, profile: prof, library: lib, seed: UInt64.random(in: 1...UInt64.max / 2))
                    }
                    showIntro = false
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("startQuestButton")
            }
            .padding(20)
        }
    }

    private func record(_ a: Activity, _ r: ActivityResult) {
        if let c = model.complete(a, outcome: r.outcome, verified: r.verified) {
            xpEarned += c.xpGained
            if c.questCompleted != nil { reward = c }
        }
        index += 1
    }

    private func finish(_ q: Quest) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "star.circle.fill").font(.system(size: 80)).foregroundStyle(Color(p.accent))
                .accessibilityHidden(true)
            Text(model.phrases.questComplete).font(.largeTitle.bold())
                .onAppear { model.sfx(.reward) }
            Text("Quest complete: \(q.title)").font(.title3)
            Text("+\(xpEarned) XP").font(.title2.bold())
            if let q = quizScore { Label("Lesson quiz: \(q.correct) of \(q.total)", systemImage: "checkmark.seal").font(.headline) }
            if let c = reward?.cosmeticUnlocked, let item = Catalog.cosmetic(c) {
                Card { Label(model.activeCourseId == "en-es" ? "New item: \(item.name) (\(item.spanishName))" : "New item: \(item.name)", systemImage: "gift.fill") }
            }
            if let b = reward?.badgeEarned, let badge = Catalog.badge(anyId: b) {
                Card { Label("Badge: \(badge.name). \(badge.detail)", systemImage: "rosette") }
            }
            Text("XP shows how much you played. Your Review keeps track of what you remember.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Color(p.secondaryText))
            Spacer()
            Button("Back to the village") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("backToVillage")
        }
        .padding(24)
    }
}

struct CulturalNoteCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let note: CulturalNote
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(note.title, systemImage: "globe.americas.fill").font(.headline)
                Text(note.body).font(.subheadline)
                if let v = model.profile?.variant, let extra = note.byVariant?[v] {
                    Text(extra).font(.subheadline.italic())
                }
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
