import SwiftUI
import Charts
import LQCore

private func playSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max / 2) }

// MARK: - 6. Lightning round

struct LightningView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var round: LightningRound?
    @State private var endsAt: Date?
    @State private var remaining = Int(LightningRound.seconds)
    @State private var finished = false
    @State private var newBest = false
    @State private var flash: Bool?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if finished, let r = round {
                    Image(systemName: "bolt.fill").font(.system(size: 54)).foregroundStyle(.yellow).accessibilityHidden(true)
                    Text("\(r.score)").font(.system(size: 64, weight: .heavy, design: .rounded)).accessibilityIdentifier("lightningScore")
                    Text(newBest ? "New best!" : "Best: \(model.profile.map { LightningRound.best($0) } ?? 0)").font(.title3.bold())
                    Text("\(r.answered) answered in \(Int(LightningRound.seconds)) seconds.").font(.subheadline)
                    Text("A fast game for fun. It doesn't change your review schedule.").font(.caption).foregroundStyle(Color(p.secondaryText)).multilineTextAlignment(.center)
                    Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                } else if endsAt == nil {
                    Image(systemName: "bolt.fill").font(.system(size: 54)).foregroundStyle(.yellow).accessibilityHidden(true)
                    Text("Lightning round").font(.title.bold())
                    Text("60 seconds. Pick the meaning of as many words as you can.").multilineTextAlignment(.center)
                    Text("Best: \(model.profile.map { LightningRound.best($0) } ?? 0)").font(.headline)
                    Button("Go!") { start() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("lightningGo")
                } else if let q = round?.current {
                    HStack {
                        Label("\(remaining)s", systemImage: "timer").font(.title3.monospacedDigit().bold())
                            .accessibilityLabel("\(remaining) seconds left")
                        Spacer()
                        Label("\(round?.score ?? 0)", systemImage: "bolt.fill").font(.title3.bold())
                            .accessibilityLabel("Score \(round?.score ?? 0)")
                    }
                    Text(model.display(q.word)).font(.largeTitle.bold())
                        .padding(8)
                        .background((flash.map { Color($0 ? p.success : p.retry).opacity(0.25) } ?? .clear), in: RoundedRectangle(cornerRadius: 12))
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                        Button { pick(i) } label: {
                            Text(o).font(.title3).frame(maxWidth: .infinity, minHeight: 54)
                                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                        .accessibilityIdentifier("lightning-\(i)")
                    }
                } else {
                    Text("Meet a few words in the village first.").multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            .background(ThemedBackground())
            .navigationTitle("Lightning round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onReceive(tick) { _ in
                guard let end = endsAt, !finished else { return }
                remaining = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
                if remaining == 0 { end_() }
            }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        round = LightningRound(profile: prof, library: lib, seed: playSeed())
        finished = false; newBest = false
        remaining = Int(LightningRound.seconds)
        endsAt = Date().addingTimeInterval(LightningRound.seconds)
    }

    private func pick(_ i: Int) {
        guard var r = round else { return }
        let ok = r.answer(choice: i)
        round = r
        flash = ok
        model.sfx(ok ? .correct : .retry)
        model.haptic(ok)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { flash = nil }
        if r.current == nil { end_() }
    }

    private func end_() {
        guard let r = round, !finished else { return }
        finished = true
        var best = false
        model.updateProfile { best = LightningRound.finish(r, profile: &$0) }
        newBest = best
        model.record(.gamePlayed)
        model.checkMilestones()
        UIAccessibility.post(notification: .announcement, argument: "Time's up. Score \(r.score)")
    }
}

// MARK: - Quiz sheets (Quick 3, listening check, look-alikes, bedtime review)

struct KindQuizSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let kind: RetentionQuizKind
    let title: String
    var count = RetentionQuiz.size
    var onFinish: ((QuizRecord) -> Void)? = nil
    var body: some View {
        NavigationStack {
            RetentionQuizView(kind: kind, count: count) { rec in
                if let r = rec { onFinish?(r) }
                dismiss()
            }
            .background(ThemedBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - 8, 10, 14. The language page's "today" card: daily goal, Quick 3, bedtime review

struct TodayGoalCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if let goal = DailyGoal.goal(prof.settings) {
                        let f = DailyGoal.progress(minutesToday: model.minutesToday, goal: goal)
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().stroke(Color(p.secondaryText).opacity(0.25), lineWidth: 7)
                                Circle().trim(from: 0, to: f).stroke(Color(p.accent), style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                                if f >= 1 { Image(systemName: "checkmark").font(.headline) }
                            }
                            .frame(width: 44, height: 44)
                            VStack(alignment: .leading) {
                                Text(f >= 1 ? "Daily goal done!" : "Daily goal: \(goal) minutes").font(.headline)
                                Text("\(Int(model.minutesToday.rounded())) of \(goal) minutes today").font(.caption)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    HStack(spacing: 10) {
                        Button { model.sheet = .quickThree } label: {
                            Label("Busy day? Quick 3", systemImage: "hare.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("quickThree")
                        if BedtimeReview.isAvailable(prof, now: Date()) {
                            Button { model.sheet = .bedtimeReview(BedtimeReview.ids(prof, now: Date())) } label: {
                                Label("Bedtime review", systemImage: "moon.zzz.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("bedtimeReview")
                        }
                    }
                    if BedtimeReview.isAvailable(prof, now: Date()) {
                        Text("A last look at today's words before sleep helps them stick.").font(.caption)
                    }
                    SentenceOfTheDayRow()
                }
            }
        }
    }
}

// MARK: - 9. Sentence of the day (under the word of the day)

struct SentenceOfTheDayRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile, let lib = model.library, let s = SentenceOfTheDay.make(prof, library: lib, now: Date()) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.display(s.text)).font(.subheadline.bold())
                    Text("“\(s.english)”").font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                Spacer()
                SpeakerButton(text: VText(s.text), label: "Hear the sentence")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sentenceOfTheDay")
        }
    }
}

// MARK: - 3. Forecast, day by day

struct ForecastChart: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile {
            let days = DailyForecast.days(prof, now: Date())
            Chart(days) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Words", d.count))
                    .foregroundStyle(Color(p.accent))
                    .accessibilityLabel(d.date.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue("\(d.count) words")
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 110)
        }
    }
}

// MARK: - 4. Unit mastery rings

struct UnitMasterySection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile, let lib = model.library {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(UnitMastery.rows(prof, library: lib)) { u in
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().stroke(Color(p.secondaryText).opacity(0.25), lineWidth: 8)
                                    Circle().trim(from: 0, to: u.fraction).stroke(Color(p.accent), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                                    Text("\(Int((u.fraction * 100).rounded()))%").font(.caption.bold())
                                }
                                .frame(width: 60, height: 60)
                                Text("Unit \(u.order)").font(.caption.bold())
                                Text("\(u.strong)/\(u.total)").font(.caption2)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Unit \(u.order), \(u.title): \(u.strong) of \(u.total) words understood")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text("Unit mastery") } footer: {
                Text("The share of each unit's words you understand well, measured by spaced reviews.")
            }
        }
    }
}

// MARK: - 5. Look-alike words

struct LookAlikesSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile, let lib = model.library {
            let pairs = LookAlikes.pairs(prof, library: lib)
            if !pairs.isEmpty {
                Section {
                    ForEach(pairs) { pr in
                        if let a = lib.item(pr.a), let b = lib.item(pr.b) {
                            HStack {
                                VStack(alignment: .leading) { Text(model.display(a.target)).bold(); Text(a.english).font(.caption) }
                                Spacer()
                                Image(systemName: "arrow.left.arrow.right").accessibilityHidden(true)
                                Spacer()
                                VStack(alignment: .trailing) { Text(model.display(b.target)).bold(); Text(b.english).font(.caption) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Button("Practise these side by side") { model.sheet = .lookAlikes(LookAlikes.drillIds(pairs)) }
                        .accessibilityIdentifier("lookAlikeDrill")
                } header: { Text("Look-alike words") } footer: {
                    Text("Words spelled almost the same are easy to mix up. Practising them together helps tell them apart.")
                }
            }
        }
    }
}

// MARK: - 15. Weekly question goal, 20. Today's report

struct WeeklyQuestionsSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    var body: some View {
        if let prof = model.profile {
            let n = WeeklyQuestions.answered(prof, now: Date())
            Section {
                ProgressView(value: Double(min(n, WeeklyQuestions.goal)), total: Double(WeeklyQuestions.goal)) {
                    Text(n >= WeeklyQuestions.goal ? "Weekly goal done: \(n) questions!" : "\(n) of \(WeeklyQuestions.goal) quiz questions this week")
                }
                .tint(Color(p.accent))
                NavigationLink("Today's report") { TodayReportView() }.accessibilityIdentifier("todayReportLink")
            } header: { Text("This week") }
        }
    }
}

struct TodayReportView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            if let prof = model.profile {
                let r = TodayReport.compute(prof, now: Date())
                Section {
                    LabeledContent("Minutes played", value: "\(r.minutes)")
                    LabeledContent("Activities", value: "\(r.activities)")
                    LabeledContent("Words practised", value: "\(r.wordsPractised)")
                    LabeledContent("Quizzes", value: "\(r.quizzes)")
                    LabeledContent("Questions", value: "\(r.questions)")
                    LabeledContent("Right on the first try", value: r.accuracy.map { "\($0)%" } ?? "–")
                }
                Section {
                    Text(r.wordsPractised == 0 ? "Nothing yet today. Even 3 minutes helps."
                         : r.questions == 0 ? "Nice practice! A quick memory check would lock today's words in."
                         : "Great work today. Come back tomorrow: spacing it out is what makes words stick.")
                }
            }
        }
        .navigationTitle("Today")
    }
}

// MARK: - 11 + 19. Word Library details: example sentence and "Review soon"

struct WordExtrasRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let itemId: String
    @State private var pinned = false
    var body: some View {
        if let prof = model.profile, let lib = model.library, let item = lib.item(itemId) {
            VStack(alignment: .leading, spacing: 6) {
                if let s = ExampleSentence.sentence(for: item, profile: prof, library: lib) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.display(s.text)).font(.subheadline)
                            Text("“\(s.english)”").font(.caption).foregroundStyle(Color(p.secondaryText))
                        }
                        Spacer()
                        SpeakerButton(text: VText(s.text), label: "Hear the example")
                    }
                    .accessibilityElement(children: .combine)
                }
                if pinned || ReviewSoon.isDue(itemId, profile: prof, now: Date()) {
                    Label("In your next review", systemImage: "checkmark.circle").font(.caption)
                } else {
                    Button { model.updateProfile { ReviewSoon.pin(itemId, profile: &$0, now: Date()) }; pinned = true } label: {
                        Label("Review soon", systemImage: "clock.arrow.circlepath")
                    }
                    .font(.caption.bold())
                    .accessibilityHint("Adds this word to your next review. It doesn't count as a mistake.")
                    .accessibilityIdentifier("reviewSoon-\(itemId)")
                }
            }
        }
    }
}

// MARK: - 17, 18, 25. Parents area: bedtime, word list, tricky words

struct ParentBedtimeRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Bedtime (no play after)", selection: Binding(
            get: { model.save.parent.bedtimeHour ?? 0 },
            set: { v in model.updateParent { $0.bedtimeHour = v == 0 ? nil : v } })) {
            Text("Off").tag(0)
            ForEach(Bedtime.choices, id: \.self) { h in
                Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())?.formatted(date: .omitted, time: .shortened) ?? "\(h):00").tag(h)
            }
        }
        .accessibilityIdentifier("bedtimeHour")
    }
}

struct ParentWordsSection: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile, let lib = model.library, !prof.knowledge.isEmpty {
            Section {
                let tricky = TrickyWords.ids(prof).prefix(5).compactMap { lib.item($0) }
                if tricky.isEmpty {
                    Text("No tricky words right now.")
                } else {
                    ForEach(tricky, id: \.id) { item in
                        HStack { Text(model.display(item.target)).bold(); Text("= \(item.english)").font(.caption); Spacer(); SpeakerButton(text: item.target) }
                    }
                }
                ShareLink(item: WordListExport.text(prof, library: lib)) {
                    Label("Share the word list", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareWordList")
            } header: { Text("Words to practise together") } footer: {
                Text("The words your explorer keeps missing, to practise together. The word list is plain text, shared only where you choose.")
            }
        }
    }
}

// Sheets that count a finished drill (look-alikes) or the evening review.
struct LookAlikeSheet: View {
    @EnvironmentObject var model: AppModel
    let ids: [String]
    var body: some View {
        KindQuizSheet(kind: .words(ids), title: "Look-alike words", count: min(10, ids.count)) { _ in
            model.updateProfile { LookAlikes.markDrillDone(&$0) }
            model.checkMilestones()
        }
    }
}

struct BedtimeSheet: View {
    @EnvironmentObject var model: AppModel
    let ids: [String]
    var body: some View {
        KindQuizSheet(kind: .words(ids), title: "Bedtime review", count: ids.count) { _ in
            model.updateProfile { BedtimeReview.markDone(&$0, now: Date()) }
            model.checkMilestones()
        }
    }
}
