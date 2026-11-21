import SwiftUI
import Charts
import LQCore

private func playSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max / 2) }

// MARK: - 1 + 8. Quiz sheets: tricky-word drill, practice missed words

struct WordsQuizSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let kind: RetentionQuizKind
    var title = "Practice"
    var body: some View {
        NavigationStack {
            RetentionQuizView(kind: kind, count: RetentionQuiz.size) { _ in dismiss() }
                .background(ThemedBackground())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - 2. "Almost!": what was different

struct TypoDiffView: View {
    @Environment(\.palette) var p
    let typed: String
    let expected: String
    var body: some View {
        let marks = TypoDiff.marks(typed: typed, expected: expected)
        if !marks.isEmpty {
            VStack(spacing: 4) {
                Text("You typed").font(.caption)
                marks.reduce(Text("")) { acc, m in
                    acc + Text(String(m.char))
                        .foregroundColor(m.ok ? Color(p.text) : Color(p.retry))
                        .underline(!m.ok)
                        .bold(!m.ok)
                }
                .font(.title3.monospaced())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You typed \(typed). The underlined letters were different.")
        }
    }
}

// MARK: - 4. Sentence dictation

struct DictationView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: DictationGame?
    @State private var typed = ""
    @State private var feedback: (ok: Bool, text: String, english: String, typed: String)?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let f = feedback {
                        Image(systemName: f.ok ? "checkmark.circle.fill" : "lightbulb.fill").font(.system(size: 50))
                            .foregroundStyle(Color(f.ok ? p.success : p.retry)).accessibilityHidden(true)
                        Text(f.ok ? "Perfect hearing!" : "Here's the sentence").font(.title2.bold())
                        Text(f.text).font(.title3.bold()).multilineTextAlignment(.center)
                        Text("“\(f.english)”").font(.subheadline).multilineTextAlignment(.center)
                        if !f.ok { TypoDiffView(typed: f.typed, expected: f.text) }
                        Button(game?.isFinished == true ? "See my score" : "Next sentence") { next() }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("dictNext")
                    } else if let g = game, let s = g.current {
                        Text("Sentence \(g.index + 1) of \(g.sentences.count)").font(.caption)
                        Text("Listen, then type the whole sentence.").font(.headline)
                        HStack(spacing: 16) {
                            SpeakerButton(text: VText(s.text), label: "Play the sentence", big: true)
                            SlowSpeakerButton(text: VText(s.text))
                        }
                        TextField("Type what you hear", text: $typed, axis: .vertical)
                            .textFieldStyle(.roundedBorder).font(.title3)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("dictField")
                        AccentKeyBar(text: $typed)
                        Text("Punctuation and capitals don't matter.").font(.caption).foregroundStyle(Color(p.secondaryText))
                        Button("Check") { submit() }.buttonStyle(PrimaryButtonStyle())
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("dictCheck")
                    } else if let g = game, g.isFinished, !g.sentences.isEmpty {
                        Text("\(g.correct) of \(g.sentences.count)").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        Text(g.correct == g.sentences.count ? "Every sentence! Great ears." : "Sentences are hard. Each try trains your ear.")
                            .multilineTextAlignment(.center)
                        Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    } else if game != nil {
                        Text("Talk to someone in the village first, then their sentences show up here.").multilineTextAlignment(.center)
                    }
                }
                .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(ThemedBackground())
            .navigationTitle("Sentence dictation")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        game = DictationGame(profile: prof, library: lib, seed: playSeed())
        typed = ""; feedback = nil; saved = false
        if let s = game?.current { model.autoSay(VText(s.text)) }
    }

    private func submit() {
        guard var g = game, let s = g.current, let lib = model.library, let prof = model.profile else { return }
        let v = g.submit(typed, variant: prof.variant(for: lib), context: lib.checkContext)
        game = g
        model.sfx(v.isCorrect ? .correct : .retry)
        feedback = (v.isCorrect, s.text, s.english, typed)
        UIAccessibility.post(notification: .announcement, argument: v.isCorrect ? "Correct" : "The sentence was \(s.text)")
    }

    private func next() {
        feedback = nil; typed = ""
        guard let g = game else { return }
        if g.isFinished {
            if !saved { saved = true; model.updateProfile { DictationGame.finish(g, profile: &$0) }; model.record(.gamePlayed); model.checkMilestones() }
        } else if let s = g.current { model.autoSay(VText(s.text)) }
    }
}

// MARK: - 7. Share a progress card (Parents area)

struct ProgressCardImage: View {
    let name: String
    let language: String
    let streak: Int
    let words: Int
    let lockedIn: Int
    let level: Int
    var body: some View {
        VStack(spacing: 10) {
            Text("Language Quest").font(.title2.bold())
            Text(name).font(.title.bold())
            Text("Learning \(language)").font(.headline)
            HStack(spacing: 20) {
                statBox("\(streak)", "day streak")
                statBox("\(words)", "words met")
                statBox("\(lockedIn)", "locked in")
                statBox("\(level)", "level")
            }
        }
        .padding(28)
        .frame(width: 600)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.27), Color(red: 0.2, green: 0.36, blue: 0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(.white)
    }
    private func statBox(_ v: String, _ l: String) -> some View {
        VStack { Text(v).font(.largeTitle.bold()); Text(l).font(.caption) }
    }
}

struct ParentShareCardSection: View {
    @EnvironmentObject var model: AppModel
    @State private var image: Image?

    var body: some View {
        Section {
            if let img = image {
                img.resizable().scaledToFit().frame(maxHeight: 160).accessibilityLabel("Progress card preview")
                ShareLink(item: img, preview: SharePreview("Language Quest progress", image: img)) {
                    Label("Share the progress card", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareCard")
            } else {
                Button("Make a progress card") { render() }.accessibilityIdentifier("makeCard")
            }
        } header: { Text("Progress card") } footer: {
            Text("A picture of the explorer's nickname, streak and words. It's only shared if you tap Share and choose where it goes.")
        }
    }

    @MainActor private func render() {
        guard let prof = model.profile else { return }
        let card = ProgressCardImage(name: prof.nickname.isEmpty ? "Explorer" : prof.nickname, language: model.languageName,
                                     streak: Streak.current(prof, now: Date()), words: prof.knowledge.count,
                                     lockedIn: prof.knowledge.values.filter { RecallModel.isLockedIn($0, now: Date()) }.count,
                                     level: ExplorerLevel.level(forXP: prof.rewards.xp))
        let r = ImageRenderer(content: card)
        r.scale = 2
        if let ui = r.uiImage { image = Image(uiImage: ui) }
    }
}

// MARK: - 9. Daily time limit

struct TimeLimitOverlay: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @State private var asking = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 18) {
                if asking {
                    if let record = ParentPINStore.load() {
                        PINGateView(record: record) { allow() }
                    } else {
                        ParentGateView { allow() }
                    }
                    Button("Back") { asking = false }.foregroundStyle(.white)
                } else {
                    Image(systemName: "moon.stars.fill").font(.system(size: 60)).foregroundStyle(.yellow).accessibilityHidden(true)
                    Text("That's today's playtime!").font(.title.bold()).foregroundStyle(.white)
                    Text("Great work. Your words will be waiting tomorrow, and resting helps them stick.")
                        .multilineTextAlignment(.center).foregroundStyle(.white)
                    Button("A parent can allow more time") { asking = true }
                        .buttonStyle(.bordered).tint(.white)
                        .accessibilityIdentifier("limitParent")
                }
            }
            .padding(30)
            .frame(maxWidth: 520)
            .background(Color(p.surface).opacity(asking ? 1 : 0), in: RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityAddTraits(.isModal)
    }
    private func allow() { model.updateProfile { TimeLimit.allowMoreToday(profile: &$0, now: Date()) }; model.objectWillChange.send() }
}

struct ParentTimeLimitRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Daily playtime limit", selection: Binding(
            get: { model.save.parent.dailyLimitMinutes ?? 0 },
            set: { v in model.updateParent { $0.dailyLimitMinutes = v == 0 ? nil : v } })) {
            Text("No limit").tag(0)
            ForEach(TimeLimit.choices, id: \.self) { Text("\($0) minutes").tag($0) }
        }
        .accessibilityIdentifier("dailyLimit")
    }
}

// MARK: - 10, 12, 13, 18. My progress additions

struct WordsThisWeekSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile, let lib = model.library {
            let ids = WordsThisWeek.ids(prof, now: Date())
            if !ids.isEmpty {
                Section("New this week (\(ids.count))") {
                    ForEach(ids.prefix(12), id: \.self) { id in
                        if let item = lib.item(id) {
                            HStack {
                                Text(model.display(item.target)).font(.headline)
                                Text(item.english).font(.caption).foregroundStyle(Color(p.secondaryText))
                                Spacer()
                                SpeakerButton(text: item.target)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TrickyWordsSection: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile {
            let n = TrickyWords.ids(prof).count
            Section {
                if n == 0 {
                    Text("No tricky words right now. Words you keep missing will show up here.")
                } else {
                    Button("Drill my \(n) tricky word\(n == 1 ? "" : "s")") { model.sheet = .tricky }
                        .accessibilityIdentifier("trickyDrill")
                }
            } header: { Text("Tricky words") } footer: {
                Text("A word becomes tricky after 3 slips, or after being missed in 2 quizzes. Extra practice with feedback is the best fix.")
            }
        }
    }
}

struct QuizDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let record: QuizRecord
    var body: some View {
        List {
            Section {
                Text("\(record.correct) of \(record.total) right").font(.title2.bold())
                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            }
            if record.missed.isEmpty {
                Section { Label("Nothing missed. Perfect!", systemImage: "star.fill") }
            } else {
                Section("Missed") {
                    ForEach(record.missed, id: \.self) { id in
                        if let item = model.library?.item(id) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(model.display(item.target)).font(.headline)
                                    Text(item.english).font(.caption).foregroundStyle(Color(p.secondaryText))
                                }
                                Spacer()
                                SpeakerButton(text: item.target)
                            }
                        }
                    }
                    Button("Practice these now") { model.sheet = .practiceWords(record.missed) }
                }
            }
        }
        .navigationTitle(record.isLesson ? "Lesson quiz" : "Memory check")
    }
}

struct MemoryScienceView: View {
    @Environment(\.palette) var p
    var body: some View {
        List {
            Section {
                Text("Memories fade over time unless you use them. Each time you pull a word out of memory, especially just as it starts to fade, it fades more slowly afterwards.")
                Chart {
                    let curves = RecallModel.exampleCurves()
                    ForEach(curves.indices, id: \.self) { ci in
                        ForEach(curves[ci].points) { pt in
                            LineMark(x: .value("Days", pt.day), y: .value("Remembered", pt.recall * 100))
                                .foregroundStyle(by: .value("When", curves[ci].label))
                        }
                    }
                }
                .chartYAxisLabel("% remembered").chartXAxisLabel("days without practice")
                .frame(height: 220)
                .accessibilityLabel("Three curves: the more times a word is reviewed, the more slowly it is forgotten.")
            } header: { Text("How memory works") }
            Section("What Language Quest does about it") {
                Label("Quizzes ask you to recall, not just reread: that's what makes words stick.", systemImage: "brain.head.profile")
                Label("Reviews come back just as a word starts to fade.", systemImage: "clock.arrow.circlepath")
                Label("Missed words come back sooner, with the answer right away.", systemImage: "arrow.uturn.backward")
                Label("A little every day beats a lot once a week.", systemImage: "calendar")
            }
        }
        .navigationTitle("How memory works")
    }
}

struct PracticeTimesSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile, let s = PracticeTimes.summary(prof) {
            Section {
                Chart(PracticeTimes.byHour(prof).filter { (6...22).contains($0.hour) }) { h in
                    BarMark(x: .value("Hour", h.hour), y: .value("Sessions", h.sessions)).foregroundStyle(Color(p.accent))
                }
                .chartXScale(domain: 6...22)
                .frame(height: 120)
                .accessibilityLabel(s)
                Text(s).font(.caption)
            } header: { Text("When you practice") }
        }
    }
}

/// 14. A word's memory curve for the next two weeks (Word Library details).
struct WordCurveView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let itemId: String
    var body: some View {
        if let k = model.profile?.knowledge[itemId], let now = Optional(Date()), let r = RecallModel.probability(k, now: now) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memory now: \(Int((r * 100).rounded()))%" + (RecallModel.isLockedIn(k, now: now) ? " · locked in" : "")).font(.caption.bold())
                Chart(RecallModel.curve(k, now: now)) { pt in
                    AreaMark(x: .value("Days", pt.day), y: .value("%", pt.recall * 100)).foregroundStyle(Color(p.accent).opacity(0.35))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 70)
                .accessibilityLabel("If you don't practice, memory of this word goes from \(Int(r * 100)) percent to \(Int((RecallModel.curve(k, now: now).last?.recall ?? 0) * 100)) percent in two weeks.")
            }
        }
    }
}

// MARK: - 16. Reminder days off

struct ReminderDaysOffRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if model.profile?.settings.smartRemindersOn == true {
            let off = model.profile?.settings.reminderDaysOff ?? []
            VStack(alignment: .leading, spacing: 4) {
                Text("Days off (no reminders)").font(.subheadline)
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { wd in
                        let isOff = off.contains(wd)
                        Button(String(Calendar.current.shortWeekdaySymbols[wd - 1].prefix(2))) {
                            model.updateProfile { p in
                                var d = p.settings.reminderDaysOff ?? []
                                if isOff { d.removeAll { $0 == wd } } else if d.count < 6 { d.append(wd) }
                                p.settings.reminderDaysOff = d
                            }
                            model.rescheduleSmartReminders()
                        }
                        .buttonStyle(.bordered)
                        .tint(isOff ? Color.gray : Color.accentColor)
                        .accessibilityLabel("\(Calendar.current.weekdaySymbols[wd - 1]): \(isOff ? "day off" : "reminders on")")
                    }
                }
            }
        }
    }
}

// MARK: - 6. Path chest, 20. tip, 21. what's new

struct PathChestButton: View {
    @EnvironmentObject var model: AppModel
    let steps: [PathStep]
    var body: some View {
        if let prof = model.profile, TodayPath.canOpenChest(steps, profile: prof, now: Date()) {
            Button {
                var xp = 0
                model.updateProfile { xp = TodayPath.openChest(steps, profile: &$0, now: Date()) }
                model.sfx(.coin)
                model.celebrate(AppModel.Celebration(icon: "gift.fill", title: "Path complete!", detail: "+\(xp) XP. See you tomorrow!"))
                model.checkMilestones()
            } label: { Label("Open today's chest", systemImage: "gift.fill").frame(maxWidth: .infinity) }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("pathChest")
        }
    }
}

struct TipCard: View {
    @EnvironmentObject var model: AppModel
    let id: String
    let icon: String
    let text: String
    var body: some View {
        if let prof = model.profile, !OnceMessages.tipSeen(id, in: prof) {
            Card {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.title3).accessibilityHidden(true)
                    Text(text).font(.subheadline)
                    Spacer()
                    Button("Got it") { model.updateProfile { OnceMessages.markTip(id, profile: &$0) } }
                        .font(.subheadline.bold())
                        .accessibilityIdentifier("tip-\(id)")
                }
            }
        }
    }
}

struct WhatsNewCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile, OnceMessages.shouldShowWhatsNew(prof) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label("New in Language Quest \(OnceMessages.currentVersion)", systemImage: "sparkles").font(.headline)
                    ForEach(OnceMessages.whatsNew, id: \.self) { Text("• \($0)").font(.subheadline) }
                    Button("Got it") { model.updateProfile { OnceMessages.markWhatsNew(&$0) } }
                        .font(.subheadline.bold())
                        .accessibilityIdentifier("whatsNewOK")
                }
            }
        }
    }
}
