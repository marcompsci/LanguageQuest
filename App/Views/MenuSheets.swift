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

struct FlashcardsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var deck: [Flashcard] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var knew = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if deck.isEmpty {
                    ProgressView()
                } else if index >= deck.count {
                    Spacer()
                    Text("Deck done!").font(.largeTitle.bold())
                    Text("You knew \(knew) of \(deck.count). The others will come back soon in reviews.")
                        .multilineTextAlignment(.center)
                    Button("Another deck") { build() }.buttonStyle(PrimaryButtonStyle())
                    Spacer()
                } else {
                    let card = deck[index]
                    Text("Card \(index + 1) of \(deck.count)").font(.caption).foregroundStyle(Color(p.secondaryText))
                    Button { withAnimation(.easeInOut(duration: 0.2)) { flipped.toggle() } } label: {
                        VStack(spacing: 12) {
                            if let pic = card.picture { Text(pic).font(.system(size: 64)).accessibilityHidden(true) }
                            if flipped {
                                Text(card.back).font(.title.bold())
                                Text(model.display(card.front)).font(.title3).foregroundStyle(Color(p.secondaryText))
                            } else {
                                Text(model.display(card.front)).font(.title.bold())
                                Text("Tap to flip").font(.caption).foregroundStyle(Color(p.secondaryText))
                            }
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(flipped ? "\(model.text(card.front)) means \(card.back)" : model.text(card.front))
                    .accessibilityHint(flipped ? "" : "Flips the card")
                    .accessibilityIdentifier("flashcard")
                    SpeakerButton(text: card.front)
                    if flipped {
                        HStack(spacing: 12) {
                            Button("Still learning") { answer(false) }.buttonStyle(SecondaryButtonStyle())
                            Button("I knew it") { answer(true) }.buttonStyle(PrimaryButtonStyle())
                                .accessibilityIdentifier("knewIt")
                        }
                    }
                    Spacer()
                }
            }
            .padding(20)
            .background(ThemedBackground())
            .navigationTitle("Flashcards")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if deck.isEmpty { build() } }
        }
    }

    private func build() {
        guard let p = model.profile, let lib = model.library else { return }
        deck = FlashcardDeck.build(p, library: lib, now: Date(), seed: UInt64.random(in: 1...UInt64.max))
        index = 0; knew = 0; flipped = false
        if let first = deck.first { model.say(first.front) }
    }

    private func answer(_ knewIt: Bool) {
        let card = deck[index]
        model.updateProfile { FlashcardDeck.record(card, knewIt: knewIt, profile: &$0, now: Date()) }
        model.sfx(knewIt ? .correct : .retry)
        if knewIt { knew += 1 }
        flipped = false
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
                            .font(.system(size: 96, weight: .bold))
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
                        Text(String(repeating: "★", count: d.stars) + String(repeating: "☆", count: 3 - d.stars)).font(.system(size: 48))
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
        }
    }
}
