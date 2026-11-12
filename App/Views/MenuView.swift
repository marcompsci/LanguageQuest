import SwiftUI
import LQCore

/// Main menu: shown at launch. Players pick a language here, which opens that language's page.
struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @State private var phase = DayPhase.now()

    var body: some View {
        ZStack {
            ThemedBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        HamburgerMenu()
                    }
                    Text("Language Quest")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    if let prof = model.profile {
                        explorerCard(prof)
                        RecentLessonView()
                        bonusCard(prof)
                        DailyChallengesCard()
                        ForEach(CourseCategory.allCases, id: \.self) { section in
                            let rows = model.courseSummaries.filter { $0.category == section }
                            if !rows.isEmpty {
                                Card {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(section.title).font(.title3.bold())
                                            .accessibilityAddTraits(.isHeader)
                                            .accessibilityIdentifier("section-\(section.rawValue)")
                                        if section != .modern {
                                            Text(section == .african ? "Starter lessons: greetings, names, polite words and numbers."
                                                                     : "Starter lessons in languages from the ancient world.")
                                                .font(.caption).foregroundStyle(Color(p.secondaryText))
                                        }
                                        ForEach(rows) { s in
                                            LanguageRow(summary: s) { model.chooseLanguage(s.courseId) }
                                        }
                                    }
                                }
                            }
                        }
                        Text("Progress in each language is kept when you switch.")
                            .font(.caption).foregroundStyle(Color(p.secondaryText))
                        if model.save.profiles.count > 1 { explorersCard }
                    }
                }
                .padding(16)
            }
        }
        .onAppear { phase = DayPhase.now(); model.checkMilestones() }
    }

    private func bonusCard(_ prof: PlayerProfile) -> some View {
        let day = ActivityLog.dayKey(Date())
        let claimed = BonusLesson.claimed(prof, day: day)
        let flag = model.courseSummaries.first(where: \.isActive)?.flag ?? "🌐"
        return Button { model.sheet = .bonus } label: {
            HStack(spacing: 14) {
                Image(systemName: claimed ? "gift" : "gift.fill").font(.title)
                    .foregroundStyle(Color(p.accent)).frame(width: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bonus lesson").font(.headline)
                    Text("\(flag) \(model.languageName) · 6 quick activities").font(.subheadline)
                    Text(claimed ? "Today's bonus XP collected. You can still play!" : "+\(BonusLesson.bonusXP) bonus XP today")
                        .font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Color(p.secondaryText))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(p.accent).opacity(claimed ? 0.10 : 0.28), Color(p.surface)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bonusLesson")
    }

    private func explorerCard(_ prof: PlayerProfile) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(uiImage: PixelArt.avatarImage(prof.avatar, scale: 5))
                    .interpolation(.none)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(phase.greeting), \(prof.nickname.isEmpty ? "explorer" : prof.nickname)!").font(.headline)
                    LevelBadge(xp: prof.rewards.xp)
                    Text("\(prof.rewards.badges.count) badge\(prof.rewards.badges.count == 1 ? "" : "s") · \(prof.rewards.ownedCosmetics.count) item\(prof.rewards.ownedCosmetics.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var explorersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Explorers on this device").font(.headline)
                ForEach(model.save.profiles, id: \.id) { other in
                    Button { model.switchProfile(other.id) } label: {
                        HStack {
                            Image(uiImage: PixelArt.avatarImage(other.avatar, scale: 3)).interpolation(.none).accessibilityHidden(true)
                            Text(other.nickname.isEmpty ? "Explorer" : other.nickname)
                            Spacer()
                            if other.id == model.profile?.id { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Playing now") }
                        }
                    }
                }
            }
        }
    }
}

/// The page after choosing a language: Play, Today, Games and Flashcards.
/// Everything else lives in the ☰ menu at the top right.
struct LanguageHubView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            ThemedBackground()
            ScrollView {
                VStack(spacing: 16) {
                    topBar
                    if let prof = model.profile, let s = model.courseSummaries.first(where: \.isActive) {
                        VStack(spacing: 4) {
                            Text(s.flag).font(.system(size: 64)).accessibilityHidden(true)
                            Text(s.language).font(.system(size: 32, weight: .heavy, design: .rounded))
                                .accessibilityAddTraits(.isHeader)
                            Text(s.nativeName).font(.headline).foregroundStyle(Color(p.secondaryText))
                            ProgressView(value: s.fraction).tint(Color(p.accent)).padding(.horizontal, 40).padding(.top, 6)
                            Text("\(s.questsDone)/\(s.questsTotal) quests · \(s.wordsMet) words met")
                                .font(.caption).foregroundStyle(Color(p.secondaryText))
                        }
                        Button { model.play() } label: {
                            Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityLabel("Play: \(s.language) village")
                        .accessibilityIdentifier("playButton")
                        todayCard(prof)
                        LazyVGrid(columns: columns, spacing: 12) {
                            MenuTile(icon: "gamecontroller.fill", title: "Games", id: "menu-games") { model.sheet = .games }
                            MenuTile(icon: "rectangle.on.rectangle.angled", title: "Flashcards", id: "menu-flashcards") { model.sheet = .flashcards }
                            MenuTile(icon: "gift.fill", title: "Bonus lesson", id: "menu-bonus") { model.sheet = .bonus }
                            MenuTile(icon: "pencil.and.scribble", title: "Write Out", id: "menu-writeout") { model.sheet = .writeOut }
                            if model.library?.course.script == .kana {
                                MenuTile(icon: "character.ja", title: "Kana Dojo", id: "menu-kana") { model.sheet = .kana }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { model.openMenu() } label: {
                Label("Languages", systemImage: "chevron.left").font(.headline)
            }
            .accessibilityHint("Back to the main menu to choose a language")
            .accessibilityIdentifier("backToLanguages")
            Spacer()
            HamburgerMenu()
        }
    }

    private func todayCard(_ prof: PlayerProfile) -> some View {
        let t = TodaySummary.compute(prof, now: Date())
        let due = ReviewPlanner.dueItems(prof.knowledge, now: Date(), limit: 50).count
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Today", systemImage: "sun.max.fill").font(.headline)
                Text(t.message)
                if due > 0 {
                    Button { model.sheet = .review } label: {
                        Text("\(due) word\(due == 1 ? " is" : "s are") ready for a quick review")
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

/// ☰ at the top right: every screen that isn't on the language page.
struct HamburgerMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    var body: some View {
        Menu {
            Button { model.sheet = .review } label: { Label("Review", systemImage: "arrow.triangle.2.circlepath") }
            Button { model.sheet = .phrasebook } label: { Label("Phrasebook", systemImage: "character.book.closed.fill") }
            Button { model.sheet = .writeOut } label: { Label("Write Out", systemImage: "pencil.and.scribble") }
            Button { model.sheet = .mistakes } label: { Label("Mistakes notebook", systemImage: "exclamationmark.bubble") }
            Button { model.sheet = .trophies } label: { Label("Trophies", systemImage: "trophy.fill") }
            Button { model.sheet = .stats } label: { Label("My stats", systemImage: "chart.bar.fill") }
            Button { model.sheet = .bonus } label: { Label("Bonus lesson", systemImage: "gift.fill") }
            Button { model.sheet = .journal } label: { Label("Quest journal", systemImage: "book.closed.fill") }
            Button { model.sheet = .wardrobe } label: { Label("Wardrobe", systemImage: "tshirt.fill") }
            Button { model.sheet = .bag } label: { Label("Bag and badges", systemImage: "bag.fill") }
            Divider()
            Button { model.sheet = .settings } label: { Label("Settings", systemImage: "gearshape.fill") }
            Button { model.sheet = .parent } label: { Label("Parents", systemImage: "lock.shield") }
            Button { model.sheet = .privacy } label: { Label("Privacy policy", systemImage: "hand.raised.fill") }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title2.bold())
                .frame(width: 46, height: 46)
                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Menu")
        .accessibilityIdentifier("hamburgerMenu")
    }
}

struct MenuTile: View {
    @Environment(\.palette) var p
    let icon: String
    let title: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(Color(p.accent))
                Text(title).font(.subheadline.bold()).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// A flag, the language name and a progress bar.
struct LanguageRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let summary: CourseSummary
    /// Defaults to switching language in place (used by the switcher sheet).
    var action: (() -> Void)? = nil

    var body: some View {
        Button { if let action { action() } else { model.switchCourse(to: summary.courseId) } } label: {
            HStack(spacing: 12) {
                Text(summary.flag).font(.largeTitle)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(summary.language).font(.headline)
                        Text(summary.nativeName).font(.subheadline).foregroundStyle(Color(p.secondaryText))
                    }
                    ProgressView(value: summary.fraction).tint(Color(p.accent))
                    Text(summary.started ? "\(summary.questsDone)/\(summary.questsTotal) quests · \(summary.wordsMet) words met" : "Not started yet")
                        .font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right").foregroundStyle(Color(p.secondaryText))
                } else if summary.isActive {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color(p.accent))
                }
            }
            .padding(8)
            .background(summary.isActive ? Color(p.accent).opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.language). \(summary.started ? "\(summary.questsDone) of \(summary.questsTotal) quests done" : "Not started")")
        .accessibilityValue(summary.isActive ? "Learning now" : "")
        .accessibilityHint(action != nil ? "Opens \(summary.language)" : (summary.isActive ? "" : "Switches to \(summary.language)"))
        .accessibilityIdentifier("course-\(summary.courseId)")
    }
}

/// "Recent lesson" on the main menu: the last quest, a button to keep going,
/// and one quick flashcard from words practiced in earlier lessons.
struct RecentLessonView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @State private var seed = UInt64.random(in: 1...UInt64.max)
    @State private var answered: Bool?
    /// The card on screen stays put after answering (recording changes which word is due).
    @State private var shown: Flashcard?

    var body: some View {
        if let prof = model.profile,
           let r = RecentLessonCard.compute(prof, libraries: model.libraries, now: Date(), seed: seed) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Recent lesson", systemImage: "clock.arrow.circlepath").font(.headline)
                        Spacer()
                        Text(r.flag).font(.title2).accessibilityHidden(true)
                    }
                    Button { model.chooseLanguage(r.courseId) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.questTitle).font(.subheadline.bold())
                                Text(r.language).font(.caption).foregroundStyle(Color(p.secondaryText))
                            }
                            Spacer()
                            Text("Continue").font(.subheadline.bold())
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Continue \(r.language): \(r.questTitle)")
                    .accessibilityIdentifier("recentContinue")
                    if let card = shown ?? r.card { quickCard(card, courseId: r.courseId) }
                }
            }
        }
    }

    private func roman(_ v: VText, _ courseId: String) -> String? {
        guard model.profile?.settings.romanizationOn ?? true else { return nil }
        return model.libraries[courseId]?.course.romanize(v.base)
    }

    @ViewBuilder
    private func quickCard(_ card: Flashcard, courseId: String) -> some View {
        if let lib = model.libraries[courseId] {
            VStack(spacing: 10) {
                Text("Quick flashcard").font(.caption.bold()).foregroundStyle(Color(p.secondaryText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChoiceFlashcard(card: card, choices: FlashcardChoices.make(for: card, library: lib, seed: seed),
                                romanized: roman(card.front, courseId), compact: true) { ok in record(card, courseId, ok) }
                    .id("\(seed)-\(card.itemId)")
                if let a = answered {
                    HStack {
                        Text(a ? "Nice! See you in your next review." : "No problem, it'll come back soon.").font(.subheadline)
                        Spacer()
                        Button("Another") { seed &+= 1; answered = nil; shown = nil }.font(.subheadline.bold())
                            .accessibilityIdentifier("quickAnother")
                    }
                }
            }
        }
    }

    private func record(_ card: Flashcard, _ courseId: String, _ knewIt: Bool) {
        let libs = model.libraries
        shown = card
        model.updateProfile { RecentLessonCard.record(card, courseId: courseId, knewIt: knewIt, profile: &$0, libraries: libs, now: Date()) }
        if knewIt { model.record(.flashcardRight) }
        answered = knewIt
    }
}
