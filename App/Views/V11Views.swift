import SwiftUI
import LQCore

private func playSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max / 2) }

// MARK: - 1. Today's path

struct TodayPathCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var onPlay: () -> Void

    var body: some View {
        if let prof = model.profile, let lib = model.library, let prog = model.progression {
            let steps = TodayPath.steps(prof, library: lib, progression: prog, plan: model.plan, now: Date())
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Today's path", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill").font(.headline)
                        Spacer()
                        Text("\(steps.filter(\.done).count)/\(steps.count)").font(.subheadline.bold())
                    }
                    PathChestButton(steps: steps)
                    ForEach(steps) { s in
                        Button { go(s.kind) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(s.done ? Color(p.success) : Color(p.secondaryText))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.subheadline.bold()).strikethrough(s.done)
                                    Text(s.detail).font(.caption).foregroundStyle(Color(p.secondaryText))
                                }
                                Spacer()
                                if !s.done { Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(s.title). \(s.detail). \(s.done ? "Done" : "Not done yet")")
                        .accessibilityIdentifier("path-\(s.kind.rawValue)")
                    }
                }
            }
        }
    }

    private func go(_ k: PathStepKind) {
        switch k {
        case .memoryCheck: model.sheet = .memoryCheck
        case .quest: onPlay()
        case .review: model.sheet = .review
        }
    }
}

// MARK: - 2. Warm-up guesses before a quest

struct WarmUpView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let questions: [RetentionQuestion]
    var onDone: () -> Void
    @State private var index = 0
    @State private var picked: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Label("Warm-up: have a guess!", systemImage: "sparkles").font(.title3.bold())
                Text("Guessing before you learn helps the real answer stick. Wrong guesses don't count against you.")
                    .font(.subheadline).multilineTextAlignment(.center)
                if index < questions.count {
                    let q = questions[index]
                    Text("Guess \(index + 1) of \(questions.count)").font(.caption)
                    HStack { Text(model.display(q.word)).font(.largeTitle.bold()); SpeakerButton(text: q.word) }
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                        Button { if picked == nil { picked = i; model.sfx(i == q.answerIndex ? .correct : .select) } } label: {
                            HStack {
                                Text(o).font(.title3)
                                if picked != nil, i == q.answerIndex { Image(systemName: "checkmark.circle.fill").accessibilityLabel("right answer") }
                                else if picked == i { Image(systemName: "xmark.circle.fill").accessibilityLabel("your guess") }
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                                .background(fill(i, q), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("warm-option-\(i)")
                    }
                    if let pk = picked {
                        Text(pk == q.answerIndex ? "Great guess!" : "It means “\(q.meaning)”. Watch for it in this quest!")
                            .font(.headline).multilineTextAlignment(.center)
                        Button(index + 1 == questions.count ? "Start the quest" : "Next guess") {
                            picked = nil; index += 1
                            if index >= questions.count { finish() }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("warm-next")
                    }
                }
                Button("Skip the warm-up") { onDone() }.font(.subheadline).accessibilityIdentifier("warm-skip")
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    private func fill(_ i: Int, _ q: RetentionQuestion) -> Color {
        guard let pk = picked else { return Color(p.surface) }
        if i == q.answerIndex { return Color(p.success).opacity(0.35) }
        return i == pk ? Color(p.retry).opacity(0.3) : Color(p.surface)
    }

    private func finish() {
        model.updateProfile { WarmUp.finished(profile: &$0) }
        model.checkMilestones()
        onDone()
    }
}

// MARK: - 16. Accent keys above a text field

struct AccentKeyBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var text: String
    var body: some View {
        let keys = AccentKeys.keys(for: model.profile?.courseId ?? "")
        if !keys.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(keys, id: \.self) { k in
                        Button(k) { text.append(k) }
                            .font(.title3).frame(minWidth: 40, minHeight: 40)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Type \(k)")
                    }
                }
            }
            .accessibilityIdentifier("accentKeys")
        }
    }
}

// MARK: - 5. Memory hook editor (in quiz feedback, after a miss)

struct MemoryHookEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let itemId: String
    @State private var text = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Make a memory hook: a silly picture, a rhyme, a word it sounds like.").font(.caption)
            HStack {
                TextField("e.g. “gato” → a cat on a gate", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("hookField")
                Button(saved ? "Saved" : "Save") {
                    model.updateProfile { WordNotes.addHook(text, for: itemId, profile: &$0) }
                    saved = true
                    model.checkMilestones()
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || saved)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("hookSave")
            }
        }
        .padding(12)
        .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { text = model.profile.flatMap { WordNotes.note(itemId, in: $0) } ?? "" }
    }
}

// MARK: - 8 + 11. Streak calendar and personal bests (My progress)

struct StreakCalendarSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        if let prof = model.profile {
            let days = Streak.calendarDays(prof, now: Date())
            Section {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(days) { d in
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(fill(d.mark))
                            if d.mark == .frozen { Image(systemName: "snowflake").font(.caption2).foregroundStyle(.white) }
                            if d.mark == .practiced { Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.white) }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityElement()
                        .accessibilityLabel("\(d.date.formatted(.dateTime.month(.wide).day())): \(label(d.mark))")
                    }
                }
            } header: { Text("Streak: last 4 weeks") } footer: { Text("Flame: practiced. Snowflake: a streak freeze covered the day.") }
        }
    }

    private func fill(_ m: DayMark) -> Color {
        switch m { case .practiced: return Color.orange; case .frozen: return Color.blue.opacity(0.7); case .none: return Color(p.surface) }
    }
    private func label(_ m: DayMark) -> String {
        switch m { case .practiced: return "practiced"; case .frozen: return "streak freeze"; case .none: return "no practice" }
    }
}

struct PersonalBestsSection: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile {
            let b = PersonalBests.make(prof, now: Date())
            Section("Personal bests") {
                Label("Longest streak: \(b.longestStreak) day\(b.longestStreak == 1 ? "" : "s")", systemImage: "flame.fill")
                Label("Perfect quizzes in a row: \(b.perfectRun)", systemImage: "star.fill")
                if let w = b.bestWeekAverage { Label("Best week: \(w)% on quizzes", systemImage: "chart.bar.fill") }
                Label("Most new words in a day: \(b.mostWordsInADay)", systemImage: "text.book.closed.fill")
            }
        }
    }
}

// MARK: - 10. Weekly recap

struct WeeklyRecapCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile, let r = WeeklyRecap.make(prof, now: Date()) {
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Your week", systemImage: "calendar.badge.clock").font(.headline)
                        Text(r.line).font(.subheadline)
                        Button("See my progress") { model.sheet = .myProgress }.font(.subheadline.bold())
                    }
                    Spacer()
                    Button { model.updateProfile { WeeklyRecap.dismiss(r, profile: &$0) } } label: {
                        Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close the weekly recap")
                }
            }
            .accessibilityIdentifier("weeklyRecap")
        }
    }
}

// MARK: - 12. Learning summary in the Parents area

struct ParentLearningSection: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Section {
            ForEach(model.save.profiles, id: \.id) { prof in
                let s = LearningSummary.make(prof, now: Date())
                VStack(alignment: .leading, spacing: 4) {
                    Text(prof.nickname.isEmpty ? "Explorer" : prof.nickname).font(.headline)
                    Text("Quizzes this week: \(s.quizzesThisWeek)" + (s.averageThisWeek.map { " · average \($0)%" } ?? ""))
                    Text("Streak: \(s.streak) day\(s.streak == 1 ? "" : "s") · words locked in: \(s.lockedIn)")
                    if let r = s.rememberedNow { Text("Estimated words remembered today: \(r)%") }
                    if let t = PracticeTimes.summary(prof) { Text(t) }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        } header: { Text("Learning") } footer: {
            Text("From lesson quizzes and memory checks. \"Remembered today\" is the app's estimate from when each word was last practiced.")
        }
    }
}

// MARK: - 18. Retake a lesson quiz

struct LessonQuizSheet: View {
    @Environment(\.dismiss) var dismiss
    let questId: String
    var body: some View {
        NavigationStack {
            RetentionQuizView(kind: .lesson(questId: questId)) { _ in dismiss() }
                .background(ThemedBackground())
                .navigationTitle("Lesson quiz")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
