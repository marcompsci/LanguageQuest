import SwiftUI
import LQCore

/// NPC conversation box: Spanish line, optional English subtitle, replies.
struct DialogueOverlay: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let conversation: WorldCoordinator.Conversation
    let onAdvance: () -> Void
    let onChoose: (Int) -> Void
    @State private var showEnglish = false
    @State private var showHint = false

    var body: some View {
        VStack {
            Spacer()
            if let node = conversation.runner.current {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(conversation.npc.name).font(.headline)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(p.accent), in: Capsule())
                            .foregroundStyle(Color(p.onAccent))
                        Spacer()
                        SpeakerButton(text: node.line, label: "Hear \(conversation.npc.name) again")
                    }
                    Text(model.text(node.line))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dialogueLine")
                    if subtitlesOn || showEnglish {
                        Text(model.personalize(node.gloss))
                            .font(.subheadline)
                            .foregroundStyle(Color(p.secondaryText))
                    } else {
                        Button("Show English") { showEnglish = true }.font(.subheadline)
                    }
                    if let fb = conversation.runner.lastFeedback {
                        Label(fb, systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(Color(p.retry))
                            .font(.subheadline.weight(.semibold))
                    }
                    if let hint = node.hint {
                        if showHint {
                            Label(hint, systemImage: "bird.fill").font(.subheadline)
                        } else {
                            Button { showHint = true } label: { Label("Ask Coco for a hint", systemImage: "bird") }
                                .font(.subheadline)
                        }
                    }
                    if let choices = node.choices, !choices.isEmpty {
                        ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                            Button { showHint = false; onChoose(i) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.text(c.text)).font(.headline)
                                    if subtitlesOn || showEnglish {
                                        Text(model.personalize(c.gloss)).font(.caption).foregroundStyle(Color(p.secondaryText))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(p.background), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("reply\(i)")
                        }
                    } else {
                        Button { showHint = false; onAdvance() } label: { Label("Next", systemImage: "chevron.right.circle.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("dialogueNext")
                    }
                }
                .padding(18)
                .background(Color(p.dialogueBox), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(p.accent).opacity(0.5), lineWidth: 2))
                .padding(12)
                .onChange(of: node.id) { _, _ in showEnglish = false }
            }
        }
        .background(Color.black.opacity(0.15).ignoresSafeArea())
    }

    private var subtitlesOn: Bool { model.profile?.settings.subtitles ?? true }
}
