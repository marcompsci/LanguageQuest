import SwiftUI
import LQCore

/// Every sheet in the app, presented from RootView (menu or village).
struct SheetRouter: View {
    let sheet: AppModel.Sheet

    var body: some View {
        switch sheet {
        case .quest(let id): QuestPlayerView(questId: id)
        case .journal: JournalView()
        case .bag: BagView()
        case .review: ReviewView()
        case .placement: PlacementView()
        case .mastery(let unitId): MasteryCheckView(unitId: unitId)
        case .parent: ParentAreaView()
        case .games: GamesHubView()
        case .battle(let id): BattleView(opponentId: id)
        case .scramble: ScrambleView()
        case .market: MarketRushView()
        case .phrasebook: PhrasebookView()
        case .languages: LanguagesView()
        case .settings: PlayerSettingsView()
        case .wardrobe: WardrobeView()
        case .flashcards: FlashcardsView()
        case .kana: KanaDojoView()
        case .bonus: BonusLessonView()
        case .writeOut: WriteOutView()
        case .trophies: TrophiesView()
        case .stats: StatsView()
        case .mistakes: MistakesView()
        case .echo: EchoView()
        case .memory: MemoryMatchView()
        case .bee: SpellingBeeView()
        case .privacy: PrivacyPolicyView()
        case .words: WordLibraryView()
        case .starredPractice: FlashcardsView(starredOnly: true)
        case .builder: SentenceBuilderView()
        case .quizzes: QuizzesView()
        case .listenType: ListenTypeView()
        case .rightOrWrong: RightOrWrongView()
        }
    }
}

// MARK: - Language switcher

struct LanguagesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.courseSummaries) { s in LanguageRow(summary: s) }
                } footer: {
                    Text("Your quests, words and reviews are kept for each language. XP, items and badges are shared.")
                }
                if let lib = model.library, lib.course.variants.count > 1, let prof = model.profile {
                    Section("\(lib.course.displayLanguage) variety") {
                        ForEach(lib.course.variants) { v in
                            Button {
                                model.updateProfile { $0.variant = v.id }
                            } label: {
                                HStack {
                                    Text("\(v.flagEmoji) \(v.name)")
                                    Spacer()
                                    if prof.variant == v.id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }
                            }
                            .accessibilityIdentifier("variant-\(v.id)")
                        }
                    }
                }
            }
            .navigationTitle("Languages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Explorer settings (no gate: nothing here touches data, money or permissions)

struct PlayerSettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile, let lib = model.library {
                    Section("Learning") {
                        Picker("Language", selection: Binding(get: { model.activeCourseId }, set: { model.switchCourse(to: $0) })) {
                            ForEach(model.courses, id: \.id) { c in Text(c.displayLanguage).tag(c.id) }
                        }
                        if lib.course.variants.count > 1 {
                            Picker("Variety", selection: binding(\.variant, prof)) {
                                ForEach(lib.course.variants) { v in Text("\(v.flagEmoji) \(v.name)").tag(v.id) }
                            }
                        }
                        if lib.course.hasRomanization {
                            Toggle("Show pronunciation under \(lib.course.displayLanguage)", isOn: Binding(get: { (model.profile ?? prof).settings.romanizationOn },
                                                                               set: { v in model.updateProfile { $0.settings.showRomanization = v } }))
                        }
                        Toggle("English subtitles in conversations", isOn: setting(\.subtitles, prof))
                        Toggle("Read instructions aloud", isOn: setting(\.readAloudInstructions, prof))
                    }
                    Section("Sound") {
                        Toggle("Music", isOn: setting(\.music, prof))
                        VStack(alignment: .leading) {
                            Text("Music volume")
                            Slider(value: Binding(get: { (model.profile ?? prof).settings.musicLevel },
                                                  set: { v in model.updateProfile { $0.settings.musicVolume = v } }), in: 0...1)
                        }
                        Toggle("Sound effects", isOn: setting(\.soundEffects, prof))
                        VStack(alignment: .leading) {
                            Text("Voice volume")
                            Slider(value: setting(\.voiceVolume, prof), in: 0...1)
                        }
                        VStack(alignment: .leading) {
                            Text("Speaking speed")
                            Slider(value: setting(\.speechRate, prof), in: 0.3...0.55)
                        }
                        VoiceStatusRow(language: lib.course.displayLanguage, variant: lib.course.variant(prof.variant))
                    }
                    Section("Look and comfort") {
                        Picker("Look", selection: binding(\.theme, prof)) {
                            Text("Playful").tag(ThemeKind.playful)
                            Text("Explorer").tag(ThemeKind.explorer)
                        }
                        Picker("Text size", selection: setting(\.textScale, prof)) {
                            Text("Normal").tag(1.0)
                            Text("Larger").tag(1.15)
                        }
                        Toggle("Reduce motion", isOn: setting(\.reducedMotion, prof))
                        Toggle("Easy-read text (wider spacing, higher contrast)", isOn: Binding(get: { (model.profile ?? prof).settings.easyReadOn },
                                                                                        set: { v in model.updateProfile { $0.settings.easyRead = v } }))
                            .accessibilityIdentifier("easyReadToggle")
                        Toggle("High-contrast colors (black and white)", isOn: Binding(get: { (model.profile ?? prof).settings.highContrastOn },
                                                                                   set: { v in model.updateProfile { $0.settings.highContrast = v } }))
                            .accessibilityIdentifier("highContrastToggle")
                        Toggle("Arrow pad on the right (left-handed)", isOn: Binding(get: { (model.profile ?? prof).settings.leftHandedOn },
                                                                                 set: { v in model.updateProfile { $0.settings.leftHanded = v } }))
                            .accessibilityIdentifier("leftHandedToggle")
                    }
                    Section { EmptyView() } footer: {
                        Text("Break reminders, speech checking, purchases and deleting data are in the Parents area.")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onDisappear { model.syncMusic() }
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<PlayerProfile, T>, _ fallback: PlayerProfile) -> Binding<T> {
        Binding(get: { (model.profile ?? fallback)[keyPath: kp] }, set: { v in model.updateProfile { $0[keyPath: kp] = v }; model.syncMusic() })
    }

    private func setting<T>(_ kp: WritableKeyPath<LearnerSettings, T>, _ fallback: PlayerProfile) -> Binding<T> {
        Binding(get: { (model.profile ?? fallback).settings[keyPath: kp] }, set: { v in model.updateProfile { $0.settings[keyPath: kp] = v }; model.syncMusic() })
    }
}

// MARK: - Wardrobe

struct WardrobeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let prof = model.profile {
                    VStack(spacing: 16) {
                        AvatarEditor(avatar: Binding(get: { model.profile?.avatar ?? prof.avatar },
                                                     set: { a in model.updateProfile { $0.avatar = a } }))
                        let owned = Catalog.cosmetics.filter { prof.rewards.ownedCosmetics.contains($0.id) }
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Items you've earned").font(.headline)
                                if owned.isEmpty { Text("Finish quests to earn hats and accessories.") }
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
                                            Text(c.name)
                                            Spacer()
                                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        }
                                    }
                                    .accessibilityValue(on ? "Wearing" : "Not wearing")
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(ThemedBackground())
            .navigationTitle("Wardrobe")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Flashcards

/// A flashcard you answer by picking its meaning from four choices. Flipping is
/// still allowed as a peek; a peeked card is then self-rated.
struct ChoiceFlashcard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let card: Flashcard
    let choices: FlashcardChoices
    /// Romanization line under the word (nil = none).
    var romanized: String?
    var compact = false
    /// Called once with whether the learner knew it.
    let onAnswer: (Bool) -> Void
    @State private var picked: Int?
    @State private var peeked = false

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { peeked.toggle() } } label: {
                VStack(spacing: 6) {
                    if let pic = card.picture { Text(pic).font(.system(size: compact ? 40 : 56)).accessibilityHidden(true) }
                    Text(card.front.base).font(compact ? .title2.bold() : .title.bold())
                    if let r = romanized { Text(r).font(.subheadline).foregroundStyle(Color(p.secondaryText)) }
                    if peeked && picked == nil {
                        Text(card.back).font(.headline).foregroundStyle(Color(p.accent))
                    } else if picked == nil {
                        Text("Pick the meaning · tap to peek").font(.caption2).foregroundStyle(Color(p.secondaryText))
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: compact ? 110 : 180)
                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(p.accent).opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(peeked ? "\(card.front.base) means \(card.back)" : card.front.base)
            .accessibilityHint(picked == nil ? "Pick its meaning below, or tap to peek" : "")
            .accessibilityIdentifier("flashcard")

            if peeked && picked == nil {
                HStack(spacing: 10) {
                    Button("Still learning") { finish(false) }.buttonStyle(SecondaryButtonStyle())
                    Button("I knew it") { finish(true) }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("knewIt")
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(choices.options.enumerated()), id: \.offset) { i, o in
                        Button { pick(i) } label: {
                            HStack(spacing: 6) {
                                if picked != nil, i == choices.answerIndex { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                                else if picked == i { Image(systemName: "xmark.circle.fill").accessibilityHidden(true) }
                                Text(o).font(.subheadline.bold()).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: compact ? 48 : 58)
                            .padding(.horizontal, 6)
                            .background(fill(i), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                        .accessibilityValue(picked == nil ? "" : (i == choices.answerIndex ? "Correct answer" : (picked == i ? "Your answer" : "")))
                        .accessibilityIdentifier("flash-option-\(i)")
                    }
                }
            }
        }
    }

    private func fill(_ i: Int) -> Color {
        guard let pk = picked else { return Color(p.accent).opacity(0.12) }
        if i == choices.answerIndex { return Color.green.opacity(0.35) }
        if i == pk { return Color.red.opacity(0.30) }
        return Color(p.accent).opacity(0.06)
    }

    private func pick(_ i: Int) {
        picked = i
        let ok = i == choices.answerIndex
        model.sfx(ok ? .correct : .retry)
        onAnswer(ok)
    }

    private func finish(_ knew: Bool) {
        picked = knew ? choices.answerIndex : -1
        onAnswer(knew)
    }
}

struct FlashcardsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var deck: [Flashcard] = []
    @State private var index = 0
    @State private var answered: Bool?
    @State private var knew = 0
    @State private var seed: UInt64 = 1
    @State private var built = false
    /// Practice only the words the explorer starred in the Word Library.
    var starredOnly = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if deck.isEmpty && built {
                    Spacer()
                    Text("No starred words yet. Tap ☆ next to a word in the Word Library to add it.").multilineTextAlignment(.center)
                    Spacer()
                } else if deck.isEmpty {
                    ProgressView()
                } else if index >= deck.count {
                    Spacer()
                    Text("Deck done!").font(.largeTitle.bold())
                    Text("You knew \(knew) of \(deck.count). The others will come back soon in reviews.")
                        .multilineTextAlignment(.center)
                    Button("Another deck") { build() }.buttonStyle(PrimaryButtonStyle())
                    Spacer()
                } else if let lib = model.library {
                    let card = deck[index]
                    Text("Card \(index + 1) of \(deck.count)").font(.caption).foregroundStyle(Color(p.secondaryText))
                    ChoiceFlashcard(card: card, choices: FlashcardChoices.make(for: card, library: lib, seed: seed &+ UInt64(index)),
                                    romanized: (model.profile?.settings.romanizationOn ?? true) ? lib.course.romanize(card.front.base) : nil) { ok in
                        model.updateProfile { FlashcardDeck.record(card, knewIt: ok, profile: &$0, now: Date()) }
                        if ok { knew += 1; model.record(.flashcardRight) }
                        answered = ok
                    }
                    .id("\(seed)-\(index)")
                    HStack {
                        SpeakerButton(text: card.front)
                        Spacer()
                        if let a = answered {
                            Text(a ? "Nice!" : "It'll come back soon.").font(.headline)
                            Button("Next") { next() }.buttonStyle(PrimaryButtonStyle())
                                .accessibilityIdentifier("flashNext")
                        }
                    }
                    Spacer()
                }
            }
            .padding(20)
            .background(ThemedBackground())
            .navigationTitle(starredOnly ? "Starred words" : "Flashcards")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if deck.isEmpty { build() } }
        }
    }

    private func build() {
        guard let p = model.profile, let lib = model.library else { return }
        seed = UInt64.random(in: 1...UInt64.max / 2)
        deck = starredOnly ? StarredWords.deck(p, library: lib, now: Date(), seed: seed) : FlashcardDeck.build(p, library: lib, now: Date(), seed: seed)
        built = true
        index = 0; knew = 0; answered = nil
        if let first = deck.first { model.say(first.front) }
    }

    private func next() {
        answered = nil
        index += 1
        if index < deck.count { model.say(deck[index].front) }
    }
}

// MARK: - Kana Dojo

struct KanaDojoView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var dojo: KanaDojo?
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let d = dojo {
                    if let q = d.current {
                        Text("\(d.index + 1) of \(d.questions.count) · \(d.script == .hiragana ? "Hiragana" : "Katakana")")
                            .font(.caption).foregroundStyle(Color(p.secondaryText))
                        Text(q.readKana ? "How do you read this?" : "Which one says “\(q.romaji)”?").font(.headline)
                        Text(q.readKana ? q.kana : q.romaji)
                            .font(.system(size: 96, weight: .bold, design: .default)).dynamicTypeSize(.large) // a single big practice glyph; its romaji is spoken and shown in the options
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel(q.readKana ? "Kana character" : q.romaji)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                                Button(o) { pick(i, q) }
                                    .font(.title.bold())
                                    .buttonStyle(SecondaryButtonStyle())
                                    .accessibilityIdentifier("kana-option-\(i)")
                            }
                        }
                        if let f = feedback { Text(f).font(.headline) }
                    } else {
                        Spacer()
                        Text(String(repeating: "★", count: d.stars) + String(repeating: "☆", count: 3 - d.stars)).font(.largeTitle).accessibilityLabel("\(d.stars) of 3 stars")
                        Text("\(d.correct) of \(d.questions.count) right").font(.title2.bold())
                        Button("Hiragana again") { start(.hiragana) }.buttonStyle(PrimaryButtonStyle())
                        Button("Try katakana") { start(.katakana) }.buttonStyle(SecondaryButtonStyle())
                        Spacer()
                    }
                } else {
                    Spacer()
                    Text("Kana Dojo").font(.largeTitle.bold())
                    Text("Japanese uses two sound alphabets. Hiragana is for Japanese words; katakana is mostly for words from other languages. Practice reading them here.")
                        .multilineTextAlignment(.center)
                    if let best = model.profile?.extrasOrEmpty.kanaBestStars, best > 0 {
                        Text("Best: " + String(repeating: "★", count: best)).font(.headline)
                    }
                    Button("Start hiragana") { start(.hiragana) }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("kanaStart")
                    Button("Start katakana") { start(.katakana) }.buttonStyle(SecondaryButtonStyle())
                    Spacer()
                }
            }
            .padding(20)
            .background(ThemedBackground())
            .navigationTitle("Kana Dojo")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func start(_ s: KanaScript) {
        dojo = KanaDojo(script: s, seed: UInt64.random(in: 1...UInt64.max))
        feedback = nil
    }

    private func pick(_ i: Int, _ q: KanaQuestion) {
        guard var d = dojo else { return }
        let ok = d.answer(i)
        model.sfx(ok ? .correct : .retry)
        model.say(VText(q.kana))
        feedback = ok ? "Yes! \(q.kana) = \(q.romaji)" : "That one is \(q.kana) = \(q.romaji)"
        dojo = d
        if d.finished {
            let stars = d.stars
            model.updateProfile { $0.updateExtras { $0.kanaBestStars = max($0.kanaBestStars ?? 0, stars) } }
            model.record(.gamePlayed)
        }
    }
}

/// Shows which voice reads the lessons and how to get a smoother one.
struct VoiceStatusRow: View {
    let language: String
    let variant: LanguageVariant?
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let st = SpeechService.voiceStatus(for: variant) {
                Label("\(language) voice: \(st.name)", systemImage: st.natural ? "waveform" : "waveform.badge.exclamationmark")
                if st.natural {
                    Text("This is a high-quality voice.").font(.caption)
                } else {
                    Text("For a smoother, more natural voice, a grown-up can download an Enhanced or Premium \(language) voice (free): Settings › Accessibility › Read & Speak (or Spoken Content) › Voices.")
                        .font(.caption)
                }
            } else {
                Label("No \(language) voice on this device", systemImage: "speaker.slash")
                Text("iPhone has no voice for \(language) yet, so lessons read the Latin spelling with an English voice.").font(.caption)
            }
            Button("Test the voice") { model.say(VText(model.phrases.helloAgain.base)) }
                .font(.subheadline)
        }
    }
}

// MARK: - Bonus lesson

struct BonusLessonView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var lesson: BonusLesson?
    @State private var done = false
    @State private var correct = 0
    @State private var xp = 0

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                if done, let l = lesson {
                    VStack(spacing: 16) {
                        Image(systemName: "gift.fill").font(.system(size: 60)).accessibilityHidden(true)
                        Text(model.phrases.excellent).font(.largeTitle.bold())
                        Text("\(correct) of \(l.activities.count) right on the first try.")
                        Text(xp > 0 ? "+\(xp) bonus XP!" : "You already got today's bonus XP. Come back tomorrow for more!")
                            .font(.headline).multilineTextAlignment(.center)
                        Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(24)
                } else if let l = lesson {
                    VStack(spacing: 6) {
                        Text(l.title).font(.headline).padding(.top, 6)
                        ActivitySequence(activities: l.activities, onEach: { a, r in
                            model.complete(a, outcome: r.outcome, verified: r.verified)
                            if r.outcome.correct && r.outcome.attempts == 1 { correct += 1 }
                        }, onFinish: {
                            var gained = 0
                            model.updateProfile { gained = BonusLesson.claim(&$0, day: l.dayKey) }
                            xp = gained
                            model.sfx(.reward)
                            done = true
                            model.record(.bonusDone)
                        })
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Bonus lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                guard lesson == nil, let p = model.profile, let lib = model.library else { return }
                lesson = BonusLesson.build(p, library: lib, plan: model.plan, now: Date())
            }
        }
    }
}
