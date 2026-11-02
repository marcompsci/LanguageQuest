import SwiftUI
import LQCore

/// The result an activity view reports when the learner moves on.
struct ActivityResult {
    var outcome: ReviewOutcome
    /// False when a speaking answer was self-checked (not verified by recognition).
    var verified: Bool = true
}

/// Shared frame for every exercise: instructions, hint, the exercise body, and
/// kind feedback. In practice mode the learner may retry (up to 3 tries, then
/// the answer is shown). In assessment mode there is one try, then feedback.
struct ActivityHost: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let activity: Activity
    var assessment = false
    let onDone: (ActivityResult) -> Void

    @State private var attempts = 0
    @State private var usedHint = false
    @State private var showHint = false
    @State private var verdict: AnswerVerdict?
    @State private var finished = false
    @State private var started = Date()
    @State private var selfChecked = false

    static let maxTries = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            exercise
                .disabled(finished)
            Spacer(minLength: 0)
            feedback
        }
        .padding(20)
        // Gentle haptic: success for right, a soft tap for "try again". Off with the sounds setting.
        .sensoryFeedback(trigger: attempts) { _, _ in
            guard model.profile?.settings.soundEffects ?? true, let v = verdict else { return nil }
            return v.isCorrect ? .success : .impact(weight: .light)
        }
        .onAppear {
            started = Date()
            model.readAloud(activity.prompt)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(activity.skill.rawValue.capitalized, systemImage: skillIcon)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(p.accent).opacity(0.15), in: Capsule())
                Text(activity.type.displayName).font(.caption).foregroundStyle(Color(p.secondaryText))
                Spacer()
                if !assessment {
                    Button { showHint = true; usedHint = true } label: { Label("Hint", systemImage: "lightbulb") }
                        .font(.subheadline)
                        .accessibilityIdentifier("hintButton")
                }
            }
            HStack(alignment: .top) {
                Text(activity.prompt).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { model.speech.speakEnglish(activity.prompt, settings: model.profile?.settings ?? LearnerSettings()) } label: {
                    Image(systemName: "text.bubble")
                }
                .accessibilityLabel("Read the instructions aloud")
            }
            if showHint {
                Label(activity.hint, systemImage: "bird.fill")
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var skillIcon: String {
        switch activity.skill {
        case .listening: return "ear"
        case .reading: return "book"
        case .writing: return "pencil"
        case .speaking: return "mouth"
        }
    }

    @ViewBuilder
    private var exercise: some View {
        switch activity.type {
        case .listenChoose, .readChoose, .fillBlank, .dialogueReply:
            ChoiceExercise(activity: activity, onAnswer: submitChoice)
        case .match:
            MatchExercise(activity: activity) { mistakes in finish(correct: true, extraAttempts: mistakes) }
        case .buildSentence:
            BuildExercise(activity: activity) { tiles in
                submit(AnswerChecker.checkTiles(tiles, correct: activity.tiles ?? [], variant: variantId))
            }
        case .typeAnswer:
            TypeExercise(activity: activity) { text in
                submit(AnswerChecker.check(text, accepted: activity.accepted ?? [], variant: variantId))
            }
        case .speak:
            SpeakExercise(activity: activity, assessment: assessment,
                          onRecognized: { text in submit(AnswerChecker.check(text, accepted: activity.accepted ?? [], variant: variantId)) },
                          onSelfCheck: { selfChecked = true; finish(correct: true, extraAttempts: 0) })
        }
    }

    private var variantId: String { model.profile?.variant ?? "es-419" }

    private func submitChoice(_ id: String) {
        let expected = activity.choices?.first { $0.id == activity.answer }.map { model.text($0.text) } ?? ""
        submit(id == activity.answer ? .correct : .incorrect(expected: expected))
    }

    private func submit(_ v: AnswerVerdict) {
        attempts += 1
        verdict = v
        if v.isCorrect {
            finished = true
        } else if assessment || attempts >= Self.maxTries {
            finished = true
        }
    }

    private func finish(correct: Bool, extraAttempts: Int) {
        attempts = 1 + extraAttempts
        verdict = .correct
        finished = true
    }

    @ViewBuilder
    private var feedback: some View {
        if let v = verdict {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    // Shape + color + words: never color alone.
                    Image(systemName: v.isCorrect ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color(v.isCorrect ? p.success : p.retry))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AnswerChecker.feedback(for: v, variantName: model.variantName))
                            .font(.headline)
                            .accessibilityIdentifier("feedbackText")
                        if finished { Text(activity.explanation).font(.subheadline) }
                        if !finished { Text(activity.hint).font(.subheadline) }
                    }
                }
                if finished {
                    Button("Continue") { report() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("continueButton")
                } else {
                    Button("Try again") { verdict = nil }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("tryAgainButton")
                }
            }
            .padding(14)
            .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
        }
    }

    private func report() {
        let correct = verdict?.isCorrect ?? false
        let outcome = ReviewOutcome(correct: correct, attempts: max(1, attempts),
                                    responseSeconds: Date().timeIntervalSince(started), usedHint: usedHint)
        onDone(ActivityResult(outcome: outcome, verified: !selfChecked))
    }
}
