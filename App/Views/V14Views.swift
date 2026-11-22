import SwiftUI
import Charts
import LQCore

private func playSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max / 2) }

// MARK: - A small multiple-choice game screen (articles, pictures, odd one out, family quiz, word chain)

struct ChoiceGameView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    let title: String
    let intro: String
    var bigOptions = false
    let counter: String
    let make: (PlayerProfile, ContentLibrary, UInt64) -> ChoiceRound
    @State private var round: ChoiceRound?
    @State private var started = false
    @State private var feedback: (ok: Bool, q: ChoiceQuestion)?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let r = round, r.questions.isEmpty {
                        Text("Meet a few more words in the village first, then come back.").multilineTextAlignment(.center)
                    } else if !started {
                        Text(intro).multilineTextAlignment(.center)
                        Button("Start") { started = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("choiceStart")
                    } else if let f = feedback {
                        Image(systemName: f.ok ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: 48))
                            .foregroundStyle(Color(f.ok ? p.success : p.retry))
                            .accessibilityLabel(f.ok ? "Right" : "Not quite")
                        Text(f.ok ? "Right!" : "Not quite").font(.title2.bold())
                        Text(f.q.explanation).multilineTextAlignment(.center)
                        Button(round?.isFinished == true ? "See my score" : "Next") { feedback = nil; if round?.isFinished == true { save() } }
                            .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("choiceNext")
                    } else if let r = round, let q = r.current {
                        Text("\(r.index + 1) of \(r.questions.count)").font(.caption)
                        HStack {
                            Text(q.prompt).font(.title.bold()).multilineTextAlignment(.center)
                            if let a = q.promptAudio { SpeakerButton(text: a) }
                        }
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                            Button { pick(i) } label: {
                                Text(o).font(bigOptions ? .system(size: 44) : .title3)
                                    .frame(maxWidth: .infinity, minHeight: model.profile?.settings.bigButtonsOn == true ? 76 : 56)
                                    .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character("\(min(i + 1, 9))")), modifiers: [])
                            .accessibilityIdentifier("choice-\(i)")
                        }
                    } else if let r = round {
                        Text("\(r.correct) of \(r.questions.count)").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .accessibilityIdentifier("choiceScore")
                        Text(r.correct == r.questions.count ? "Perfect!" : "Nice work. Play again to beat it.")
                        Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(ThemedBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if round == nil { start() } }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        round = make(prof, lib, playSeed())
        feedback = nil; saved = false
    }

    private func pick(_ i: Int) {
        guard var r = round, let q = r.current else { return }
        let ok = r.answer(i)
        round = r
        model.sfx(ok ? .correct : .retry)
        model.haptic(ok)
        feedback = (ok, q)
    }

    private func save() {
        guard !saved else { return }
        saved = true
        model.updateProfile { GameCounters.played(counter, profile: &$0) }
        model.record(.gamePlayed)
        model.checkMilestones()
    }
}

// MARK: - 4. Free recall

struct FreeRecallView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: FreeRecall?
    @State private var typed = ""
    @State private var endsAt: Date?
    @State private var remaining = Int(FreeRecall.seconds)
    @State private var done = false
    @State private var newBest = false
    @FocusState private var focused: Bool
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let g = game {
                    if done {
                        Image(systemName: "brain").font(.system(size: 50)).accessibilityHidden(true)
                        Text("\(g.found.count) of \(g.possible) words").font(.title.bold())
                        if newBest { Text("New best!").font(.headline) }
                        Text("Pulling words out of memory with no hints is one of the strongest ways to practise.")
                            .font(.subheadline).multilineTextAlignment(.center)
                        Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    } else if endsAt == nil {
                        Text("Free recall").font(.title.bold())
                        Text("Type as many words as you can remember from \"\(g.unitTitle)\" in \(Int(FreeRecall.seconds)) seconds. No hints!")
                            .multilineTextAlignment(.center)
                        Button("Go!") { endsAt = Date().addingTimeInterval(FreeRecall.seconds); focused = true }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("recallGo")
                    } else {
                        HStack {
                            Label("\(remaining)s", systemImage: "timer").font(.title3.monospacedDigit().bold())
                            Spacer()
                            Text("\(g.found.count) found").font(.title3.bold())
                        }
                        TextField("Type a word, then Return", text: $typed)
                            .textFieldStyle(.roundedBorder).font(.title3)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .focused($focused)
                            .onSubmit { submit() }
                            .accessibilityIdentifier("recallField")
                        AccentKeyBar(text: $typed)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(g.found.reversed(), id: \.self) { id in
                                    if let item = model.library?.item(id) {
                                        Label("\(model.display(item.target)) = \(item.english)", systemImage: "checkmark.circle.fill")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text("Meet some words in the village first.").multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            .background(ThemedBackground())
            .navigationTitle("Free recall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
            .onReceive(tick) { _ in
                guard let end = endsAt, !done else { return }
                remaining = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
                if remaining == 0 { finish() }
            }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library, let u = FreeRecall.bestUnit(prof, library: lib) else { return }
        game = FreeRecall(unit: u, profile: prof, library: lib)
        typed = ""; endsAt = nil; done = false; newBest = false; remaining = Int(FreeRecall.seconds)
    }

    private func submit() {
        guard var g = game else { return }
        let hit = g.submit(typed)
        game = g
        model.sfx(hit != nil ? .correct : .retry)
        if hit != nil { model.haptic(true) }
        typed = ""
        focused = true
    }

    private func finish() {
        guard let g = game, !done else { return }
        done = true
        var best = false
        model.updateProfile { best = FreeRecall.finish(g, profile: &$0) }
        newBest = best
        model.record(.gamePlayed)
        model.checkMilestones()
    }
}

// MARK: - 6. Mini story

struct MiniStoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var story: MiniStory?
    @State private var showEnglish = false
    @State private var answer: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let s = story {
                        Text(s.unitTitle).font(.caption.bold())
                        ForEach(Array(s.texts.enumerated()), id: \.offset) { i, t in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.display(t)).font(.title3)
                                    if showEnglish { Text("“\(s.englishes[i])”").font(.caption).foregroundStyle(Color(p.secondaryText)) }
                                }
                                Spacer()
                                SpeakerButton(text: VText(t))
                            }
                        }
                        Toggle("Show English", isOn: $showEnglish).accessibilityIdentifier("storyEnglish")
                        Divider()
                        Text(s.question.prompt).font(.headline)
                        ForEach(Array(s.question.options.enumerated()), id: \.offset) { i, o in
                            Button { if answer == nil { answer = i; let ok = i == s.question.answerIndex; model.sfx(ok ? .correct : .retry); model.haptic(ok) } } label: {
                                HStack {
                                    Text(o)
                                    Spacer()
                                    if answer != nil, i == s.question.answerIndex { Image(systemName: "checkmark.circle.fill").accessibilityLabel("right answer") }
                                    else if answer == i { Image(systemName: "xmark.circle.fill").accessibilityLabel("your answer") }
                                }
                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("story-\(i)")
                        }
                        if answer != nil {
                            Text(s.question.explanation).font(.subheadline)
                            Button("Another story") { load() }.buttonStyle(PrimaryButtonStyle())
                        }
                    } else {
                        Text("Stories appear once you've reached a unit with example sentences.")
                    }
                }
                .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(ThemedBackground())
            .navigationTitle("Mini story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if story == nil { load() } }
        }
    }

    private func load() {
        guard let prof = model.profile, let lib = model.library else { return }
        story = MiniStory.make(prof, library: lib, seed: playSeed())
        answer = nil; showEnglish = false
    }
}

// MARK: - 7 + 11. Word details: related words and a fresh start

struct WordRelatedRow: View {
    @EnvironmentObject var model: AppModel
    let itemId: String
    @State private var confirmReset = false
    var body: some View {
        if let prof = model.profile, let lib = model.library, let item = lib.item(itemId) {
            let rel = RelatedWords.ids(for: item, profile: prof, library: lib).compactMap { lib.item($0) }
            VStack(alignment: .leading, spacing: 4) {
                if !rel.isEmpty {
                    Text("Related: " + rel.map { "\(model.display($0.target)) (\($0.english))" }.joined(separator: ", ")).font(.caption)
                }
                if let k = prof.knowledge[itemId], WordReset.canReset(k) {
                    Button { confirmReset = true } label: { Label("Start this word fresh", systemImage: "arrow.counterclockwise") }
                        .font(.caption.bold())
                        .confirmationDialog("Start this word fresh?", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Start fresh") { model.updateProfile { WordReset.freshStart(itemId, profile: &$0, now: Date()) } }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This word keeps slipping. It will start again from the beginning, with short gaps. Your memory hook stays.")
                        }
                        .accessibilityIdentifier("freshStart-\(itemId)")
                }
            }
        }
    }
}

// MARK: - 5, 12, 13. Additions to the language page's Today card

struct TodayExtrasRows: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile {
            let y = YesterdayRecall.ids(prof, now: Date())
            if y.count >= 3 {
                Button { model.sheet = .yesterdayCheck(y) } label: {
                    Label("Yesterday's words: a quick check", systemImage: "sunrise.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("yesterdayCheck")
            }
            if let r = prof.settings.reason {
                Label(r.nudge, systemImage: r.icon).font(.caption)
            }
            if let c = prof.settings.cue {
                Label("Your plan: " + c.plan, systemImage: "calendar.badge.clock").font(.caption)
            }
        }
    }
}

// MARK: - 14, 15, 17, 19. My progress additions

struct ProgressExtrasSections: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile {
            Section {
                Label(LearningTips.tip(now: Date()), systemImage: "lightbulb.fill")
            } header: { Text("Tip of the day") }
            let race = SelfRace.compute(prof, now: Date())
            Section {
                HStack {
                    VStack { Text("\(race.thisWeek)").font(.title.bold()); Text("this week").font(.caption) }.frame(maxWidth: .infinity)
                    Image(systemName: race.ahead ? "arrow.up.right" : "arrow.down.right").accessibilityHidden(true)
                    VStack { Text("\(race.lastWeekSoFar)").font(.title.bold()); Text("same days last week").font(.caption) }.frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(race.thisWeek) minutes this week, \(race.lastWeekSoFar) on the same days last week")
                Text(race.ahead ? "You're ahead of last week. Nice!" : "A few minutes today and you'll catch last week.").font(.caption)
            } header: { Text("You vs last week (minutes)") }
            Section {
                HeatmapView(cells: ActivityHeatmap.cells(prof, now: Date()))
            } header: { Text("Last 12 weeks") } footer: { Text("Darker squares mean more minutes that day.") }
            SkillsSection(profile: prof)
        }
    }
}

struct HeatmapView: View {
    @Environment(\.palette) var p
    let cells: [HeatCell]
    var body: some View {
        let weeks = (cells.map(\.week).max() ?? 0) + 1
        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(cells.filter { $0.week == w }) { c in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(c.level == 0 ? Color(p.secondaryText).opacity(0.15) : Color(p.accent).opacity(0.25 + 0.19 * Double(c.level)))
                            .frame(width: 14, height: 14)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practised on \(cells.filter { $0.level > 0 }.count) of the last \(cells.count) days")
    }
}

struct SkillsSection: View {
    @Environment(\.palette) var p
    let profile: PlayerProfile
    var body: some View {
        let rows = SkillBreakdown.rows(profile).filter { $0.asked > 0 }
        if !rows.isEmpty {
            Section {
                ForEach(rows) { r in
                    HStack {
                        Text(r.title)
                        Spacer()
                        Text(r.percent.map { "\($0)%" } ?? "–").bold()
                        Text("(\(r.asked))").font(.caption)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let w = SkillBreakdown.weakest(profile) {
                    Text("Your weakest skill is \(w.title.lowercased()). A little extra practice there will help most.").font(.caption)
                }
            } header: { Text("Skills") } footer: { Text("First-try answers in quizzes and memory checks, by question type.") }
        }
    }
}

// MARK: - 9, 12, 13, 21, 22. Settings additions

struct LearningSettingsRows: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile {
            Toggle("Challenge mode (memory checks are all typed)", isOn: Binding(get: { prof.settings.challengeModeOn },
                                                                                  set: { v in model.updateProfile { $0.settings.challengeMode = v } }))
                .accessibilityIdentifier("challengeMode")
            Picker("Why I'm learning", selection: Binding(get: { prof.settings.learningReason ?? "" },
                                                          set: { v in model.updateProfile { $0.settings.learningReason = v.isEmpty ? nil : v } })) {
                Text("Not set").tag("")
                ForEach(LearningReason.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
            }
            .accessibilityIdentifier("learningReason")
            Picker("When I'll practise", selection: Binding(get: { prof.settings.practiceCue ?? "" },
                                                            set: { v in model.updateProfile { $0.settings.practiceCue = v.isEmpty ? nil : v } })) {
                Text("Not set").tag("")
                ForEach(PracticeCue.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
            }
            .accessibilityIdentifier("practiceCue")
        }
    }
}

struct ReminderPauseRows: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile, prof.settings.smartRemindersOn {
            if ReminderPause.isPaused(prof.settings, now: Date()), let until = prof.settings.remindersPausedUntil {
                HStack {
                    Text("Reminders paused until \(until.formatted(date: .abbreviated, time: .omitted))").font(.subheadline)
                    Spacer()
                    Button("Resume") { model.updateProfile { ReminderPause.resume(&$0) }; model.rescheduleSmartReminders() }
                }
            } else {
                Menu {
                    ForEach(ReminderPause.choices, id: \.self) { d in
                        Button("\(d) days") { model.updateProfile { ReminderPause.pause(days: d, profile: &$0, now: Date()) }; model.rescheduleSmartReminders() }
                    }
                } label: { Label("Pause reminders (holiday)", systemImage: "pause.circle") }
                .accessibilityIdentifier("pauseReminders")
            }
            NavigationLink("See upcoming reminders") { ReminderPreviewView() }
        }
    }
}

struct ReminderPreviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            let plan = model.previewSmartReminders()
            if plan.isEmpty {
                Text("No reminders are planned right now.")
            } else {
                ForEach(plan, id: \.date) { r in
                    VStack(alignment: .leading) {
                        Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.caption.bold())
                        Text(r.body)
                    }
                }
            }
            Section { Text("Reminders are made on this device from when you usually play. Fewer come after a break, and none after 8:30 pm.").font(.caption) }
        }
        .navigationTitle("Upcoming reminders")
    }
}

// MARK: - 23–26. Parents area additions

struct ParentProgressExtras: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile, let lib = model.library {
            Section {
                Chart(ParentHistory.days(prof, now: Date())) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Minutes", d.count)).foregroundStyle(Color(p.accent))
                }
                .frame(height: 120)
                .accessibilityLabel("Minutes played on each of the last 30 days")
                Picker("Weekly minutes target", selection: Binding(get: { model.save.parent.weeklyMinutesTarget ?? 0 },
                                                                   set: { v in model.updateParent { $0.weeklyMinutesTarget = v == 0 ? nil : v } })) {
                    Text("Off").tag(0)
                    ForEach(ParentWeekly.choices, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .accessibilityIdentifier("weeklyTarget")
                if let t = model.save.parent.weeklyMinutesTarget {
                    let m = ParentWeekly.minutesThisWeek(prof, now: Date())
                    ProgressView(value: Double(min(m, t)), total: Double(t)) { Text("\(m) of \(t) minutes this week") }
                }
                ShareLink(item: PracticeSheet.text(prof, library: lib, seed: UInt64(Date().timeIntervalSince1970 / 86400))) {
                    Label("Share a practice sheet (to print)", systemImage: "printer")
                }
                .accessibilityIdentifier("practiceSheet")
            } header: { Text("Last 30 days") } footer: {
                Text("The practice sheet is plain text with English prompts and the answers at the bottom, shared only where you choose.")
            }
            SkillsSection(profile: prof)
        }
    }
}

// MARK: - Quiz sheet for yesterday's words

struct YesterdaySheet: View {
    let ids: [String]
    var body: some View { KindQuizSheet(kind: .words(ids), title: "Yesterday's words", count: ids.count) }
}

struct ChoiceGameRouter: View {
    let game: String
    var body: some View {
        switch game {
        case "articles":
            ChoiceGameView(title: "Articles", intro: "Is it masculine or feminine? Pick the right word for \"the\".", counter: MetaEvent.articleDrill) { p, l, s in ArticleDrill.round(p, library: l, seed: s) }
        case "pictures":
            ChoiceGameView(title: "Picture match", intro: "Pick the picture that matches the word.", bigOptions: true, counter: MetaEvent.pictureMatch) { p, l, s in PictureMatch.round(p, library: l, seed: s) }
        case "odd":
            ChoiceGameView(title: "Odd one out", intro: "Three words belong together. Find the one that doesn't.", counter: MetaEvent.oddOneOut) { p, l, s in OddOneOut.round(p, library: l, seed: s) }
        case "chain":
            ChoiceGameView(title: "Word chain", intro: "Pick the word that starts with the last letter of the word shown.", counter: MetaEvent.wordChain) { p, l, s in WordChain.round(p, library: l, seed: s) }
        default:
            ChoiceGameView(title: "Quiz a grown-up", intro: "Hand the phone to a grown-up. Read each word out loud, and they pick what it means. Can they beat you?", counter: MetaEvent.familyQuiz) { p, l, s in FamilyQuiz.round(p, library: l, seed: s) }
        }
    }
}
