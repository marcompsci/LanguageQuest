import SwiftUI
import StoreKit
import Charts
import LQCore

private func playSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max / 2) }

// MARK: - The 5-question quiz (end of every lesson, and the quick memory check)

struct RetentionQuizView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let kind: RetentionQuizKind
    var count: Int = RetentionQuiz.size
    var onDone: (QuizRecord?) -> Void
    @State private var hintShown: String?

    @State private var quiz: RetentionQuiz?
    @State private var typed = ""
    @State private var feedback: (ok: Bool, question: RetentionQuestion)?
    @State private var record: QuizRecord?
    @FocusState private var focused: Bool
    // v1.3: answer timing, "I guessed", combos.
    @State private var questionStart = Date()
    @State private var guessed = false
    @State private var pending: (q: RetentionQuestion, ok: Bool, hinted: Bool, seconds: Double)?
    @State private var combo = ComboCounter()
    @State private var comboHit: Int?
    @State private var showLookBack = false
    @State private var startKnowledge: [String: ItemKnowledge] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let rec = record {
                    results(rec)
                } else if let f = feedback {
                    feedbackView(f.ok, f.question)
                } else if let q = quiz, let cur = q.current {
                    header(q)
                    question(cur)
                } else if quiz != nil {
                    ProgressView().onAppear { finish() }
                }
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if quiz == nil { start() } }
    }

    // MARK: Pieces

    private func header(_ q: RetentionQuiz) -> some View {
        VStack(spacing: 8) {
            if q.isRelearning {
                Label("Let's lock in the one you missed", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline).foregroundStyle(Color(p.accent))
            } else {
                Text(kindTitle).font(.headline)
                HStack(spacing: 6) {
                    ForEach(0..<q.total, id: \.self) { i in
                        Capsule().fill(i < q.index ? Color(p.accent) : Color(p.secondaryText).opacity(0.3)).frame(height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Question \(q.index + 1) of \(q.total)")
            }
        }
    }

    private var isLesson: Bool { if case .lesson = kind { return true }; return false }

    private var kindTitle: String {
        let n = quiz?.total ?? count
        switch kind {
        case .lesson: return "Lesson quiz: \(n) questions"
        case .memoryCheck: return "Memory check: \(n) questions"
        case .tricky: return "Tricky words: \(n) questions"
        case .words: return "Practice: \(n) questions"
        case .listening: return "Listening check: \(n) questions"
        case .quick: return "Quick \(n)"
        }
    }

    @ViewBuilder
    private func question(_ q: RetentionQuestion) -> some View {
        if let pic = model.library?.item(q.itemId)?.picture, q.kind == .meaning || q.kind == .listen {
            Text(pic).font(.system(size: 56)).accessibilityHidden(true)   // a picture cue helps memory (dual coding)
        }
        if let hook = model.profile.flatMap({ WordNotes.note(q.itemId, in: $0) }), q.kind != .typeIt && q.kind != .pickWord {
            Label("Your hook: \(hook)", systemImage: "link").font(.caption).lineLimit(2)
        }
        Text(q.reason).font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(p.surface), in: Capsule())
            .accessibilityLabel("Why this word: \(q.reason)")
        switch q.kind {
        case .meaning:
            Text("What does this mean?").font(.headline)
            HStack { Text(model.display(q.word)).font(.largeTitle.bold()); SpeakerButton(text: q.word) }
            choices(q)
        case .listen:
            Text("Listen. What does it mean?").font(.headline)
            HStack(spacing: 16) {
                SpeakerButton(text: q.word, label: "Play the word", big: true)
                SlowSpeakerButton(text: q.word)
            }
            .onAppear { model.autoSay(q.word) }
            choices(q)
        case .pickWord:
            Text("How do you say this?").font(.headline)
            Text("“\(q.meaning)”").font(.title.bold()).multilineTextAlignment(.center)
            choices(q)
        case .cloze:
            Text("Which word fills the blank?").font(.headline)
            Text(q.context ?? "").font(.title2.bold()).multilineTextAlignment(.center)
            if let e = q.contextEnglish { Text("“\(e)”").font(.subheadline).multilineTextAlignment(.center) }
            choices(q)
        case .typeIt:
            Text("Type it from memory").font(.headline)
            Text("“\(q.meaning)”").font(.title.bold()).multilineTextAlignment(.center)
            Text("Pulling a word out of memory is what makes it stick, even when it's hard.")
                .font(.caption).foregroundStyle(Color(p.secondaryText)).multilineTextAlignment(.center)
            TextField("Type the word", text: $typed)
                .textFieldStyle(.roundedBorder).font(.title3)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focused)
                .onSubmit { submitTyped(q) }
                .accessibilityIdentifier("quizTyped")
            AccentKeyBar(text: $typed)
            if let h = hintShown { Text(h).font(.title3.monospaced()).accessibilityLabel("Starts with \(h.prefix(1))") }
            HStack {
                Button("Hint") {
                    guard var qz = quiz, let lib = model.library, let prof = model.profile else { return }
                    qz.useHint(); quiz = qz
                    hintShown = RetentionQuiz.firstLetterHint(q, variant: prof.variant(for: lib))
                }
                .buttonStyle(.bordered).disabled(hintShown != nil)
                .accessibilityIdentifier("quizHint")
                Button("I don't know") { typed = ""; submitTyped(q, giveUp: true) }.buttonStyle(.bordered)
                    .accessibilityIdentifier("quizDontKnow")
                Button("Check") { submitTyped(q) }.buttonStyle(PrimaryButtonStyle())
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("quizCheck")
            }
        }
    }

    private func choices(_ q: RetentionQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                Button { answer(q, choice: i) } label: {
                    Text(q.optionTexts.map { model.display($0[i]) } ?? o).font(.title3)
                        .frame(maxWidth: .infinity, minHeight: model.profile?.settings.bigButtonsOn == true ? 76 : 54).padding(.horizontal, 8)
                        .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(p.accent).opacity(0.5)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])   // iPad keyboards: 1–4
                .accessibilityIdentifier("rq-option-\(i)")
            }
        }
    }

    private func feedbackView(_ ok: Bool, _ q: RetentionQuestion) -> some View {
        VStack(spacing: 14) {
            Image(systemName: ok ? "checkmark.circle.fill" : "lightbulb.fill").font(.system(size: 54))
                .foregroundStyle(Color(ok ? p.success : p.retry)).accessibilityHidden(true)
            Text(ok ? "Yes!" : "Here's the answer").font(.title2.bold())
            // Immediate corrective feedback: the word, its meaning and its sound, right after the try.
            HStack {
                VStack(alignment: .leading) {
                    Text(model.display(q.word)).font(.title.bold())
                    Text(q.meaning).font(.title3)
                }
                Spacer()
                SpeakerButton(text: q.word)
            }
            .padding(14)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
            if !ok { Text("It'll come back at the end, and again soon in your reviews.").font(.subheadline).multilineTextAlignment(.center) }
            if ok, let t = RetentionQuiz.nextReviewText(model.profile.flatMap { RetentionQuiz.nextReviewDays(q.itemId, profile: $0, now: Date()) }) {
                Label(t, systemImage: "calendar").font(.subheadline)
            }
            if !ok, q.kind == .typeIt, let t = quiz?.lastTyped, !t.isEmpty, let lib = model.library, let prof = model.profile {
                if case .almost? = quiz?.lastVerdict { Text("Almost! Just a small slip.").font(.headline) }
                TypoDiffView(typed: t, expected: q.word.text(for: prof.variant(for: lib)))
            }
            if let c = comboHit { Label("\(c) in a row!", systemImage: "flame.fill").font(.headline).foregroundStyle(Color(p.accent)) }
            if ok, pending != nil {
                Toggle("I guessed", isOn: $guessed)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("rq-guessed")
                    .accessibilityHint("A guess still counts in your score, but the word comes back sooner.")
                if guessed { Text("Thanks for being honest. It still counts, and the word comes back sooner.").font(.caption).multilineTextAlignment(.center) }
            }
            // v1.4: after a miss, the word in a sentence (unless the question already showed one).
            if !ok, q.context == nil, let lib = model.library, let prof = model.profile, let item = lib.item(q.itemId),
               let ex = ExampleSentence.sentence(for: item, profile: prof, library: lib) {
                VStack(spacing: 2) {
                    Text(model.display(ex.text)).font(.subheadline.italic())
                    Text("“\(ex.english)”").font(.caption)
                }
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("rq-example")
            }
            if !ok { MemoryHookEditor(itemId: q.itemId) }
            Button("Next") { flushPending(); feedback = nil; typed = ""; questionStart = Date(); if quiz?.isFinished == true { finish() } }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("rq-next")
        }
        .onDisappear { flushPending() }
        .onAppear {
            // v1.3: after a listening miss, replay the word slowly.
            if !ok { if q.kind == .listen { model.autoSay(q.word, slow: true) } else { model.autoSay(q.word) } }
            UIAccessibility.post(notification: .announcement, argument: ok ? "Correct" : "The answer is \(model.text(q.word)), \(q.meaning)")
        }
    }

    private func results(_ rec: QuizRecord) -> some View {
        VStack(spacing: 14) {
            Text("\(rec.correct) of \(rec.total)").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .accessibilityIdentifier("rq-score")
            Text(rec.correct == rec.total ? "Perfect! These words are getting locked in."
                 : rec.correct >= rec.total - 1 ? "Great memory work!" : "Good effort. Misses now mean better memory later.")
                .font(.title3).multilineTextAlignment(.center)
            if let p0 = model.profile {
                Label(Streak.message(p0, now: Date()), systemImage: "flame.fill").font(.subheadline)
                let r = RetentionReport.make(p0, now: Date())
                if let avg = r.averageLast10 { Text("Your last \(min(10, r.lessonQuizzes + r.memoryChecks)) quizzes: \(avg)% on average").font(.caption) }
            }
            if !rec.missed.isEmpty, !isLesson {
                Button("Practice the \(rec.missed.count) I missed") { model.sheet = .practiceWords(rec.missed) }
                    .buttonStyle(.bordered).accessibilityIdentifier("rq-practiceMissed")
            }
            if let rows = quiz?.reviewRows, !rows.isEmpty {
                DisclosureGroup("Look back at your answers", isExpanded: $showLookBack) {
                    ForEach(rows) { r in
                        HStack {
                            Image(systemName: r.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(Color(r.correct ? p.success : p.retry))
                                .accessibilityLabel(r.correct ? "right" : "missed")
                            VStack(alignment: .leading) {
                                Text(model.display(r.word)).font(.headline)
                                Text(r.meaning + (r.hinted ? " · hint used" : "")).font(.caption)
                            }
                            Spacer()
                            SpeakerButton(text: r.word)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("rq-lookBack")
            }
            Button("Continue") { onDone(rec) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("rq-continue")
        }
    }

    // MARK: Actions

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        let q = RetentionQuiz(kind: kind, profile: prof, library: lib, now: Date(), seed: playSeed(), count: count)
        if q.questions.isEmpty { onDone(nil); return }
        quiz = q
        questionStart = Date()
        startKnowledge = prof.knowledge
    }

    private func answer(_ q: RetentionQuestion, choice: Int) {
        guard var qz = quiz, let lib = model.library, let prof = model.profile else { return }
        let first = !qz.isRelearning
        let ok = qz.answer(choice: choice, variant: prof.variant(for: lib), context: lib.checkContext)
        quiz = qz
        after(q, ok: ok, first: first)
    }

    private func submitTyped(_ q: RetentionQuestion, giveUp: Bool = false) {
        guard var qz = quiz, let lib = model.library, let prof = model.profile else { return }
        let first = !qz.isRelearning
        let ok = qz.answer(typed: giveUp ? "" : typed, variant: prof.variant(for: lib), context: lib.checkContext)
        quiz = qz
        after(q, ok: ok, first: first)
    }

    private func after(_ q: RetentionQuestion, ok: Bool, first: Bool) {
        model.sfx(ok ? .correct : .retry)
        model.haptic(ok)
        let usedHint = quiz?.hinted.contains(q.itemId) ?? false
        // Saved when the player moves on, so "I guessed" can still be ticked.
        if first { pending = (q, ok, usedHint, Date().timeIntervalSince(questionStart)) }
        guessed = false
        comboHit = combo.record(ok)
        hintShown = nil
        feedback = (ok, q)
    }

    private func flushPending() {
        guard let pr = pending else { return }
        pending = nil
        let g = guessed
        model.updateProfile { RetentionQuiz.record(pr.q, correct: pr.ok, hinted: pr.hinted, guessed: g, seconds: pr.seconds, profile: &$0, now: Date()) }
    }

    private func finish() {
        guard record == nil, let qz = quiz, qz.isFinished else { return }
        flushPending()
        record = model.finishRetentionQuiz(qz)
        model.celebrateLockIns(before: startKnowledge)
        if let r = record { UIAccessibility.post(notification: .announcement, argument: "\(r.correct) of \(r.total) right") }
    }
}

struct MemoryCheckSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var length: MemoryCheckLength?
    var body: some View {
        NavigationStack {
            Group {
                if let l = length {
                    RetentionQuizView(kind: .memoryCheck, count: l.rawValue) { rec in
                        model.updateProfile { TodayPath.mark(.memoryCheck, profile: &$0, now: Date()) }
                        if l == .long, rec != nil { model.earnFreezeIfPossible() }
                        dismiss()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "brain.head.profile").font(.system(size: 54)).accessibilityHidden(true)
                        Text("Memory check").font(.title.bold())
                        Text("Questions on the words that are starting to fade, so they come back stronger.")
                            .multilineTextAlignment(.center)
                        Button("Quick: 5 questions") { length = .short }.buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("check-5")
                        Button("Longer: 10 questions (earns a streak freeze once a week)") { length = .long }.buttonStyle(.bordered)
                            .accessibilityIdentifier("check-10")
                        Button("Listening only: 5 questions") { model.sheet = .listeningCheck }.buttonStyle(.bordered)
                            .accessibilityIdentifier("check-listen")
                    }
                    .padding(24)
                    .frame(maxWidth: 600)
                }
            }
                .background(ThemedBackground())
                .navigationTitle("Memory check")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - My progress (tracked over time)

struct MyProgressView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile, let lib = model.library {
                    let r = RetentionReport.make(prof, now: Date())
                    Section {
                        HStack {
                            statTile("\(r.predictedRetention.map { "\($0)%" } ?? "–")", "remembered now")
                            statTile("\(r.lockedIn)", "locked in")
                            statTile("\(r.fading)", "fading")
                        }
                        .accessibilityElement(children: .combine)
                        Button("Do a quick memory check") { model.sheet = .memoryCheck }
                            .accessibilityIdentifier("progressMemoryCheck")
                    } header: { Text("Your memory in \(model.languageName)") } footer: {
                        Text("\"Remembered now\" is the app's estimate of how many of your words you'd recall today. Words are locked in after you remember them 3 times after a break.")
                    }
                    Section { NavigationLink("How memory works") { MemoryScienceView() } }
                    TrickyWordsSection()
                    WordsThisWeekSection()
                    StreakCalendarSection()
                    PracticeTimesSection()
                    PersonalBestsSection()
                    Section("Quiz scores by week") {
                        Chart(r.weeks) { w in
                            if let avg = w.averagePercent {
                                BarMark(x: .value("Week", w.date, unit: .weekOfYear), y: .value("Average %", avg))
                                    .foregroundStyle(Color(p.accent))
                                    .accessibilityLabel(w.date.formatted(.dateTime.month().day()))
                                    .accessibilityValue("\(avg) percent, \(w.quizzes) quizzes")
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 180)
                        Text("\(r.lessonQuizzes) lesson quizzes · \(r.memoryChecks) memory checks" + (r.averageLast10.map { " · last 10: \($0)%" } ?? ""))
                            .font(.caption)
                    }
                    if !r.mostMissed.isEmpty {
                        Section("Words to practice") {
                            ForEach(r.mostMissed, id: \.self) { id in
                                if let item = lib.item(id) {
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
                        }
                    }
                    let hist = (prof.extrasOrEmpty.quizHistory ?? []).suffix(15).reversed()
                    if !hist.isEmpty {
                        Section("Recent quizzes") {
                            ForEach(Array(hist.enumerated()), id: \.offset) { _, rec in
                                NavigationLink { QuizDetailView(record: rec) } label: {
                                HStack {
                                    Image(systemName: rec.isLesson ? "flag.checkered" : "brain.head.profile").accessibilityHidden(true)
                                    Text(rec.isLesson ? (rec.questId.flatMap { lib.quest($0)?.quest.title } ?? "Lesson quiz") : "Memory check")
                                    Spacer()
                                    Text("\(rec.correct)/\(rec.total)").bold()
                                }
                                .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My progress")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title.bold())
            Text(label).font(.caption).foregroundStyle(Color(p.secondaryText))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Streak card (main menu)

struct StreakCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    var body: some View {
        if let prof = model.profile {
            let now = Date()
            let s = Streak.state(prof), cur = Streak.current(prof, now: now)
            let done = Streak.status(prof, now: now) == .practicedToday
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "flame.fill").font(.system(size: 36))
                        .foregroundStyle(done ? Color.orange : Color(p.secondaryText))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cur == 1 ? "1-day streak" : "\(cur)-day streak").font(.headline)
                        Text(Streak.message(prof, now: now)).font(.subheadline)
                        Label("\(s.freezesLeft) streak freeze\(s.freezesLeft == 1 ? "" : "s") left this week", systemImage: "snowflake")
                            .font(.caption).foregroundStyle(Color(p.secondaryText))
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("streakCard")
        }
    }
}

// MARK: - Welcome back (language page)

struct WelcomeBackCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile, let w = WelcomeBack.make(prof, now: Date()) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Welcome back!", systemImage: "hand.wave.fill").font(.headline)
                    Text(w.message).font(.subheadline)
                    Button("Quick memory check (5 questions)") { model.sheet = .memoryCheck }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("welcomeBackCheck")
                }
            }
        }
    }
}

// MARK: - Reminders: the player's own switch, and the parent's block

struct SmartRemindersToggle: View {
    @EnvironmentObject var model: AppModel
    @State private var note: String?

    var body: some View {
        let blocked = model.save.parent.remindersBlocked == true
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Come-back reminders", isOn: Binding(
                get: { (model.profile?.settings.smartRemindersOn ?? false) && !blocked },
                set: { on in
                    if on {
                        Task { @MainActor in
                            let ok = await ReminderScheduler.requestPermission()
                            model.updateProfile { $0.settings.smartReminders = ok }
                            note = ok ? nil : "Notifications are off for Language Quest in the iPhone's Settings › Notifications."
                            model.rescheduleSmartReminders()
                        }
                    } else {
                        model.updateProfile { $0.settings.smartReminders = false }
                        model.rescheduleSmartReminders()
                    }
                }))
            .disabled(blocked)
            .accessibilityIdentifier("smartRemindersToggle")
            Text(blocked ? "A parent turned these off." :
                 "A friendly nudge at the time you usually play, when words are ready for review. Nothing after 8:30 pm, and they slow down if you take a break.")
                .font(.caption)
            if let n = note { Text(n).font(.caption) }
        }
    }
}

struct ParentBlockRemindersToggle: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Toggle("Block the explorer's come-back reminders", isOn: Binding(
            get: { model.save.parent.remindersBlocked == true },
            set: { v in model.updateParent { $0.remindersBlocked = v }; model.rescheduleSmartReminders() }))
        .accessibilityIdentifier("blockSmartReminders")
    }
}

// MARK: - Family Plus paywall (parental gate first)

struct PlusPaywallView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var gatePassedAt: Date?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if gatePassedAt == nil {
                    // Every purchase screen sits behind the parental gate (Apple's guidance for apps used by kids).
                    if let record = ParentPINStore.load() {
                        PINGateView(record: record) { gatePassedAt = Date() }
                    } else {
                        ParentGateView { gatePassedAt = Date() }
                    }
                } else {
                    offer
                }
            }
            .navigationTitle("Family Plus")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await model.store.loadProducts() }
        }
    }

    private var offer: some View {
        List {
            if model.plan == .familyPlus {
                Section { Label("Family Plus is active on this device. Thank you!", systemImage: "checkmark.seal.fill") }
            }
            Section("Family Plus adds") {
                ForEach(PlusOffer.benefits, id: \.self) { Label($0, systemImage: "plus.circle.fill") }
            }
            Section("Always free") {
                ForEach(PlusOffer.alwaysFree, id: \.self) { Label($0, systemImage: "heart.fill") }
            }
            Section {
                if !model.save.parent.purchasesAllowed {
                    Toggle("Allow purchases on this device", isOn: Binding(get: { model.save.parent.purchasesAllowed },
                                                                          set: { v in model.updateParent { $0.purchasesAllowed = v } }))
                        .accessibilityIdentifier("allowPurchases")
                }
                if model.store.products.isEmpty {
                    Text(model.store.lastError ?? "Loading prices from the App Store…").font(.subheadline)
                }
                ForEach(model.store.products, id: \.id) { product in
                    let period = product.subscription.map { Self.periodName($0.subscriptionPeriod) } ?? ""
                    let trial = product.subscription?.introductoryOffer?.paymentMode == .freeTrial
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            buy(product)
                        } label: {
                            VStack(spacing: 2) {
                                Text(trial ? "Start \(PlusOffer.trialDays)-day free trial" : "Subscribe").font(.headline)
                                Text("then \(product.displayPrice) / \(period)").font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || !model.save.parent.purchasesAllowed)
                        .accessibilityIdentifier("buy-\(period)")
                        Text(PlusOffer.disclosure(price: product.displayPrice, period: period, hasTrial: trial)).font(.caption2)
                    }
                }
                Button("Restore purchases") {
                    Task { busy = true; await model.store.restore(); await model.refreshEntitlements(); busy = false
                        message = model.plan == .familyPlus ? "Family Plus restored." : "No active Family Plus subscription was found." }
                }
                .accessibilityIdentifier("restorePurchases")
                if let m = message { Text(m).font(.subheadline) }
            } header: { Text("Choose a plan") } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Family Sharing works: one subscription covers the family. Learning essentials stay free whether or not you subscribe.")
                    Link("Terms of Use (Apple standard EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    if let s = PrivacyNotice.hostedPolicyURL, let u = URL(string: s) { Link("Privacy policy", destination: u) }
                    Button("Manage subscription") { Task { await manage() } }
                }
                .font(.caption)
            }
        }
    }

    static func periodName(_ p: Product.SubscriptionPeriod) -> String {
        switch p.unit {
        case .day: return p.value == 7 ? "week" : "\(p.value) days"
        case .week: return "week"
        case .month: return p.value == 1 ? "month" : "\(p.value) months"
        case .year: return "year"
        @unknown default: return "period"
        }
    }

    private func buy(_ product: Product) {
        guard PurchaseGate.decide(config: model.storeConfig, parent: model.save.parent, gatePassedAt: gatePassedAt, now: Date()) == .allowed else {
            gatePassedAt = nil      // the gate has timed out: ask again
            return
        }
        busy = true
        Task {
            let r = await model.store.purchase(product)
            await model.refreshEntitlements()
            busy = false
            switch r {
            case .purchased: message = "Welcome to Family Plus!"; model.celebrate(.init(icon: "sparkles", title: "Family Plus is on", detail: "New units and games are open."))
            case .pending: message = "Waiting for approval (Ask to Buy)."
            case .cancelled: message = nil
            case .failed: message = model.store.lastError ?? "The purchase didn't go through."
            }
        }
    }

    private func manage() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
}

/// A small "Plus" tag for locked content; tapping opens the paywall.
struct PlusLockLabel: View {
    @EnvironmentObject var model: AppModel
    var text = "Family Plus"
    var body: some View {
        Button { model.sheet = .plus } label: {
            Label(text, systemImage: "lock.fill").font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Opens Family Plus for a parent")
    }
}
