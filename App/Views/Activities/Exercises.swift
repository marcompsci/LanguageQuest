import SwiftUI
import LQCore

/// Deterministic shuffle so the same exercise always looks the same (easier
/// for teachers and parents to talk about) but answers aren't always first.
func stableShuffle<T>(_ items: [T], seed: String) -> [T] {
    var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }))
    return items.shuffled(using: &rng)
}

// MARK: - Choice (listen / read / fill-in / reply)

struct ChoiceExercise: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let activity: Activity
    let onAnswer: (String) -> Void
    @State private var showText = false
    @State private var picked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stimulus
            ForEach(activity.choices ?? []) { c in
                Button {
                    picked = c.id
                    onAnswer(c.id)
                } label: {
                    HStack(spacing: 12) {
                        if let pic = c.picture {
                            Text(pic).font(.largeTitle).accessibilityLabel(c.altText ?? "")
                        }
                        Text(model.display(c.text)).font(.title3)
                        Spacer()
                        if picked == c.id {
                            Image(systemName: c.id == activity.answer ? "checkmark" : "arrow.uturn.backward")
                                .accessibilityLabel(c.id == activity.answer ? "Right answer" : "Try again")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(picked == c.id ? Color(p.accent) : .clear, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("choice-\(c.id)")
            }
        }
    }

    @ViewBuilder
    private var stimulus: some View {
        switch activity.type {
        case .listenChoose, .dialogueReply:
            HStack(spacing: 16) {
                if let t = activity.target {
                    SpeakerButton(text: t, label: "Play the audio", big: activity.type == .listenChoose)
                        .onAppear { model.say(t) }
                    VStack(alignment: .leading) {
                        // Text is available for deaf and hard-of-hearing learners and as a support.
                        if showText || activity.type == .dialogueReply {
                            Text(model.display(t)).font(.title2.bold())
                        } else {
                            Button("Show the words") { showText = true }.font(.subheadline)
                        }
                    }
                }
            }
        case .readChoose:
            if let t = activity.target {
                HStack {
                    Text(model.display(t)).font(.title.bold())
                    Spacer()
                    SpeakerButton(text: t)
                }
            }
        case .fillBlank:
            if let s = activity.sentence {
                Text(model.display(s).replacingOccurrences(of: "___", with: "_____"))
                    .font(.title.bold())
                    .accessibilityLabel(model.text(s).replacingOccurrences(of: "___", with: "blank"))
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Match

struct MatchExercise: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let activity: Activity
    let onComplete: (Int) -> Void
    @State private var selectedLeft: Int?
    @State private var matched: Set<Int> = []
    @State private var mistakes = 0
    @State private var wrongFlash: Int?

    private var pairs: [MatchPair] { activity.pairs ?? [] }
    private var rightOrder: [Int] { stableShuffle(Array(pairs.indices), seed: activity.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                ForEach(pairs.indices, id: \.self) { i in
                    tile(model.display(pairs[i].target), state: matched.contains(i) ? .done : selectedLeft == i ? .selected : .idle) {
                        guard !matched.contains(i) else { return }
                        selectedLeft = i
                        model.say(pairs[i].target)
                    }
                    .accessibilityIdentifier("matchLeft\(i)")
                }
            }
            VStack(spacing: 10) {
                ForEach(rightOrder, id: \.self) { i in
                    tile(pairs[i].english, state: matched.contains(i) ? .done : wrongFlash == i ? .wrong : .idle) { tapRight(i) }
                        .accessibilityIdentifier("matchRight\(i)")
                }
            }
        }
    }

    private func tapRight(_ i: Int) {
        guard let l = selectedLeft, !matched.contains(i) else { return }
        if l == i {
            matched.insert(i)
            selectedLeft = nil
            if matched.count == pairs.count { onComplete(min(mistakes, 3)) }
        } else {
            mistakes += 1
            wrongFlash = i
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { wrongFlash = nil }
        }
    }

    enum TileState { case idle, selected, done, wrong }

    private func tile(_ text: String, state: TileState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text).font(.headline).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if state == .done { Image(systemName: "checkmark").accessibilityLabel("Matched") }
                if state == .wrong { Image(systemName: "arrow.uturn.backward").accessibilityLabel("Not a match") }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color(state == .done ? p.success : p.surface).opacity(state == .done ? 0.2 : 1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(state == .selected ? Color(p.accent) : state == .wrong ? Color(p.retry) : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }
}

// MARK: - Build a sentence

struct BuildExercise: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let activity: Activity
    let onCheck: ([String]) -> Void
    @State private var chosen: [Int] = []

    private var bank: [String] {
        let all = (activity.tiles ?? []) + (activity.distractors ?? [])
        return stableShuffle(all.map { model.text($0) }, seed: activity.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let en = activity.targetEnglish { Text(en).font(.title3).foregroundStyle(Color(p.secondaryText)) }
            FlowRow(spacing: 8) {
                ForEach(chosen, id: \.self) { i in
                    chip(bank[i], filled: true) { chosen.removeAll { $0 == i } }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(8)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Your sentence: \(chosen.map { bank[$0] }.joined(separator: " "))")
            FlowRow(spacing: 8) {
                ForEach(bank.indices, id: \.self) { i in
                    if !chosen.contains(i) {
                        chip(bank[i], filled: false) { chosen.append(i) }
                            .accessibilityIdentifier("tile-\(bank[i])")
                    }
                }
            }
            Button("Check") { onCheck(chosen.map { bank[$0] }) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(chosen.isEmpty)
                .accessibilityIdentifier("checkButton")
        }
    }

    private func chip(_ t: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(model.display(t)).font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).frame(minHeight: 46)
                .background(filled ? Color(p.accent) : Color(p.surface), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(filled ? Color(p.onAccent) : Color(p.text))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(p.accent), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityHint(filled ? "Removes this word" : "Adds this word")
    }
}

/// Simple wrapping layout for word tiles.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Type (writing)

struct TypeExercise: View {
    @Environment(\.palette) var p
    let activity: Activity
    let onCheck: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @EnvironmentObject var model: AppModel
    private var accents: [String] { model.library?.course.typingKeys ?? ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡"] }
    private var placeholder: String {
        model.library?.course.script == .kana ? "Type in kana or romaji" : model.library?.course.hasRomanization == true ? "Type in \(model.languageName) or its Latin spelling" : "Type in \(model.languageName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(placeholder, text: $text)
                .font(.title2)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if !text.isEmpty { onCheck(text) } }
                .accessibilityIdentifier("answerField")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(accents, id: \.self) { a in
                        Button(a) { text += a }
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Type \(a)")
                    }
                }
            }
            Button("Check") { onCheck(text) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("checkButton")
        }
        .onAppear { focused = true }
    }
}

// MARK: - Speak

struct SpeakExercise: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var rec: SpeechRecognitionService
    @Environment(\.palette) var p
    let activity: Activity
    let assessment: Bool
    let onRecognized: (String) -> Void
    let onSelfCheck: () -> Void
    @State private var revealed = false

    init(activity: Activity, assessment: Bool, onRecognized: @escaping (String) -> Void, onSelfCheck: @escaping () -> Void) {
        self.activity = activity
        self.assessment = assessment
        self.onRecognized = onRecognized
        self.onSelfCheck = onSelfCheck
        // The model owns the recognizer; observe it directly.
        _rec = ObservedObject(wrappedValue: SpeechRecognitionServiceHolder.shared)
    }

    private var availability: SpeechRecognitionService.Availability {
        rec.availability(variant: model.variant, parentAllowed: model.save.parent.allowOnDeviceSpeech)
    }

    /// Independent practice hides the Spanish until the learner has tried.
    private var showsModel: Bool { activity.practice == .guided || revealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let t = activity.target {
                if showsModel {
                    HStack {
                        Text(model.display(t)).font(.title.bold())
                        Spacer()
                        SpeakerButton(text: t, label: "Hear it first")
                    }
                } else if let en = activity.targetEnglish {
                    Text("“\(en)”").font(.title2.bold())
                }
            }
            if availability == .available {
                Button {
                    if rec.isListening { rec.stop(); onRecognized(rec.transcript) } else { rec.start(variant: model.variant) }
                } label: {
                    Label(rec.isListening ? "I'm done" : "Tap and talk", systemImage: rec.isListening ? "stop.circle.fill" : "mic.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("talkButton")
                if rec.isListening {
                    Label("Listening on this device only", systemImage: "waveform").font(.caption)
                }
                if !rec.transcript.isEmpty { Text("I heard: \(rec.transcript)").font(.subheadline) }
            } else {
                // No microphone: say it aloud, then self-check. Nothing is recorded.
                Text("Say it out loud. Then tap below.").font(.subheadline)
                if !showsModel {
                    Button("Show me the answer") { revealed = true }.buttonStyle(SecondaryButtonStyle())
                }
                Button { revealed = true; onSelfCheck() } label: { Label("I said it!", systemImage: "checkmark.bubble.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("saidItButton")
                if availability == .unsupportedOnDevice {
                    Text("Speech checking isn't available for this language on this device, so nothing is recorded.").font(.caption)
                }
            }
        }
        .onDisappear { rec.stop() }
    }
}

/// One shared recognizer instance so audio resources are never duplicated.
@MainActor
enum SpeechRecognitionServiceHolder {
    static let shared = SpeechRecognitionService()
}
