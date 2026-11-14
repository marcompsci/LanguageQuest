import SwiftUI
import LQCore

private func playSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max / 2) }

// MARK: - 3. Slow replay

/// A turtle button that says the word slowly.
struct SlowSpeakerButton: View {
    @EnvironmentObject var model: AppModel
    let text: VText
    var body: some View {
        Button { model.say(text, slow: true) } label: {
            Image(systemName: "tortoise.fill").font(.title3).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Hear it slowly")
    }
}

// MARK: - 1. Listen & Type

struct ListenTypeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: ListenTypeGame?
    @State private var typed = ""
    @State private var feedback: (ok: Bool, text: String)?
    @State private var saved = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let g = game, let item = g.current {
                        Text("Word \(g.index + 1) of \(g.items.count)").font(.caption)
                        Text("Listen, then type what you hear.").font(.headline)
                        HStack(spacing: 16) {
                            SpeakerButton(text: item.target, label: "Play the word", big: true)
                            SlowSpeakerButton(text: item.target)
                        }
                        if feedback == nil {
                            TextField("Type it here", text: $typed)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focused)
                                .onSubmit { submit() }
                                .accessibilityIdentifier("listenTypeField")
                            Button("Check") { submit() }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                                .accessibilityIdentifier("listenTypeCheck")
                            Text("Tip: you can type the pronunciation line for non-Latin scripts.")
                                .font(.caption).foregroundStyle(Color(p.secondaryText)).multilineTextAlignment(.center)
                        }
                    } else if let g = game, g.isFinished, !g.items.isEmpty {
                        Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars))
                            .font(.largeTitle).accessibilityLabel("\(g.stars) of 3 stars")
                        Text("\(g.correct) of \(g.items.count) right").font(.title2.bold())
                        if !g.missed.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Words to listen to again").font(.headline)
                                ForEach(g.missed, id: \.id) { m in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(model.display(m.target)).font(.headline)
                                            Text(m.english).font(.caption).foregroundStyle(Color(p.secondaryText))
                                        }
                                        Spacer()
                                        SpeakerButton(text: m.target)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    }
                    if let f = feedback {
                        Text(f.text).font(.headline).multilineTextAlignment(.center)
                            .foregroundStyle(Color(f.ok ? p.success : p.retry))
                        Button(game?.isFinished == true ? "See my score" : "Next word") { next() }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("listenTypeNext")
                    }
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(ThemedBackground())
            .navigationTitle("Listen & Type")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        game = ListenTypeGame(profile: prof, library: lib, seed: playSeed())
        typed = ""; feedback = nil; saved = false
        if let w = game?.current { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.say(w.target) } }
    }

    private func submit() {
        guard var g = game, let item = g.current, let lib = model.library, let prof = model.profile, !typed.isEmpty else { return }
        let v = prof.variant(for: lib)
        let verdict = g.submit(typed, variant: v, context: lib.checkContext)
        game = g
        model.sfx(verdict.isCorrect ? .correct : .retry)
        model.updateProfile {
            PracticeRecorder.record(itemId: item.id, outcome: ReviewOutcome(correct: verdict.isCorrect), track: .spontaneousProduction, profile: &$0, now: Date())
        }
        feedback = (verdict.isCorrect, AnswerChecker.feedback(for: verdict, praise: "Great ear!", variantName: model.variantName)
                    + (verdict.isCorrect ? "" : "\nIt means “\(item.english)”."))
    }

    private func next() {
        feedback = nil; typed = ""
        guard let g = game else { return }
        if g.isFinished {
            if !saved { saved = true; model.updateProfile { ListenTypeGame.finish(g, profile: &$0) }; model.record(.gamePlayed) }
        } else if let w = g.current {
            model.say(w.target); focused = true
        }
    }
}

// MARK: - 2. Right or Wrong

struct RightOrWrongView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: RightOrWrongGame?
    @State private var last: (ok: Bool, round: RightOrWrongRound)?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let g = game, let r = g.current, last == nil {
                        Text("Round \(g.index + 1) of \(g.rounds.count)").font(.caption)
                        HStack {
                            Text(model.display(r.word)).font(.largeTitle.bold()).multilineTextAlignment(.center)
                            SpeakerButton(text: r.word)
                        }
                        Text("means").font(.headline).foregroundStyle(Color(p.secondaryText))
                        Text("“\(r.shownMeaning)”").font(.title2).multilineTextAlignment(.center)
                        HStack(spacing: 14) {
                            Button { answer(true) } label: { Label("Right", systemImage: "checkmark").frame(maxWidth: .infinity) }
                                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rowRight")
                            Button { answer(false) } label: { Label("Wrong", systemImage: "xmark").frame(maxWidth: .infinity) }
                                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rowWrong")
                        }
                    } else if let l = last {
                        Image(systemName: l.ok ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 56)).foregroundStyle(Color(l.ok ? p.success : p.retry)).accessibilityHidden(true)
                        Text(l.ok ? "Yes!" : "Not this time.").font(.title2.bold())
                        Text("\(model.text(l.round.word)) means “\(l.round.realMeaning)”.").multilineTextAlignment(.center)
                        Button(game?.isFinished == true ? "See my score" : "Next") { next() }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rowNext")
                    } else if let g = game, g.isFinished {
                        Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars))
                            .font(.largeTitle).accessibilityLabel("\(g.stars) of 3 stars")
                        Text("\(g.correct) of \(g.rounds.count) right").font(.title2.bold())
                        Button("Play again") { start() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(ThemedBackground())
            .navigationTitle("Right or Wrong")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if game == nil { start() } }
        }
    }

    private func start() {
        guard let prof = model.profile, let lib = model.library else { return }
        game = RightOrWrongGame(profile: prof, library: lib, seed: playSeed()); last = nil; saved = false
    }

    private func answer(_ saysRight: Bool) {
        guard var g = game, let r = g.current else { return }
        let ok = g.answer(saysRight: saysRight)
        game = g; last = (ok, r)
        model.sfx(ok ? .correct : .retry)
        model.updateProfile { PracticeRecorder.record(itemId: r.itemId, outcome: ReviewOutcome(correct: ok), track: .comprehension, profile: &$0, now: Date()) }
    }

    private func next() {
        last = nil
        guard let g = game, g.isFinished, !saved else { return }
        saved = true
        model.updateProfile { RightOrWrongGame.finish(g, profile: &$0) }
        model.record(.gamePlayed)
    }
}

// MARK: - 4. Unit progress map

struct UnitMapCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    var body: some View {
        if let prof = model.profile, let lib = model.library, let prog = model.progression {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your units", systemImage: "map.fill").font(.headline)
                    ForEach(UnitMap.units(prof, library: lib, progression: prog, plan: model.plan)) { u in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Unit \(u.order): \(u.title)").font(.subheadline.bold())
                                Spacer()
                                if !u.unlocked { Image(systemName: "lock.fill").font(.caption).accessibilityHidden(true) }
                            }
                            bar(u.fractionDone, color: Color(p.accent))
                            Text(detail(u)).font(.caption).foregroundStyle(Color(p.secondaryText))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Unit \(u.order), \(u.title)\(u.unlocked ? "" : ", locked"). \(detail(u))")
                    }
                }
            }
            .accessibilityIdentifier("unitMap")
        }
    }

    private func detail(_ u: UnitProgress) -> String {
        var s = "\(u.questsDone)/\(u.questsTotal) quests · \(u.wordsStrong)/\(u.wordsTotal) words strong"
        if let q = u.quizBest { s += " · quiz \(q)%" }
        return s
    }

    private func bar(_ f: Double, color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(p.secondaryText).opacity(0.25))
                Capsule().fill(color).frame(width: max(f > 0 ? 6 : 0, g.size.width * f))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - 8. Conversation replay

struct ConversationReplayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let questId: String
    @State private var showEnglish = true
    @State private var counted = false

    var body: some View {
        List {
            if let q = model.library?.units.flatMap(\.quests).first(where: { $0.id == questId }) {
                let name = StarterVillage.npc(q.npc)?.name ?? q.npc
                Section {
                    Toggle("Show English", isOn: $showEnglish).accessibilityIdentifier("replayEnglish")
                } footer: { Text("Tap a line to hear it again.") }
                Section(q.title) {
                    ForEach(ConversationReplay.lines(q, npcName: name)) { line in
                        Button { model.say(line.text) } label: {
                            VStack(alignment: line.isYou ? .trailing : .leading, spacing: 3) {
                                Text(line.speaker).font(.caption.bold()).foregroundStyle(Color(p.secondaryText))
                                Text(model.display(line.text)).font(.body)
                                    .multilineTextAlignment(line.isYou ? .trailing : .leading)
                                if showEnglish && !line.english.isEmpty {
                                    Text(line.english).font(.caption).foregroundStyle(Color(p.secondaryText))
                                        .multilineTextAlignment(line.isYou ? .trailing : .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: line.isYou ? .trailing : .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Plays this line")
                    }
                }
            }
        }
        .navigationTitle("Conversation")
        .onAppear {
            guard !counted else { return }
            counted = true
            model.updateProfile { ConversationReplay.recordReplay(profile: &$0) }
            model.checkMilestones()
        }
    }
}

// MARK: - 9. Word notes (inside the Word Library)

struct WordNoteEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let itemId: String
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("My note (only on this device)", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onChange(of: text) { _, new in if new.count > WordNotes.maxLength { text = String(new.prefix(WordNotes.maxLength)) } }
                .accessibilityIdentifier("noteField-\(itemId)")
            HStack {
                Text("\(text.count)/\(WordNotes.maxLength)").font(.caption2).foregroundStyle(Color(p.secondaryText))
                Spacer()
                Button("Save note") {
                    model.updateProfile { WordNotes.set(text, for: itemId, profile: &$0) }
                    model.sfx(.select)
                    model.checkMilestones()
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .disabled(text == (model.profile.flatMap { WordNotes.note(itemId, in: $0) } ?? ""))
                .accessibilityIdentifier("saveNote-\(itemId)")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = model.profile.flatMap { WordNotes.note(itemId, in: $0) } ?? ""
        }
    }
}

// MARK: - 5 + 13. Stats additions

struct ReviewForecastSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        if let prof = model.profile {
            let f = ReviewForecast.make(prof, now: Date())
            Section {
                Label("\(f.dueNow) ready now", systemImage: "clock.badge.checkmark")
                Label("\(f.tomorrow) more by tomorrow night", systemImage: "moon.stars")
                Label("\(f.nextSevenDays) in the next 7 days", systemImage: "calendar")
                if f.dueNow > 0 {
                    Button("Review now") { model.sheet = .review }.accessibilityIdentifier("forecastReview")
                }
            } header: { Text("Coming up for review") } footer: {
                Text("Words come back just before you'd forget them. This language only.")
            }
        }
    }
}

struct MonthCalendarSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        if let prof = model.profile {
            let days = PlayerStats.lastMonth(prof, now: Date())
            Section {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(days) { d in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(shade(d.intensity))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(p.secondaryText).opacity(0.35)))
                            .aspectRatio(1, contentMode: .fit)
                            .accessibilityElement()
                            .accessibilityLabel("\(d.date.formatted(.dateTime.month(.wide).day())): \(d.activities) activities, \(Int(d.minutes.rounded())) minutes")
                    }
                }
                .padding(.vertical, 4)
                HStack(spacing: 6) {
                    Text("Less").font(.caption2)
                    ForEach(0..<4) { RoundedRectangle(cornerRadius: 3).fill(shade($0)).frame(width: 14, height: 14) }
                    Text("More").font(.caption2)
                }
                .accessibilityHidden(true)
            } header: { Text("Last 30 days: \(PlayerStats.activeDays(days)) days active") } footer: {
                Text("Each square is a day, oldest first. Days off are fine: nothing is lost.")
            }
        }
    }

    private func shade(_ i: Int) -> Color {
        i == 0 ? Color(p.surface) : Color(p.accent).opacity([0, 0.35, 0.65, 1][i])
    }
}

// MARK: - 10. Pinned languages

struct PinnedLanguagesCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    var body: some View {
        if let prof = model.profile {
            let pins = PinnedLanguages.pinned(prof)
            let rows = pins.compactMap { id in model.courseSummaries.first { $0.courseId == id } }
            if !rows.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Pinned", systemImage: "pin.fill").font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("section-pinned")
                        ForEach(rows) { s in
                            LanguageRow(summary: s) { model.chooseLanguage(s.courseId) }
                        }
                    }
                }
            }
        }
    }
}

struct PinButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let prof = model.profile {
            let pinned = PinnedLanguages.pinned(prof).contains(prof.courseId)
            Button {
                model.updateProfile { p in let id = p.courseId; PinnedLanguages.toggle(id, profile: &p) }
                model.toast = pinned ? "Unpinned from the main menu" : "Pinned to the top of the main menu"
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(pinned ? "Unpin \(model.languageName)" : "Pin \(model.languageName) to the main menu")
            .accessibilityIdentifier("pinLanguage")
        }
    }
}

// MARK: - 14. Achievement progress

struct AchievementProgressBar: View {
    @Environment(\.palette) var p
    let progress: AchievementProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: progress.fraction).tint(Color(p.accent))
            Text("\(progress.current) of \(progress.target)").font(.caption2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.current) of \(progress.target)")
    }
}
