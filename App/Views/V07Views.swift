import SwiftUI
import LQCore

// MARK: - Level badge (explorer card)

struct LevelBadge: View {
    @Environment(\.palette) var p
    let xp: Int

    var body: some View {
        let lvl = ExplorerLevel.level(forXP: xp)
        let prog = ExplorerLevel.progress(forXP: xp)
        VStack(alignment: .leading, spacing: 4) {
            let pill = Text("Lv \(lvl)").font(.caption.bold())
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color(p.accent), in: Capsule())
                .foregroundStyle(Color(p.onAccent))
            let title = Text(ExplorerLevel.title(lvl)).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { pill; title }
                VStack(alignment: .leading, spacing: 4) { pill; title }
            }
            ProgressView(value: Double(prog.into), total: Double(prog.needed)).tint(Color(p.accent))
            Text("\(prog.into)/\(prog.needed) XP to level \(lvl + 1)").font(.caption).foregroundStyle(Color(p.secondaryText))
                .fixedSize(horizontal: false, vertical: true)   // wrap instead of truncating at large text sizes
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(lvl), \(ExplorerLevel.title(lvl)). \(prog.into) of \(prog.needed) XP to the next level.")
    }
}

// MARK: - Daily challenges (main menu)

struct DailyChallengesCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    var body: some View {
        if let prof = model.profile {
            let now = Date()
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Daily challenges", systemImage: "flag.checkered").font(.headline)
                        Spacer()
                        Text("New ones every day").font(.caption).foregroundStyle(Color(p.secondaryText))
                    }
                    ForEach(DailyChallenge.today(now)) { c in
                        HStack(spacing: 10) {
                            Image(systemName: c.icon).frame(width: 26).foregroundStyle(Color(p.accent)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.title).font(.subheadline)
                                ProgressView(value: Double(c.count(prof, now: now)), total: Double(c.goal)).tint(Color(p.accent))
                            }
                            if c.isClaimed(prof, now: now) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(p.success)).accessibilityLabel("Claimed")
                            } else if c.isDone(prof, now: now) {
                                Button("+\(DailyChallenge.xp) XP") {
                                    model.updateProfile { _ = c.claim(&$0, now: now) }
                                    model.sfx(.coin)
                                    model.checkMilestones()
                                }
                                .font(.caption.bold())
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("claim-\(c.id)")
                            } else {
                                Text("\(c.count(prof, now: now))/\(c.goal)").font(.caption.monospacedDigit())
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Celebration

struct CelebrationOverlay: View {
    @Environment(\.palette) var p
    let celebration: AppModel.Celebration
    let reducedMotion: Bool
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onDone)
            if !reducedMotion { ConfettiView().ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: 12) {
                Image(systemName: celebration.icon).font(.system(size: 56)).foregroundStyle(Color(p.accent))
                Text(celebration.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(celebration.detail).multilineTextAlignment(.center)
                Button("Awesome!", action: onDone).buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("celebrationDone")
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 22))
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// Lightweight confetti drawn with Canvas (no particle assets).
struct ConfettiView: View {
    @State private var start = Date()
    private let pieces: [(x: Double, speed: Double, spin: Double, color: Color, size: Double, delay: Double)] = (0..<70).map { i in
        let colors: [Color] = [.pink, .yellow, .mint, .orange, .purple, .cyan, .green]
        var g = SeededRandom(seed: UInt64(i + 1) * 7919)
        func r() -> Double { Double(g.next() % 10_000) / 10_000 }
        return (r(), 120 + r() * 160, r() * 6, colors[i % colors.count], 5 + r() * 6, r() * 0.6)
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { c, size in
                let t = ctx.date.timeIntervalSince(start)
                for p in pieces {
                    let tt = t - p.delay
                    guard tt > 0, tt < 3.2 else { continue }
                    let y = -20 + tt * p.speed
                    let x = p.x * size.width + sin(tt * 3 + p.spin) * 18
                    var rect = Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2))
                    rect = rect.applying(CGAffineTransform(rotationAngle: tt * p.spin + p.spin)).applying(CGAffineTransform(translationX: x, y: y))
                    c.fill(rect, with: .color(p.color.opacity(max(0, 1 - tt / 3.2))))
                }
            }
        }
    }
}

// MARK: - Trophies

struct TrophiesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile {
                    Section { LevelBadge(xp: prof.rewards.xp) }
                    let have = prof.metaOrEmpty.achievements
                    Section("\(have.count) of \(Achievement.all.count) achievements") {
                        ForEach(Achievement.all) { a in
                            HStack(spacing: 12) {
                                Image(systemName: have[a.id] != nil ? a.icon : "lock.fill")
                                    .font(.title3).frame(width: 34)
                                    .foregroundStyle(have[a.id] != nil ? Color(p.accent) : Color(p.secondaryText))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.title).font(.headline)
                                    Text(a.detail).font(.caption).foregroundStyle(Color(p.secondaryText))
                                }
                                Spacer()
                                if let d = have[a.id] { Text(d, style: .date).font(.caption2) }
                                else if let pr = a.progress(prof, libraries: model.libraries) { AchievementProgressBar(progress: pr).frame(width: 80) }
                            }
                            .opacity(have[a.id] != nil ? 1 : 0.6)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(have[a.id] != nil ? "Unlocked" : "Locked")
                        }
                    }
                }
            }
            .navigationTitle("Trophies")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { model.checkMilestones() }
        }
    }
}

// MARK: - Stats

struct StatsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile {
                    ReviewForecastSection()
                    Section("Last 7 days") {
                        let week = PlayerStats.lastWeek(prof, now: Date())
                        let top = max(week.map(\.activities).max() ?? 1, 1)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(week) { d in
                                VStack(spacing: 4) {
                                    Text("\(d.activities)").font(.caption2.monospacedDigit())
                                    RoundedRectangle(cornerRadius: 4).fill(Color(p.accent))
                                        .frame(height: max(4, CGFloat(d.activities) / CGFloat(top) * 90))
                                    Text(d.label).font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(d.label): \(d.activities) activities")
                            }
                        }
                        .frame(height: 130)
                    }
                    MonthCalendarSection()
                    Section("Words by language") {
                        let langs = PlayerStats.languages(prof, libraries: model.libraries)
                        if langs.isEmpty { Text("Words show up here once you start a quest.") }
                        ForEach(langs) { l in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(l.language).font(.headline); Spacer(); Text("\(l.total) words").font(.subheadline) }
                                GeometryReader { g in
                                    HStack(spacing: 1) {
                                        ForEach(MasteryLevel.allCases.filter { $0 != .new }, id: \.self) { lv in
                                            let n = l.byLevel[lv] ?? 0
                                            if n > 0 {
                                                Rectangle().fill(color(lv))
                                                    .frame(width: g.size.width * CGFloat(n) / CGFloat(max(l.total, 1)))
                                            }
                                        }
                                    }
                                }
                                .frame(height: 12).clipShape(Capsule())
                                Text(MasteryLevel.allCases.filter { $0 != .new && (l.byLevel[$0] ?? 0) > 0 }
                                        .map { "\($0.label) \(l.byLevel[$0] ?? 0)" }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Color(p.secondaryText))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Section("Totals") {
                        let c = prof.metaOrEmpty.counters
                        Label("\(prof.rewards.xp) XP · level \(ExplorerLevel.level(forXP: prof.rewards.xp))", systemImage: "star.fill")
                        Label("\(c[MetaEvent.activity.rawValue] ?? 0) activities finished", systemImage: "checkmark.circle")
                        Label("\(c[MetaEvent.flashcardRight.rawValue] ?? 0) flashcards right", systemImage: "rectangle.on.rectangle.angled")
                        Label("\(c[MetaEvent.wordWritten.rawValue] ?? 0) words written", systemImage: "pencil.and.scribble")
                        Label("\(c[MetaEvent.duelWon.rawValue] ?? 0) duels won", systemImage: "bolt.fill")
                    }
                }
            }
            .navigationTitle("My stats")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func color(_ lv: MasteryLevel) -> Color {
        switch lv {
        case .new: return .gray
        case .learning: return Color(p.accent).opacity(0.35)
        case .familiar: return Color(p.accent).opacity(0.6)
        case .understood: return Color(p.accent)
        case .canUse: return Color(p.success)
        }
    }
}

// MARK: - Mistakes notebook

struct MistakesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var practicing = false
    @State private var queue: [MistakeEntry] = []
    @State private var index = 0
    @State private var answered: Bool?

    var body: some View {
        NavigationStack {
            Group {
                if practicing, let lib = model.library {
                    VStack(spacing: 16) {
                        if index < queue.count {
                            let e = queue[index]
                            let card = Flashcard(itemId: e.itemId, front: e.target, back: e.english, picture: lib.item(e.itemId)?.picture)
                            Text("Retry \(index + 1) of \(queue.count)").font(.caption)
                            ChoiceFlashcard(card: card, choices: FlashcardChoices.make(for: card, library: lib, seed: UInt64(index + 11)),
                                            romanized: (model.profile?.settings.romanizationOn ?? true) ? lib.course.romanize(e.target.base) : nil) { ok in
                                model.updateProfile { FlashcardDeck.record(card, knewIt: ok, profile: &$0, now: Date()) }
                                if ok { model.record(.flashcardRight) }
                                answered = ok
                            }
                            .id(index)
                            if answered != nil {
                                Button("Next") { answered = nil; index += 1 }.buttonStyle(PrimaryButtonStyle())
                            }
                        } else {
                            Text("All retried!").font(.largeTitle.bold())
                            Text("Missed words come back sooner in Review, so they'll stick.").multilineTextAlignment(.center)
                            Button("Back to the notebook") { practicing = false }.buttonStyle(PrimaryButtonStyle())
                        }
                        Spacer()
                    }
                    .padding(20)
                } else {
                    list
                }
            }
            .background(ThemedBackground())
            .navigationTitle("Mistakes notebook")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var list: some View {
        List {
            if let prof = model.profile, let lib = model.library {
                let entries = MistakesNotebook.entries(prof, library: lib)
                Section {
                    Text("Mistakes are how words stick. These are the \(model.languageName) words you've missed most.")
                        .font(.subheadline)
                    if !entries.isEmpty {
                        Button {
                            queue = Array(entries.prefix(10)); index = 0; answered = nil; practicing = true
                        } label: { Label("Retry these words", systemImage: "arrow.counterclockwise") }
                        .accessibilityIdentifier("retryMistakes")
                    }
                }
                Section {
                    if entries.isEmpty { Text("No mistakes yet. Nice!") }
                    ForEach(entries) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.display(e.target)).font(.headline)
                                Text(e.english).font(.caption).foregroundStyle(Color(p.secondaryText))
                            }
                            Spacer()
                            Text("missed \(e.misses)×").font(.caption.monospacedDigit())
                            SpeakerButton(text: e.target)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Echo

struct EchoView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: EchoGame?
    @State private var picked: Int?
    @State private var shownIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let g = game, shownIndex < g.questions.count {
                    let q = g.questions[shownIndex]
                    Text("Round \(shownIndex + 1) of \(g.questions.count)").font(.caption)
                    Text("Listen. Which one did you hear?").font(.headline)
                    Button { model.say(q.spoken) } label: {
                        Image(systemName: "speaker.wave.3.fill").font(.system(size: 54))
                            .frame(width: 130, height: 130)
                            .background(Color(p.accent).opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel("Play the word again")
                    .accessibilityIdentifier("echoPlay")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                            Button { pick(i, q) } label: {
                                Text(model.display(o)).font(.title3.bold()).multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 70)
                                    .background(fill(i, q), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .disabled(picked != nil)
                            .accessibilityIdentifier("echo-option-\(i)")
                        }
                    }
                    if picked != nil {
                        Text("\(model.text(q.spoken)) = \(q.english)").font(.headline)
                        Button("Next") { next() }.buttonStyle(PrimaryButtonStyle())
                    }
                    Spacer()
                } else if let g = game {
                    Spacer()
                    Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars)).font(.largeTitle).accessibilityLabel("\(g.stars) of 3 stars")
                    Text("\(g.correct) of \(g.questions.count) heard right").font(.title2.bold())
                    Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    Spacer()
                }
            }
            .padding(20)
            .background(ThemedBackground())
            .navigationTitle("Echo")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
        }
    }

    private func fill(_ i: Int, _ q: EchoQuestion) -> Color {
        guard let pk = picked else { return Color(p.surface) }
        if i == q.answerIndex { return Color.green.opacity(0.35) }
        return i == pk ? Color.red.opacity(0.3) : Color(p.surface)
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        game = EchoGame(profile: prof, library: lib, seed: UInt64.random(in: 1...UInt64.max / 2))
        picked = nil; shownIndex = 0
        if let q = game?.current { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.say(q.spoken) } }
    }

    private func pick(_ i: Int, _ q: EchoQuestion) {
        guard var g = game else { return }
        let ok = g.answer(i)
        game = g
        picked = i
        model.sfx(ok ? .correct : .retry)
        model.updateProfile { PracticeRecorder.record(itemId: q.itemId, outcome: ReviewOutcome(correct: ok), track: .comprehension, profile: &$0, now: Date()) }
        if g.current == nil { model.record(.gamePlayed) }
    }

    private func next() {
        picked = nil
        shownIndex += 1
        if let q = game?.current { model.say(q.spoken) }
    }
}

// MARK: - Memory Match

struct MemoryMatchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: MemoryMatch?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let g = game {
                    HStack {
                        Text("Moves: \(g.moves)").font(.headline.monospacedDigit())
                        Spacer()
                        Text("Pairs: \(g.matched.count)/\(MemoryMatch.pairs)").font(.headline.monospacedDigit())
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(g.cards) { c in
                            Button { flip(c) } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(g.isFaceUp(c.id) ? (g.matched.contains(c.pairId) ? Color.green.opacity(0.3) : Color(p.surface)) : Color(p.accent))
                                    if g.isFaceUp(c.id) {
                                        Text(c.isTarget ? model.display(c.text) : c.text.base)
                                            .font(c.isTarget ? .headline : .subheadline)
                                            .multilineTextAlignment(.center).minimumScaleFactor(0.6).padding(4)
                                    } else {
                                        Image(systemName: "questionmark").font(.title.bold()).foregroundStyle(Color(p.onAccent))
                                    }
                                }
                                .frame(height: 86)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(g.isFaceUp(c.id) ? c.text.base : "Face-down card")
                            .accessibilityIdentifier("memory-\(c.id)")
                        }
                    }
                    if g.finished {
                        Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars)).font(.largeTitle)
                        Text("All pairs in \(g.moves) moves!").font(.headline)
                        Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Text("Match each word with its meaning.").font(.caption)
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(ThemedBackground())
            .navigationTitle("Memory Match")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        game = MemoryMatch(profile: prof, library: lib, seed: UInt64.random(in: 1...UInt64.max / 2))
    }

    private func flip(_ c: MemoryCard) {
        guard var g = game, !busy else { return }
        let r = g.flip(c.id)
        game = g
        if c.isTarget && r != .ignored { model.say(c.text) }
        switch r {
        case .match:
            model.sfx(.correct)
            model.updateProfile { PracticeRecorder.record(itemId: c.pairId, outcome: ReviewOutcome(correct: true), track: .comprehension, profile: &$0, now: Date()) }
            if g.finished { model.record(.gamePlayed) }
        case .mismatch:
            model.sfx(.retry)
            busy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                busy = false
                // Turn the pair back down by starting the next flip cycle.
                if var gg = game { gg.hideMismatch(); game = gg }
            }
        default: model.sfx(.select)
        }
    }
}

// MARK: - Spelling Bee

struct SpellingBeeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: SpellingBee?
    @State private var typed = ""
    @State private var verdict: (ok: Bool, expected: String)?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let g = game, let w = (verdict != nil ? g.words[g.index - 1] : g.current) {
                    Text("Word \(min(g.index + (verdict == nil ? 1 : 0), g.words.count)) of \(g.words.count)").font(.caption)
                    Button { model.say(w.target) } label: {
                        Image(systemName: "speaker.wave.3.fill").font(.system(size: 44))
                            .frame(width: 100, height: 100)
                            .background(Color(p.accent).opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel("Hear the word")
                    Text("Meaning: \(w.english)").font(.headline)
                    if let pic = w.picture { Text(pic).font(.system(size: 44)).accessibilityHidden(true) }
                    TextField(model.library?.course.hasRomanization == true ? "Type it (or its Latin spelling)" : "Type the word", text: $typed)
                        .textFieldStyle(.roundedBorder).font(.title2)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused)
                        .disabled(verdict != nil)
                        .onSubmit(submit)
                        .accessibilityIdentifier("beeField")
                    if let v = verdict {
                        Label(v.ok ? "Correct!" : "It's spelled: \(v.expected)", systemImage: v.ok ? "checkmark.circle.fill" : "pencil.line")
                            .font(.headline).foregroundStyle(Color(v.ok ? p.success : p.retry))
                        Button("Next") { verdict = nil; typed = ""; focused = true; if let n = game?.current { model.say(n.target) } }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Check", action: submit).buttonStyle(PrimaryButtonStyle()).disabled(typed.isEmpty)
                    }
                    Spacer()
                } else if let g = game {
                    Spacer()
                    Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars)).font(.largeTitle).accessibilityLabel("\(g.stars) of 3 stars")
                    Text("\(g.correct) of \(g.words.count) spelled right").font(.title2.bold())
                    Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    Spacer()
                }
            }
            .padding(20)
            .background(ThemedBackground())
            .navigationTitle("Spelling Bee")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        game = SpellingBee(profile: prof, library: lib, seed: UInt64.random(in: 1...UInt64.max / 2))
        typed = ""; verdict = nil; focused = true
        if let w = game?.current { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.say(w.target) } }
    }

    private func submit() {
        guard var g = game, let lib = model.library, let w = g.current, !typed.isEmpty else { return }
        let variant = model.profile?.variant ?? lib.course.defaultVariant
        let v = g.submit(typed, variant: variant, library: lib)
        game = g
        verdict = (v.isCorrect, w.target.text(for: variant))
        model.sfx(v.isCorrect ? .correct : .retry)
        model.updateProfile { PracticeRecorder.record(itemId: w.id, outcome: ReviewOutcome(correct: v.isCorrect), track: .guidedProduction, profile: &$0, now: Date()) }
        if g.current == nil { model.record(.gamePlayed) }
    }
}

// MARK: - Privacy policy (shipped in the app, works offline)

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    /// false when pushed inside an existing navigation stack (the Parents area).
    var standalone = true

    var body: some View {
        if standalone {
            NavigationStack {
                content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        } else {
            content
        }
    }

    private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(PrivacyNotice.policyMarkdown().components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("# ") {
                            Text(line.dropFirst(2)).font(.title.bold()).accessibilityAddTraits(.isHeader)
                        } else if line.hasPrefix("## ") {
                            Text(line.dropFirst(3)).font(.title3.bold()).padding(.top, 6).accessibilityAddTraits(.isHeader)
                        } else if line.hasPrefix("- ") {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").accessibilityHidden(true)
                                Text(md(String(line.dropFirst(2))))
                            }
                        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(md(line))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Privacy policy")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("privacyPolicy")
    }

    private func md(_ s: String) -> AttributedString { (try? AttributedString(markdown: s)) ?? AttributedString(s) }
}
