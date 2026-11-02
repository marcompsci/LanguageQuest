import SwiftUI
import LQCore

/// The main menu: shown at launch and from the house button in the village.
struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @State private var phase = DayPhase.now()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            ThemedBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Language Quest")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    if let prof = model.profile {
                        explorerCard(prof)
                        Button { model.play() } label: {
                            Label("Play: \(model.languageName) village", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("playButton")
                        languagesCard
                        todayCard(prof)
                        LazyVGrid(columns: columns, spacing: 12) {
                            tile("gamecontroller.fill", "Games", "menu-games") { model.sheet = .games }
                            tile("rectangle.on.rectangle.angled", "Flashcards", "menu-flashcards") { model.sheet = .flashcards }
                            tile("arrow.triangle.2.circlepath", "Review", "menu-review") { model.sheet = .review }
                            tile("character.book.closed.fill", "Phrasebook", "menu-phrasebook") { model.sheet = .phrasebook }
                            if model.library?.course.script == .kana {
                                tile("character.ja", "Kana Dojo", "menu-kana") { model.sheet = .kana }
                            }
                            tile("book.closed.fill", "Quest journal", "menu-journal") { model.sheet = .journal }
                            tile("tshirt.fill", "Wardrobe", "menu-wardrobe") { model.sheet = .wardrobe }
                            tile("bag.fill", "Bag and badges", "menu-bag") { model.sheet = .bag }
                            tile("gearshape.fill", "Settings", "menu-settings") { model.sheet = .settings }
                            tile("lock.shield", "Parents", "grownUpsButton") { model.sheet = .parent }
                        }
                        if model.save.profiles.count > 1 { explorersCard }
                    }
                }
                .padding(16)
            }
        }
        .onAppear { phase = DayPhase.now() }
    }

    private func explorerCard(_ prof: PlayerProfile) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(uiImage: PixelArt.avatarImage(prof.avatar, scale: 5))
                    .interpolation(.none)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(phase.greeting), \(prof.nickname.isEmpty ? "explorer" : prof.nickname)!").font(.headline)
                    Label("\(prof.rewards.xp) XP", systemImage: "star.fill").font(.subheadline)
                    Text("\(prof.rewards.badges.count) badge\(prof.rewards.badges.count == 1 ? "" : "s") · \(prof.rewards.ownedCosmetics.count) item\(prof.rewards.ownedCosmetics.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var languagesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Languages").font(.headline)
                    Spacer()
                    Text("Tap to switch").font(.caption).foregroundStyle(Color(p.secondaryText))
                }
                ForEach(model.courseSummaries) { s in LanguageRow(summary: s) }
                Text("Progress in each language is kept when you switch.").font(.caption).foregroundStyle(Color(p.secondaryText))
            }
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

    private func tile(_ icon: String, _ title: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(Color(p.accent))
                Text(title).font(.subheadline.bold()).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// A flag, the language name and a progress bar. Tapping switches to that language.
struct LanguageRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let summary: CourseSummary

    var body: some View {
        Button { model.switchCourse(to: summary.courseId) } label: {
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
                if summary.isActive {
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
        .accessibilityHint(summary.isActive ? "" : "Switches to \(summary.language)")
        .accessibilityIdentifier("course-\(summary.courseId)")
    }
}
