import SwiftUI
import LQCore

/// First run: age band (no birthdate), language, Spanish variant, avatar,
/// optional nickname, then an optional placement test.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p

    enum Step: Int, CaseIterable { case welcome, age, language, variant, avatar, name }
    @State private var step: Step = .welcome
    @State private var ageBand: AgeBand?
    @State private var variantId: String?
    @State private var avatar = AvatarConfig()
    @State private var nickname = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            ThemedBackground()
            VStack(spacing: 20) {
                if step != .welcome {
                    ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                        .accessibilityLabel("Step \(step.rawValue) of \(Step.allCases.count - 1)")
                }
                ScrollView { content.frame(maxWidth: 560).frame(maxWidth: .infinity) }
                if let e = error { Text(e).foregroundStyle(Color(p.retry)) }
                HStack(spacing: 12) {
                    if step != .welcome {
                        Button("Back") { go(-1) }.buttonStyle(SecondaryButtonStyle())
                    }
                    Button(step == .name ? "Start exploring" : "Next") { next() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canContinue)
                        .accessibilityIdentifier("onboardingNext")
                }
                .frame(maxWidth: 560)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 16) {
                Image(uiImage: PixelArt.avatarImage(AvatarConfig(body: 1, hair: 1, hairColor: 0, outfit: 4, accessory: "scarf-yellow"), scale: 10))
                    .interpolation(.none)
                    .accessibilityLabel("Luna, your guide")
                Text("Language Quest").font(.largeTitle.bold())
                Text("Explore a village, meet new friends, and learn languages from around the world by talking with them.")
                    .font(.title3).multilineTextAlignment(.center)
                Text("No ads. No timers. Mistakes are how we learn.").font(.subheadline)
            }
        case .age:
            VStack(alignment: .leading, spacing: 12) {
                Text("How old is the explorer?").font(.title.bold())
                Text("This only changes how the game looks and how much reading help you get. It doesn't change your level.")
                    .font(.subheadline)
                // No option is pre-selected (neutral age screening).
                ForEach(AgeBand.allCases, id: \.self) { b in
                    choiceRow("\(b.label) years", selected: ageBand == b) { ageBand = b }
                        .accessibilityIdentifier("age-\(b.rawValue)")
                }
            }
        case .language:
            VStack(alignment: .leading, spacing: 12) {
                Text("What do you want to learn?").font(.title.bold())
                ForEach(model.courses, id: \.id) { c in
                    choiceRow("\(c.displayLanguage) · \(c.nativeName ?? "")", detail: courseDetail(c),
                              selected: model.onboardingCourseId == c.id) {
                        if model.onboardingCourseId != c.id { model.onboardingCourseId = c.id; variantId = nil }
                    }
                    .accessibilityIdentifier("course-\(c.id)")
                }
                Text("You can add another language later in the Parents area. Each language keeps its own progress.")
                    .font(.footnote).foregroundStyle(Color(p.secondaryText))
            }
        case .variant:
            VStack(alignment: .leading, spacing: 12) {
                Text("Which \(model.languageName)?").font(.title.bold())
                Text("All of these are real \(model.languageName). Pick the one your family, friends, or school uses. You can change it later.")
                    .font(.subheadline)
                ForEach(model.library?.course.variants ?? []) { v in
                    choiceRow("\(v.flagEmoji) \(v.name)", detail: v.note, selected: variantId == v.id) { variantId = v.id }
                        .accessibilityIdentifier("variant-\(v.id)")
                }
            }
        case .avatar:
            AvatarEditor(avatar: $avatar)
        case .name:
            VStack(alignment: .leading, spacing: 12) {
                Text("What should we call you?").font(.title.bold())
                Text("A first name or nickname is fine. It stays on this device. You can leave it blank.")
                    .font(.subheadline)
                TextField("Nickname (optional)", text: $nickname)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("nicknameField")
            }
        }
    }

    private func choiceRow(_ title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if let d = detail { Text(d).font(.caption).foregroundStyle(Color(p.secondaryText)) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color(p.accent) : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var canContinue: Bool {
        switch step {
        case .age: return ageBand != nil
        case .variant: return variantId != nil
        default: return true
        }
    }

    private func courseDetail(_ c: Course) -> String {
        switch c.targetLanguage {
        case "es": return "6 regional varieties, from Mexico to Spain to Argentina"
        case "fr": return "France or Québec"
        case "ja": return "Hiragana and katakana, with romaji to help you read"
        default: return ""
        }
    }

    private func go(_ d: Int) {
        error = nil
        guard var s = Step(rawValue: step.rawValue + d) else { return }
        // A course with one variant (Japanese) needs no variant step.
        if s == .variant, let only = model.library?.course.variants, only.count == 1 {
            variantId = only[0].id
            s = Step(rawValue: s.rawValue + d) ?? s
        }
        step = s
    }

    private func next() {
        guard step == .name else { go(1); return }
        guard let band = ageBand, let v = variantId else { return }
        let profile = PlayerProfile(nickname: PlayerProfile.sanitizeNickname(nickname), ageBand: band, avatar: avatar,
                                    courseId: model.onboardingCourseId, variant: v)
        do {
            try model.createProfile(profile)
            model.sheet = .placement
        } catch FamilyError.profileLimitReached(let max) {
            error = "This device already has \(max) explorers. A grown-up can remove one in the Grown-ups area."
        } catch {
            self.error = "Something went wrong. Please try again."
        }
    }
}

struct AvatarEditor: View {
    @Binding var avatar: AvatarConfig
    @Environment(\.palette) var p

    var body: some View {
        VStack(spacing: 16) {
            Text("Make your explorer").font(.title.bold())
            Image(uiImage: PixelArt.avatarImage(avatar, scale: 10))
                .interpolation(.none)
                .accessibilityLabel("Your explorer preview")
            stepper("Skin", value: $avatar.body, count: AvatarConfig.bodyCount)
            stepper("Hair style", value: $avatar.hair, count: AvatarConfig.hairCount)
            stepper("Hair color", value: $avatar.hairColor, count: AvatarConfig.hairColorCount)
            stepper("Outfit", value: $avatar.outfit, count: AvatarConfig.outfitCount)
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, count: Int) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button { value.wrappedValue = (value.wrappedValue + count - 1) % count } label: { Image(systemName: "chevron.left.circle.fill").font(.title) }
                .accessibilityLabel("Previous \(title.lowercased())")
            Text("\(value.wrappedValue + 1)/\(count)").monospacedDigit().frame(width: 52)
            Button { value.wrappedValue = (value.wrappedValue + 1) % count } label: { Image(systemName: "chevron.right.circle.fill").font(.title) }
                .accessibilityLabel("Next \(title.lowercased())")
                .accessibilityIdentifier("next-\(title)")
        }
        .padding(12)
        .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value.wrappedValue + 1) of \(count)")
    }
}
