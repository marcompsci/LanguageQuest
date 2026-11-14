import SwiftUI
import LQCore

/// A seed that changes each play.
private func playSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max / 2) }

// MARK: - 1 + 2. Word Library with stars

struct WordLibraryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var filter: WordFilter = .all
    @State private var query = ""
    @State private var openId: String?

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile, let lib = model.library {
                    let entries = WordLibrary.entries(prof, library: lib, filter: filter, query: query)
                    let starredCount = (prof.extrasOrEmpty.starredWords ?? []).filter { lib.item($0) != nil }.count
                    Section {
                        Picker("Show", selection: $filter) {
                            ForEach(WordFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("wordFilter")
                        Button {
                            model.sheet = .starredPractice
                        } label: {
                            Label(starredCount == 0 ? "Star words to practice them together" : "Practice starred words (\(starredCount))",
                                  systemImage: "star.fill")
                        }
                        .disabled(starredCount == 0)
                        .accessibilityIdentifier("practiceStarred")
                    } footer: {
                        Text(footer(entries.count, total: lib.allItems.count))
                    }
                    ForEach(entries) { e in row(e, lib) }
                }
            }
            .searchable(text: $query, prompt: "Search words or meanings")
            .navigationTitle("Word Library")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func footer(_ shown: Int, total: Int) -> String {
        switch filter {
        case .all: return query.isEmpty ? "Every word and phrase in this language. Tap one to see more." : "\(shown) found."
        case .met: return "Words you've met in quests and games."
        case .practice: return "Words that are new to you or ready for review."
        case .starred: return "Tap ☆ on any word to add it here."
        }
    }

    @ViewBuilder
    private func row(_ e: WordEntry, _ lib: ContentLibrary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { withAnimation { openId = openId == e.id ? nil : e.id } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.display(e.item.target)).font(.headline)
                        Text(e.item.english).font(.subheadline).foregroundStyle(Color(p.secondaryText))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(openId == e.id ? "Hides details" : "Shows details")
                Text(e.met ? e.level.label : "Unit \(e.unitOrder)").font(.caption)
                    .foregroundStyle(Color(p.secondaryText))
                Button {
                    model.updateProfile { StarredWords.toggle(e.id, profile: &$0) }
                    model.sfx(.select)
                    model.checkMilestones()
                } label: {
                    Image(systemName: e.starred ? "star.fill" : "star").foregroundStyle(Color(p.accent))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e.starred ? "Unstar \(model.text(e.item.target))" : "Star \(model.text(e.item.target))")
                .accessibilityIdentifier("star-\(e.id)")
            }
            if openId == e.id {
                HStack { SpeakerButton(text: e.item.target, label: "Hear \(model.text(e.item.target))"); Spacer() }
                if let ex = e.item.example {
                    Text(model.display(ex.target)).font(.subheadline.italic())
                    Text(ex.english).font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                if let note = e.item.note { Text(note).font(.caption) }
                if let pos = e.item.partOfSpeech { Text(pos).font(.caption2).foregroundStyle(Color(p.secondaryText)) }
            }
        }
    }
}

// MARK: - 3. Word of the day

struct WordOfTheDayCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    var body: some View {
        if let prof = model.profile, let lib = model.library, let w = WordOfTheDay.pick(prof, library: lib, now: Date()) {
            Card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Word of the day", systemImage: "sparkle").font(.caption.bold()).foregroundStyle(Color(p.secondaryText))
                        Text(model.display(w.target)).font(.title2.bold())
                        Text(w.english).font(.subheadline)
                    }
                    Spacer()
                    SpeakerButton(text: w.target, label: "Hear the word of the day")
                    Button {
                        model.updateProfile { StarredWords.toggle(w.id, profile: &$0) }
                        model.checkMilestones()
                    } label: {
                        Image(systemName: StarredWords.isStarred(w.id, in: prof) ? "star.fill" : "star")
                            .font(.title3).frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(StarredWords.isStarred(w.id, in: prof) ? "Unstar the word of the day" : "Star the word of the day")
                }
            }
            .accessibilityIdentifier("wordOfTheDay")
        }
    }
}

// MARK: - 4. Sentence Builder

struct SentenceBuilderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: SentenceBuilder?
    @State private var placed: [Int] = []      // indexes into the tiles
    @State private var feedback: String?
    @State private var finished = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let g = game, let pz = g.current {
                        Text("Sentence \(g.index + 1) of \(g.puzzles.count)").font(.caption)
                        Text("Build this sentence:").font(.headline)
                        Text(pz.english).font(.title3).multilineTextAlignment(.center)
                        answerArea(pz)
                        tilesArea(pz)
                        if let f = feedback { Text(f).font(.headline).multilineTextAlignment(.center) }
                        HStack {
                            Button("Clear") { placed = []; feedback = nil }.buttonStyle(.bordered).disabled(placed.isEmpty)
                            Button("Skip") { skip() }.buttonStyle(.bordered)
                            Button("Check") { check(pz) }.buttonStyle(PrimaryButtonStyle())
                                .disabled(placed.count != pz.tiles.count)
                                .accessibilityIdentifier("builderCheck")
                        }
                    } else if let g = game, !g.puzzles.isEmpty {
                        Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars))
                            .font(.largeTitle).accessibilityLabel("\(g.stars) of 3 stars")
                        Text("\(g.firstTryCorrect) of \(g.puzzles.count) right the first time").font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    } else if game != nil {
                        Text("Talk to someone in the village first, then their sentences show up here.")
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(ThemedBackground())
            .environment(\.layoutDirection, (model.library?.course.rightToLeft ?? false) ? .rightToLeft : .leftToRight)
            .navigationTitle("Sentence Builder")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
        }
    }

    private func answerArea(_ pz: SentencePuzzle) -> some View {
        WrapLayout(spacing: 8) {
            ForEach(Array(placed.enumerated()), id: \.offset) { slot, tileIndex in
                Button { placed.remove(at: slot); feedback = nil } label: { tile(pz.tiles[tileIndex], filled: true) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Takes this word back out")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(10)
        .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(p.accent).opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6])))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placed.isEmpty ? "Your sentence is empty" : "Your sentence")
    }

    private func tilesArea(_ pz: SentencePuzzle) -> some View {
        WrapLayout(spacing: 8) {
            ForEach(Array(pz.tiles.enumerated()).filter { !placed.contains($0.offset) }, id: \.offset) { i, t in
                Button { placed.append(i); feedback = nil; model.sfx(.select) } label: { tile(t, filled: false) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tile-\(i)")
            }
        }
    }

    private func tile(_ t: String, filled: Bool) -> some View {
        Text(t).font(.title3.bold())
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(filled ? Color(p.accent).opacity(0.22) : Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(p.accent).opacity(0.6)))
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        game = SentenceBuilder(profile: prof, library: lib, seed: playSeed())
        placed = []; feedback = nil; finished = false
    }

    private func check(_ pz: SentencePuzzle) {
        guard var g = game else { return }
        let ok = g.check(placed.map { pz.tiles[$0] })
        game = g
        model.sfx(ok ? .correct : .retry)
        if ok {
            model.say(VText(pz.full))
            placed = []; feedback = nil
            if g.isFinished { done(g) }
        } else {
            feedback = "Not quite. Tap a word in your sentence to move it back, then try again."
        }
    }

    private func skip() {
        guard var g = game else { return }
        g.skip(); game = g; placed = []; feedback = nil
        if g.isFinished { done(g) }
    }

    private func done(_ g: SentenceBuilder) {
        guard !finished else { return }
        finished = true
        model.updateProfile { SentenceBuilder.finish(g, profile: &$0) }
        model.record(.gamePlayed)
    }
}

/// Lays out views left to right, wrapping onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: subviews.isEmpty ? 0 : y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(sz.width, bounds.width), height: sz.height))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - 5. Unit quizzes

struct QuizzesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile, let lib = model.library {
                    Section {
                        ForEach(lib.units.sorted { $0.order < $1.order }, id: \.id) { u in
                            let open = UnitQuiz.isOpen(u, progress: prof.progress)
                            let best = prof.extrasOrEmpty.quizBest?[u.id]
                            NavigationLink {
                                UnitQuizView(unitId: u.id)
                            } label: {
                                HStack {
                                    Image(systemName: open ? "checklist" : "lock.fill").frame(width: 28).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Unit \(u.order): \(u.title)").font(.headline)
                                        Text(open ? (best.map { "Best score: \($0)%" } ?? "Not taken yet")
                                                  : "Finish a quest in this unit to open it")
                                            .font(.caption).foregroundStyle(Color(p.secondaryText))
                                    }
                                }
                            }
                            .disabled(!open)
                            .accessibilityIdentifier("quiz-\(u.order)")
                        }
                    } footer: {
                        Text("Ten quick questions on a unit's words, both ways round. Take a quiz as often as you like; your best score is kept.")
                    }
                }
            }
            .navigationTitle("Unit quizzes")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct UnitQuizView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let unitId: String
    @State private var quiz: UnitQuiz?
    @State private var picked: Int?
    @State private var shownIndex = 0
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let q = quiz, shownIndex < q.questions.count {
                    let item = q.questions[shownIndex]
                    ProgressView(value: Double(shownIndex), total: Double(q.questions.count)).tint(Color(p.accent))
                    Text(item.showsTarget ? "What does this mean?" : "How do you say this?").font(.headline)
                    HStack {
                        Text(item.promptText.map { model.display($0) } ?? item.prompt).font(.title.bold()).multilineTextAlignment(.center)
                        if let t = item.promptText { SpeakerButton(text: t) }
                    }
                    ForEach(Array(item.options.enumerated()), id: \.offset) { i, o in
                        Button { pick(i, item) } label: {
                            Text(item.optionTexts.map { model.display($0[i]) } ?? o).font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .padding(.horizontal, 8)
                                .background(fill(i, item), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                        .accessibilityIdentifier("quiz-option-\(i)")
                    }
                    if picked != nil {
                        Button(shownIndex + 1 == q.questions.count ? "See my score" : "Next") { picked = nil; shownIndex += 1; finishIfDone() }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("quizNext")
                    }
                } else if let q = quiz {
                    Text("\(q.percent)%").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    Text("\(q.correct) of \(q.questions.count) right").font(.title2.bold())
                    Text(q.percent == 100 ? "Perfect! You know this unit." : "Missed words come back sooner in your reviews.")
                        .multilineTextAlignment(.center)
                    Button("Try again") { start() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(ThemedBackground())
        .navigationTitle("Quiz")
        .onAppear { if quiz == nil { start() } }
    }

    private func fill(_ i: Int, _ q: QuizQuestion) -> Color {
        guard let pk = picked else { return Color(p.surface) }
        if i == q.answerIndex { return Color.green.opacity(0.35) }
        return i == pk ? Color.red.opacity(0.3) : Color(p.surface)
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library, let u = lib.units.first(where: { $0.id == unitId }) else { return }
        quiz = UnitQuiz(unit: u, profile: prof, library: lib, seed: playSeed())
        picked = nil; shownIndex = 0; saved = false
    }

    private func pick(_ i: Int, _ item: QuizQuestion) {
        guard var q = quiz else { return }
        let ok = q.answer(i)
        quiz = q; picked = i
        model.sfx(ok ? .correct : .retry)
        model.updateProfile { UnitQuiz.record(item, correct: ok, profile: &$0, now: Date()) }
    }

    private func finishIfDone() {
        guard let q = quiz, q.isFinished, shownIndex >= q.questions.count, !saved else { return }
        saved = true
        model.updateProfile { UnitQuiz.finish(q, profile: &$0) }
        model.record(.activity)
    }
}

// MARK: - 6. Weekly goal

struct WeeklyGoalCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    var body: some View {
        if let prof = model.profile {
            let now = Date()
            let goal = WeeklyGoal.goal(prof), done = WeeklyGoal.daysPracticed(prof, now: now)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Weekly goal", systemImage: "calendar").font(.headline)
                        Spacer()
                        Menu {
                            ForEach(WeeklyGoal.choices, id: \.self) { d in
                                Button("\(d) days a week") { model.updateProfile { WeeklyGoal.setGoal(d, profile: &$0) } }
                            }
                        } label: {
                            Text("\(goal) days").font(.subheadline.bold())
                        }
                        .accessibilityLabel("Goal: \(goal) days a week. Change goal")
                        .accessibilityIdentifier("weeklyGoalPicker")
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<goal, id: \.self) { i in
                            Circle().fill(i < done ? Color(p.accent) : Color(p.secondaryText).opacity(0.25))
                                .frame(width: 18, height: 18)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(min(done, goal)) of \(goal) days")
                    HStack {
                        Text(WeeklyGoal.message(prof, now: now)).font(.subheadline)
                        Spacer()
                        if WeeklyGoal.isMet(prof, now: now) && !WeeklyGoal.isClaimed(prof, now: now) {
                            Button("+\(WeeklyGoal.xp) XP") {
                                model.updateProfile { _ = WeeklyGoal.claim(&$0, now: now) }
                                model.sfx(.coin)
                                model.checkMilestones()
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("claimWeekly")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 7 + 8. Parent area: reminders and weekly report

struct ParentRemindersSection: View {
    @EnvironmentObject var model: AppModel
    @State private var message: String?

    private var plan: ReminderPlan { model.save.parent.reminderPlan }
    private let dayNames = Calendar.current.shortWeekdaySymbols   // index 0 = Sunday

    var body: some View {
        Section {
            Toggle("Practice reminders", isOn: Binding(
                get: { plan.enabled },
                set: { on in
                    if on {
                        Task { @MainActor in
                            let ok = await ReminderScheduler.requestPermission()
                            update { $0.enabled = ok }
                            message = ok ? nil : "Notifications aren't allowed for Language Quest. You can allow them in the iPhone's Settings › Notifications."
                        }
                    } else {
                        update { $0.enabled = false }
                    }
                }))
            .accessibilityIdentifier("remindersToggle")
            if plan.enabled {
                DatePicker("Time", selection: Binding(
                    get: { Calendar.current.date(from: DateComponents(hour: plan.hour, minute: plan.minute)) ?? Date() },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        update { $0.hour = c.hour ?? 17; $0.minute = c.minute ?? 0 }
                    }), displayedComponents: .hourAndMinute)
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { wd in
                        let on = plan.weekdays.contains(wd)
                        Button(String(dayNames[wd - 1].prefix(2))) {
                            update { p in
                                if on { if p.weekdays.count > 1 { p.weekdays.removeAll { $0 == wd } } } else { p.weekdays.append(wd); p.weekdays.sort() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? Color.accentColor : Color.gray)
                        .accessibilityLabel("\(Calendar.current.weekdaySymbols[wd - 1]), \(on ? "on" : "off")")
                    }
                }
            }
            if let m = message { Text(m).font(.caption) }
        } header: { Text("Reminders") } footer: {
            Text("Off by default. A gentle notification on the days and time you pick. It's scheduled on this device only, shows no name or progress, and needs no account.")
        }
    }

    private func update(_ change: (inout ReminderPlan) -> Void) {
        var plan = model.save.parent.reminderPlan
        change(&plan)
        model.updateParent { $0.reminders = plan }
        ReminderScheduler.apply(plan)
    }
}

struct ParentWeeklyReportSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let prof = model.profile {
            let r = WeeklyReport.make(prof, libraries: model.libraries, now: Date())
            Section {
                ForEach(r.lines.dropLast(), id: \.self) { Text($0).font(.subheadline) }
                ShareLink(item: r.text, subject: Text(r.title)) {
                    Label("Share this summary", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareReport")
            } header: { Text("This week") } footer: {
                Text("Made on this device from the last 7 days. It's only shared if you tap Share and choose where it goes.")
            }
        }
    }
}
