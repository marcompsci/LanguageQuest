import Foundation

/// Plays an authored dialogue tree. Deterministic: the same choices always
/// produce the same path. There is no free text and no generated dialogue.
public struct DialogueRunner: Sendable {
    public let dialogue: Dialogue
    public private(set) var current: DialogueNode?
    public private(set) var history: [String] = []
    public private(set) var effects: [DialogueEffect] = []
    /// The last wrong choice's feedback (shown gently; the node stays put).
    public private(set) var lastFeedback: String?
    public private(set) var wrongChoices = 0

    public init(_ d: Dialogue) {
        dialogue = d
        current = d.node(d.start)
        if let c = current { enter(c) }
    }

    public var isFinished: Bool { current == nil }
    public var awaitingChoice: Bool { !(current?.choices ?? []).isEmpty }

    private mutating func enter(_ n: DialogueNode) {
        history.append(n.id)
        effects += n.effects ?? []
    }

    /// Advance a line that has no choices.
    public mutating func advance() {
        guard let c = current, !awaitingChoice else { return }
        lastFeedback = nil
        if let next = c.next, let n = dialogue.node(next) {
            current = n
            enter(n)
        } else {
            current = nil
        }
    }

    /// Choose a reply. A wrong reply shows feedback and lets the learner pick again.
    /// Returns false if the choice was a gentle "try again".
    @discardableResult
    public mutating func choose(_ index: Int) -> Bool {
        guard let c = current, let choices = c.choices, choices.indices.contains(index) else { return false }
        let ch = choices[index]
        if ch.correct == false {
            lastFeedback = ch.feedback
            wrongChoices += 1
            return false
        }
        lastFeedback = nil
        if let n = dialogue.node(ch.next) {
            current = n
            enter(n)
        } else {
            current = nil
        }
        return true
    }

    /// Plays to the end choosing the first acceptable reply each time (used in tests and previews).
    public mutating func autoplay(limit: Int = 200) {
        var steps = 0
        while let c = current, steps < limit {
            steps += 1
            if let cs = c.choices, !cs.isEmpty {
                let i = cs.firstIndex { $0.correct != false } ?? 0
                choose(i)
            } else {
                advance()
            }
        }
    }
}
