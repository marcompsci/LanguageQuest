import SwiftUI
import LQCore

/// A seed that changes each play but is stable within a session of the view.
private func freshSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max) }

// MARK: - Treasure card

struct TreasureCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let treasure: WordTreasure
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 12) {
                Text("¡Palabra perdida!").font(.caption.bold()).foregroundStyle(Color(p.secondaryText))
                Text(treasure.emoji).font(.system(size: 64)).accessibilityHidden(true)
                HStack {
                    Text(model.text(treasure.spanish)).font(.title.bold())
                    SpeakerButton(text: treasure.spanish)
                }
                Text(treasure.english).font(.title3)
                Text(treasure.fact).font(.subheadline).multilineTextAlignment(.center)
                let found = model.profile?.extrasOrEmpty.treasuresFound.count ?? 0
                Text("Treasure book: \(found)/\(StarterVillage.treasures.count)").font(.footnote.bold())
                Button("Keep exploring", action: onClose).buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("closeTreasure")
            }
            .padding(22)
            .background(Color(p.dialogueBox), in: RoundedRectangle(cornerRadius: 22))
            .padding(28)
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Games hub

struct GamesHubView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile, let prog = model.progression {
                    let extras = prof.extrasOrEmpty
                    Section {
                        ForEach(BattleRoster.opponents) { o in
                            let open = BattleRoster.isUnlocked(o, progress: prof.progress, progression: prog)
                            Button { model.sheet = .battle(o.id) } label: {
                                gameRow(icon: "bolt.fill", title: "\(o.name): \(o.title)",
                                        detail: open ? stars(extras.battleStars[o.id] ?? 0)
                                                     : (o.unitOrder.map { "Finish Unit \($0) to unlock" } ?? "Finish all units to unlock"),
                                        locked: !open)
                            }
                            .disabled(!open)
                        }
                    } header: { Text("Word Battles") } footer: {
                        Text("Friendly duels: answer to charge your spark. Mistakes never cost points, only the spark you'd have gained. Or challenge them by talking to them in the village.")
                    }
                    Section("Puzzles and mini-games") {
                        Button { model.sheet = .scramble } label: {
                            gameRow(icon: "textformat.abc", title: "Word Scramble (Profe Sol)", detail: stars(extras.scrambleBestStars), locked: false)
                        }
                        .accessibilityIdentifier("scrambleGame")
                        let marketOpen = prog.library.units.first { $0.order == 3 }.map { prog.isUnitUnlocked($0, prof.progress, plan: model.plan) } ?? false
                        Button { model.sheet = .market } label: {
                            gameRow(icon: "cart.fill", title: "Market Rush (Señora Ana)",
                                    detail: marketOpen ? stars(extras.marketBestStars) : "Opens with Unit 3", locked: !marketOpen)
                        }
                        .disabled(!marketOpen)
                        .accessibilityIdentifier("marketGame")
                    }
                    Section("Exploration") {
                        let found = extras.treasuresFound
                        Label("Treasure book: \(found.count)/\(StarterVillage.treasures.count) lost words", systemImage: "sparkles")
                        ForEach(StarterVillage.treasures) { t in
                            if found.contains(t.id) {
                                HStack { Text(t.emoji); Text(model.text(t.spanish)).bold(); Text("= \(t.english)") }
                            }
                        }
                        if found.count < StarterVillage.treasures.count {
                            Text("Look for sparkles around the village and press A next to them.").font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Games")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func gameRow(icon: String, title: String, detail: String, locked: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: locked ? "lock.fill" : icon).frame(width: 28).foregroundStyle(Color(p.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(Color(p.secondaryText))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stars(_ n: Int) -> String {
        n == 0 ? "Not played yet" : String(repeating: "★", count: n) + String(repeating: "☆", count: 3 - n) + " best"
    }
}

// MARK: - Word Battle

struct BattleView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    let opponentId: String
    @State private var battle: WordBattle?
    @State private var lastTurn: BattleTurn?
    @State private var picked: Int?
    @State private var started = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                if let b = battle {
                    VStack(spacing: 16) {
                        meters(b)
                        if let q = b.current {
                            question(q, b)
                        } else {
                            results(b)
                        }
                        Spacer()
                    }
                    .padding(20)
                }
            }
            .navigationTitle(battle?.opponent.title ?? "Word Battle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Leave") { dismiss() } } }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        guard battle == nil, let lib = model.library, let prof = model.profile,
              let o = BattleRoster.opponents.first(where: { $0.id == opponentId }) else { return }
        battle = WordBattle(opponent: o, library: lib, profile: prof, seed: freshSeed())
        started = Date()
    }

    private func meters(_ b: WordBattle) -> some View {
        let maxSpark = Double(WordBattle.rounds * 30)
        return VStack(spacing: 10) {
            meter(label: model.profile?.nickname.isEmpty == false ? model.profile!.nickname : "You",
                  value: Double(b.playerSpark), max: maxSpark, color: Color(p.accent))
            meter(label: b.opponent.name, value: Double(b.rivalSpark), max: maxSpark, color: Color(p.retry))
            HStack {
                Text("Round \(min(b.round + 1, WordBattle.rounds)) of \(WordBattle.rounds)")
                Spacer()
                if b.combo >= 2 { Label("Combo ×\(b.combo)", systemImage: "flame.fill") }
            }
            .font(.caption.bold())
        }
    }

    private func meter(label: String, value: Double, max: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label).font(.subheadline.bold()); Spacer(); Text("\(Int(value)) ⚡").font(.subheadline.monospacedDigit()) }
            ProgressView(value: min(value, max), total: max).tint(color)
        }
        .accessibilityElement(children: .combine)
    }

    private func question(_ q: BattleQuestion, _ b: WordBattle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(q.spanishPrompt ? "What does it mean?" : "How do you say it in Spanish?").font(.headline)
            HStack {
                Text(model.text(q.prompt)).font(.largeTitle.bold())
                Spacer()
                if q.spanishPrompt { SpeakerButton(text: q.prompt) }
            }
            ForEach(q.options.indices, id: \.self) { i in
                Button { answer(i) } label: {
                    HStack {
                        Text(model.text(q.options[i])).font(.title3)
                        Spacer()
                        if picked != nil && i == q.answerIndex { Image(systemName: "checkmark").accessibilityLabel("Right answer") }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(picked != nil)
                .accessibilityIdentifier("battleOption\(i)")
            }
            if let t = lastTurn, picked != nil {
                Label(t.correct ? "+\(t.playerGain) spark!" : "Coach: \(t.coachTip)",
                      systemImage: t.correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(Color(t.correct ? p.success : p.retry))
                    .font(.headline)
                Button("Next round") { picked = nil; lastTurn = nil; battle = advance(b) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("nextRound")
            }
        }
    }

    @State private var pending: WordBattle?
    private func advance(_ b: WordBattle) -> WordBattle { pending ?? b }

    private func answer(_ i: Int) {
        guard var b = battle, let lib = model.library, let q = b.current else { return }
        let variant = model.profile?.variant ?? "es-419"
        let turn = b.answer(i, library: lib, variant: variant)
        model.updateProfile { prof in
            PracticeRecorder.record(itemId: q.itemId, outcome: ReviewOutcome(correct: turn?.correct ?? false,
                                    responseSeconds: Date().timeIntervalSince(started)), track: .comprehension, profile: &prof, now: Date())
        }
        started = Date()
        model.sfx(turn?.correct == true ? .battleHit : .retry)
        picked = i
        lastTurn = turn
        pending = b
        if b.finished { finish(b) }
    }

    private func finish(_ b: WordBattle) {
        model.updateProfile { prof in
            prof.updateExtras { e in e.battleStars[b.opponent.id] = max(e.battleStars[b.opponent.id] ?? 0, b.stars) }
            if b.playerWon { prof.rewards.xp += 15 }
        }
        model.sfx(b.playerWon ? .reward : .select)
    }

    private func results(_ b: WordBattle) -> some View {
        VStack(spacing: 14) {
            Text(b.playerWon ? "¡Ganaste!" : "¡Buen duelo!").font(.largeTitle.bold())
            Text(b.playerWon ? "You won the duel against \(b.opponent.name)." : "\(b.opponent.name) won this time. Every word you missed comes back in Review.")
                .multilineTextAlignment(.center)
            Text(String(repeating: "★", count: b.stars) + String(repeating: "☆", count: 3 - b.stars)).font(.largeTitle)
                .accessibilityLabel("\(b.stars) of 3 stars")
            Text("\(b.correctCount) of \(b.questions.count) right").font(.headline)
            Button("Rematch") { battle = nil; pending = nil; setup() }.buttonStyle(SecondaryButtonStyle())
            Button("Back to the village") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Word Scramble

struct ScrambleView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: WordScramble?
    @State private var chosen: [Int] = []
    @State private var feedback: String?
    @State private var revealed: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                if let g = game {
                    if let pz = g.current {
                        puzzle(pz, g)
                    } else {
                        VStack(spacing: 14) {
                            Text("¡Muy bien!").font(.largeTitle.bold())
                            Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars)).font(.largeTitle)
                            Text("\(g.firstTryCorrect) of \(g.puzzles.count) on the first try")
                            Button("Play again") { game = nil; setup() }.buttonStyle(SecondaryButtonStyle())
                            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                        }.padding(24)
                    }
                }
            }
            .navigationTitle("Word Scramble")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        guard game == nil, let lib = model.library, let prof = model.profile else { return }
        game = WordScramble(library: lib, profile: prof, seed: freshSeed())
        chosen = []; feedback = nil; revealed = nil
    }

    private func puzzle(_ pz: ScramblePuzzle, _ g: WordScramble) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(g.index), total: Double(g.puzzles.count))
            Text("Unscramble the Spanish for:").font(.headline)
            Text(pz.english).font(.title.bold())
            if let a = pz.article { Text("Hint: it starts with “\(a)”").font(.subheadline) }
            let word = String(chosen.map { pz.letters[$0] })
            Text(word.isEmpty ? " " : word)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(word.isEmpty ? "Empty" : "Your word: \(word)")
            FlowRow(spacing: 8) {
                ForEach(pz.letters.indices, id: \.self) { i in
                    Button(String(pz.letters[i]).uppercased()) {
                        chosen.append(i)
                        model.sfx(.select)
                    }
                    .font(.title2.bold())
                    .frame(width: 50, height: 50)
                    .background(Color(p.accent).opacity(chosen.contains(i) ? 0.15 : 1), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color(p.onAccent))
                    .disabled(chosen.contains(i))
                    .accessibilityLabel("Letter \(String(pz.letters[i]))")
                }
            }
            if let f = feedback { Text(f).font(.headline).foregroundStyle(Color(p.retry)) }
            if let r = revealed { Text("It was: \(r)").font(.headline) }
            HStack {
                Button("Undo") { if !chosen.isEmpty { chosen.removeLast() } }.buttonStyle(SecondaryButtonStyle())
                Button("Check") { check(word, pz) }.buttonStyle(PrimaryButtonStyle())
                    .disabled(chosen.count != pz.letters.count)
                    .accessibilityIdentifier("scrambleCheck")
            }
            Button("Skip this word") {
                revealed = pz.answer
                game?.skip()
                chosen = []
                feedback = nil
            }.font(.subheadline)
            Spacer()
        }
        .padding(20)
    }

    private func check(_ word: String, _ pz: ScramblePuzzle) {
        guard var g = game else { return }
        let ok = g.submit(word)
        game = g
        if ok {
            model.sfx(.correct)
            model.say(VText(pz.answer))
            model.updateProfile { PracticeRecorder.record(itemId: pz.itemId, outcome: ReviewOutcome(correct: true, attempts: 1),
                                                          track: .guidedProduction, profile: &$0, now: Date()) }
            if g.finished { model.updateProfile { $0.updateExtras { $0.scrambleBestStars = max($0.scrambleBestStars, g.stars) } } }
            chosen = []; feedback = nil; revealed = nil
        } else {
            model.sfx(.retry)
            feedback = "Not quite. Try another order!"
            chosen = []
        }
    }
}

// MARK: - Market Rush

struct MarketRushView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var game: MarketRush?
    @State private var basket: [String] = []
    @State private var coins: [Int] = []
    @State private var paying = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                if let g = game, let lib = model.library {
                    if let o = g.current {
                        ScrollView { order(o, g, lib).padding(20) }
                    } else {
                        VStack(spacing: 14) {
                            Text("¡Gracias por su compra!").font(.largeTitle.bold()).multilineTextAlignment(.center)
                            Text(String(repeating: "★", count: g.stars) + String(repeating: "☆", count: 3 - g.stars)).font(.largeTitle)
                            Button("Play again") { game = nil; setup() }.buttonStyle(SecondaryButtonStyle())
                            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                        }.padding(24)
                    }
                }
            }
            .navigationTitle("Market Rush")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear(perform: setup)
    }

    private var currency: Currency? { model.variant?.currency }

    private func money(_ n: Int) -> String {
        guard let c = currency else { return "\(n)" }
        return "\(n) \(n == 1 ? c.singular : c.plural)"
    }

    private func setup() {
        guard game == nil, let lib = model.library else { return }
        game = MarketRush(library: lib, seed: freshSeed())
        basket = []; coins = []; paying = false; message = nil
    }

    private func name(_ id: String, _ lib: ContentLibrary) -> String { lib.item(id).map { model.text($0.target) } ?? id }

    private func order(_ o: MarketOrder, _ g: MarketRush, _ lib: ContentLibrary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: Double(g.index), total: Double(g.orders.count))
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label("La lista de compras", systemImage: "list.bullet.clipboard").font(.headline)
                    ForEach(o.wanted, id: \.itemId) { w in
                        HStack { Text("• \(name(w.itemId, lib))").font(.title3); Spacer(); SpeakerButton(text: VText(name(w.itemId, lib))) }
                    }
                }
            }
            if !paying {
                Text("Tap the items on the list:").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(o.stall, id: \.itemId) { good in
                        let item = lib.item(good.itemId)
                        let inBasket = basket.contains(good.itemId)
                        Button {
                            if inBasket { basket.removeAll { $0 == good.itemId } } else { basket.append(good.itemId) }
                            model.sfx(.select)
                        } label: {
                            VStack(spacing: 4) {
                                Text(item?.picture ?? "🛒").font(.largeTitle).accessibilityHidden(true)
                                Text(money(good.price)).font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity, minHeight: 86)
                            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(inBasket ? Color(p.accent) : .clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        // VoiceOver reads the picture's description, not the Spanish word, so the reading task stays a reading task.
                        .accessibilityLabel("\(item?.altText ?? item?.english ?? "") , \(money(good.price))")
                        .accessibilityAddTraits(inBasket ? .isSelected : [])
                    }
                }
                Button("Check my basket") {
                    if g.checkBasket(basket) {
                        model.sfx(.correct); paying = true; message = nil
                        for id in basket {
                            model.updateProfile { PracticeRecorder.record(itemId: id, outcome: ReviewOutcome(correct: true), track: .comprehension, profile: &$0, now: Date()) }
                        }
                    } else {
                        model.sfx(.retry); game?.noteMistake(); message = "Check the list again: one item is missing or extra."
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(basket.isEmpty)
                .accessibilityIdentifier("checkBasket")
            } else {
                Text("Pay exactly \(money(o.total)). ¿Cuánto cuesta en total?").font(.headline)
                Text("Paid: \(money(coins.reduce(0, +)))").font(.title2.bold())
                HStack(spacing: 10) {
                    ForEach(MarketRush.coins, id: \.self) { c in
                        Button("\(c)") { coins.append(c); model.sfx(.coin) }
                            .font(.title2.bold())
                            .frame(width: 60, height: 60)
                            .background(Color(RGB(0xF2C230)), in: Circle())
                            .foregroundStyle(Color(RGB(0x2B2340)))
                            .accessibilityLabel("Coin of \(money(c))")
                    }
                }
                HStack {
                    Button("Start over") { coins = [] }.buttonStyle(SecondaryButtonStyle())
                    Button("Pay") {
                        if g.checkPayment(coins) {
                            model.sfx(.reward)
                            var next = g
                            next.completeRound()
                            game = next
                            if next.finished { model.updateProfile { $0.updateExtras { $0.marketBestStars = max($0.marketBestStars, next.stars) } } }
                            basket = []; coins = []; paying = false; message = nil
                        } else {
                            model.sfx(.retry); game?.noteMistake()
                            message = coins.reduce(0, +) > o.total ? "That's too much. Start over and try again." : "Not enough yet. Add more coins."
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("payButton")
                }
            }
            if let m = message { Label(m, systemImage: "arrow.uturn.backward.circle.fill").foregroundStyle(Color(p.retry)) }
        }
    }
}

// MARK: - Phrasebook

struct PhrasebookView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            List {
                if let prof = model.profile, let lib = model.library {
                    let entries = Phrasebook.entries(prof, library: lib, query: query, includeUnmet: showAll)
                    Toggle("Show words I haven't met yet", isOn: $showAll)
                    if entries.isEmpty {
                        Text(query.isEmpty ? "Words appear here as you meet them in quests." : "No matches.")
                    }
                    ForEach(lib.units) { u in
                        let inUnit = entries.filter { $0.unitOrder == u.order }
                        if !inUnit.isEmpty {
                            Section("Unit \(u.order): \(u.title)") {
                                ForEach(inUnit) { e in row(e) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search Spanish or English")
            .navigationTitle("Phrasebook")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ e: PhrasebookEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let pic = e.item.picture { Text(pic).font(.title2).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.text(e.item.target)).font(.headline)
                Text(e.item.english).font(.subheadline)
                if !e.otherRegions.isEmpty {
                    Text(e.otherRegions.map { "\($0.variantName): \($0.form)" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                if let n = e.item.note { Text(n).font(.caption).italic() }
            }
            Spacer()
            VStack(spacing: 6) {
                SpeakerButton(text: e.item.target)
                Text(e.level.label).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(p.accent).opacity(0.15), in: Capsule())
            }
        }
        .accessibilityElement(children: .contain)
    }
}
