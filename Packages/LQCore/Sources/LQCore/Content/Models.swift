import Foundation

// MARK: - Shared enums

/// The four language skills. Every unit must exercise all four.
public enum Skill: String, Codable, CaseIterable, Sendable {
    case listening, reading, writing, speaking

    public var isComprehension: Bool { self == .listening || self == .reading }
}

/// ACTFL World-Readiness communication modes.
public enum CommunicationMode: String, Codable, CaseIterable, Sendable {
    case interpretive, interpersonal, presentational
}

/// Guided practice gives scaffolds (word banks, tiles, choices). Independent
/// practice asks for recall with no scaffold. Only independent production
/// counts as "spontaneous use" in the learner model.
public enum PracticeKind: String, Codable, Sendable {
    case guided, independent
}

/// Content review pipeline. Only `released` content may ship in a public
/// build, and `released` requires a linguist review (see ContentValidator).
public enum ReviewStatus: String, Codable, Comparable, Sendable {
    case draft
    case authored
    case linguistReviewed = "linguist-reviewed"
    case released

    private var rank: Int {
        switch self {
        case .draft: return 0
        case .authored: return 1
        case .linguistReviewed: return 2
        case .released: return 3
        }
    }
    public static func < (a: ReviewStatus, b: ReviewStatus) -> Bool { a.rank < b.rank }
}

/// Age bands drive presentation (theme, reading support), never proficiency.
/// Language Quest is for ages 11 and up.
public enum AgeBand: String, Codable, CaseIterable, Sendable {
    case age11to12 = "11-12"
    case age13to15 = "13-15"
    case age16plus = "16+"

    /// The youngest age the app is designed for.
    public static let minimumAge = 11

    public var label: String {
        switch self {
        case .age11to12: return "11–12"
        case .age13to15: return "13–15"
        case .age16plus: return "16+"
        }
    }

    /// The default visual theme for this band. Players can switch any time.
    /// Since v0.6 (ages 11+) everyone starts with the sleeker Explorer look.
    public var defaultTheme: ThemeKind { .explorer }

    /// Read-aloud of English instructions is available to everyone but off by default for 11+.
    public var readAloudByDefault: Bool { false }

    /// Older saves stored "7-9" (7+ prototype) or "10-12" (v0.2–v0.5); those profiles become 11–12.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let band = AgeBand(rawValue: raw) { self = band; return }
        if raw == "7-9" || raw == "10-12" { self = .age11to12; return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown age band \(raw)"))
    }
}

// MARK: - Variant-aware text

/// Target-language text with optional regional overrides.
///
/// In JSON this is either a plain string (same everywhere) or an object:
/// `{"base": "el jugo", "es-ES": "el zumo", "es-PR": "el jugo"}`.
/// `base` is the Latin American neutral form (variant `es-419`).
public struct VText: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var base: String
    public var overrides: [String: String]

    public init(_ base: String, overrides: [String: String] = [:]) {
        self.base = base
        self.overrides = overrides
    }

    public init(stringLiteral value: String) { self.init(value) }

    /// The form for a variant, falling back to `base`.
    public func text(for variant: String) -> String { overrides[variant] ?? base }

    /// Every form across all regions (base first, no duplicates).
    public var allForms: [String] {
        var seen = Set<String>()
        return ([base] + overrides.keys.sorted().compactMap { overrides[$0] }).filter { seen.insert($0).inserted }
    }

    /// Variants whose form differs from the base.
    public var regionalVariants: [String] { overrides.keys.sorted() }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            self.init(s)
            return
        }
        let c = try decoder.container(keyedBy: Key.self)
        guard let base = try c.decodeIfPresent(String.self, forKey: Key(stringValue: "base")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Variant text object needs a \"base\" key"))
        }
        var o: [String: String] = [:]
        for k in c.allKeys where k.stringValue != "base" {
            o[k.stringValue] = try c.decode(String.self, forKey: k)
        }
        self.init(base, overrides: o)
    }

    public func encode(to encoder: Encoder) throws {
        if overrides.isEmpty {
            var c = encoder.singleValueContainer()
            try c.encode(base)
        } else {
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(base, forKey: Key(stringValue: "base"))
            for (k, v) in overrides { try c.encode(v, forKey: Key(stringValue: k)) }
        }
    }
}

// MARK: - Course

public struct Currency: Codable, Hashable, Sendable {
    public var code: String
    public var singular: String
    public var plural: String
    public var symbol: String
    /// Multiplier for shop prices in mini-games (e.g. 100 for yen). nil = 1.
    public var displayScale: Int?

    public var scale: Int { displayScale ?? 1 }
}

public enum WritingSystem: String, Codable, Sendable {
    /// Latin alphabet with accents (Spanish, French).
    case latin
    /// Japanese kana. Words are separated by spaces in lessons; romaji is derived automatically.
    case kana
    /// Any other script (Chinese, Hebrew, Greek, Ge'ez…). The course lists a
    /// romanization for every string in `romanizationOverrides`.
    case transliterated
}

/// Where a course is listed on the main menu.
public enum CourseCategory: String, Codable, CaseIterable, Sendable {
    case modern, african, ancient

    public var title: String {
        switch self {
        case .modern: return "Choose a language"
        case .african: return "African Languages"
        case .ancient: return "Old Languages"
        }
    }
}

/// A regional variety of the target language (e.g. Mexico, Spain, Argentina).
public struct LanguageVariant: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var nativeName: String
    public var flagEmoji: String
    /// Preferred AVSpeechSynthesisVoice locales, in order.
    public var voiceLocales: [String]
    /// Preferred speech-recognition locales, in order.
    public var speechLocales: [String]
    public var currency: Currency
    /// Uses "vos" instead of "tú" for informal "you".
    public var usesVoseo: Bool
    public var note: String
    /// When no voice for `voiceLocales` is installed, read the romanization with one
    /// of these voices instead (e.g. Amharic read aloud from its Latin spelling).
    public var romanizedVoiceLocales: [String]?
}

public struct Course: Codable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var title: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var defaultVariant: String
    public var variants: [LanguageVariant]
    public var unitFiles: [String]
    /// English name of the target language ("Spanish"). nil = derived from the code.
    public var languageName: String?
    /// Native name ("Español", "Français", "日本語").
    public var nativeName: String?
    public var writingSystem: WritingSystem?
    /// Whole-word romaji overrides for kana courses (e.g. こんにちは → konnichiwa).
    public var romanizationOverrides: [String: String]?
    /// Extra keys shown above the keyboard for typed answers.
    public var typingKeys: [String]?
    /// Menu section (nil = modern).
    public var category: CourseCategory?
    /// Hebrew and other right-to-left scripts.
    public var rightToLeft: Bool?

    public func variant(_ id: String) -> LanguageVariant? { variants.first { $0.id == id } }

    public var displayLanguage: String {
        languageName ?? ["es": "Spanish", "fr": "French", "ja": "Japanese"][targetLanguage] ?? targetLanguage
    }
    public var script: WritingSystem { writingSystem ?? .latin }

    public var section: CourseCategory { category ?? .modern }
    /// True when lessons can show a pronunciation line (romaji, pinyin, transliteration).
    public var hasRomanization: Bool { script != .latin }

    /// Romaji for kana courses, the authored romanization for other scripts, nil for Latin-script courses.
    public func romanize(_ s: String) -> String? {
        switch script {
        case .latin: return nil
        case .kana: return Kana.romanize(s, overrides: romanizationOverrides ?? [:])
        case .transliterated:
            let map = romanizationOverrides ?? [:]
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let whole = map[trimmed] { return whole }
            // Word by word, keeping punctuation and anything already in Latin letters (names).
            let punct = CharacterSet(charactersIn: ".,!?;:…·。，！？、「」“”\"'()[]")
            var out: [String] = []
            var hit = false
            for token in trimmed.split(separator: " ").map(String.init) {
                if let r = map[token] { out.append(r); hit = true; continue }
                let core = token.trimmingCharacters(in: punct)
                if let r = map[core], !core.isEmpty {
                    out.append(token.replacingOccurrences(of: core, with: r)); hit = true
                } else if core.unicodeScalars.allSatisfy({ $0.isASCII }) {
                    out.append(token)
                } else {
                    return nil
                }
            }
            return hit ? out.joined(separator: " ") : nil
        }
    }
}

// MARK: - Unit

public struct ActflAlignment: Codable, Hashable, Sendable {
    public var modes: [CommunicationMode]
    /// Target proficiency range, e.g. "Novice Low–Novice Mid".
    public var targetLevel: String
    /// Other ACTFL goal areas touched (Cultures, Connections, Comparisons, Communities).
    public var otherGoals: [String]
}

public struct ReviewInfo: Codable, Hashable, Sendable {
    public var text: ReviewStatus
    public var audio: ReviewStatus
    public var reviewers: [String]
    public var notes: String?
}

public enum LexKind: String, Codable, Sendable { case word, phrase }

public struct Example: Codable, Hashable, Sendable {
    public var target: VText
    public var english: String
}

/// A vocabulary word or phrase. This is the unit of spaced review.
public struct LexItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: LexKind
    public var target: VText
    public var english: String
    public var partOfSpeech: String?
    /// "m", "f", or nil.
    public var gender: String?
    /// An emoji or symbol key used as a picture cue.
    public var picture: String?
    /// Description of the picture for VoiceOver. Required when `picture` is set.
    public var altText: String?
    public var example: Example?
    /// Recorded audio file name. nil = on-device text-to-speech fallback.
    public var audioFile: String?
    public var note: String?
}

public struct CulturalNote: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    /// Variant-specific notes (key = variant id).
    public var byVariant: [String: String]?
}

public struct Reward: Codable, Hashable, Sendable {
    public var xp: Int
    public var cosmetic: String?
    public var badge: String?
}

public struct Quest: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var order: Int
    public var title: String
    public var npc: String
    public var location: String
    public var summary: String
    public var objective: String
    public var dialogue: Dialogue
    public var activities: [Activity]
    public var reward: Reward
}

public struct MasteryCheck: Codable, Hashable, Sendable {
    public var id: String
    public var passPercent: Int
    public var activities: [Activity]
}

public struct LessonUnit: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var version: Int
    public var order: Int
    public var title: String
    public var targetTitle: VText
    public var world: String
    public var objective: String
    public var canDo: [String]
    public var actfl: ActflAlignment
    public var ageBands: [AgeBand]
    public var review: ReviewInfo
    public var vocabulary: [LexItem]
    public var phrases: [LexItem]
    public var culturalNotes: [CulturalNote]
    public var quests: [Quest]
    public var masteryCheck: MasteryCheck

    public var allItems: [LexItem] { vocabulary + phrases }
    public var allActivities: [Activity] { quests.flatMap(\.activities) + masteryCheck.activities }
}

// MARK: - Activities

public enum ActivityType: String, Codable, CaseIterable, Sendable {
    /// Hear Spanish (TTS/audio + subtitles optional) and pick the meaning.
    case listenChoose
    /// Read Spanish and pick the meaning.
    case readChoose
    /// Match Spanish to English pairs.
    case match
    /// Put word tiles in order to build a Spanish sentence.
    case buildSentence
    /// Pick the word that fills the blank in a Spanish sentence.
    case fillBlank
    /// Type the Spanish for an English prompt (writing, no word bank).
    case typeAnswer
    /// Say a Spanish phrase (on-device recognition or self-check).
    case speak
    /// Pick the right reply in a conversation.
    case dialogueReply

    public var displayName: String {
        switch self {
        case .listenChoose: return "Listen"
        case .readChoose: return "Read"
        case .match: return "Match"
        case .buildSentence: return "Build"
        case .fillBlank: return "Fill in"
        case .typeAnswer: return "Write"
        case .speak: return "Speak"
        case .dialogueReply: return "Reply"
        }
    }
}

public struct ChoiceOption: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: VText
    public var picture: String?
    public var altText: String?
    public init(id: String, text: VText, picture: String? = nil, altText: String? = nil) {
        self.id = id; self.text = text; self.picture = picture; self.altText = altText
    }
}

public struct MatchPair: Codable, Hashable, Sendable {
    public var target: VText
    public var english: String
    public init(target: VText, english: String) { self.target = target; self.english = english }
}

public struct Activity: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var type: ActivityType
    public var skill: Skill
    public var mode: CommunicationMode
    public var practice: PracticeKind
    /// English instruction shown (and optionally read aloud).
    public var prompt: String
    /// The Spanish the learner hears, reads, or must say.
    public var target: VText?
    /// English gloss of `target`, used for subtitles and feedback.
    public var targetEnglish: String?
    public var choices: [ChoiceOption]?
    /// For choice activities: the id of the right choice.
    public var answer: String?
    /// For buildSentence: the tiles in the correct order.
    public var tiles: [VText]?
    /// For buildSentence: extra tiles that don't belong.
    public var distractors: [VText]?
    /// For typeAnswer/speak: every acceptable answer.
    public var accepted: [VText]?
    /// For match.
    public var pairs: [MatchPair]?
    /// For fillBlank: a sentence containing "___".
    public var sentence: VText?
    /// Lex item ids this activity practices (drives spaced review).
    public var items: [String]
    public var hint: String
    public var explanation: String

}

extension Activity {
    /// For activities built in code (bonus lessons). Authored activities come from JSON.
    public init(id: String, type: ActivityType, skill: Skill, mode: CommunicationMode, practice: PracticeKind,
                prompt: String, target: VText? = nil, targetEnglish: String? = nil, choices: [ChoiceOption]? = nil,
                answer: String? = nil, accepted: [VText]? = nil, pairs: [MatchPair]? = nil,
                items: [String], hint: String, explanation: String) {
        self.id = id; self.type = type; self.skill = skill; self.mode = mode; self.practice = practice
        self.prompt = prompt; self.target = target; self.targetEnglish = targetEnglish; self.choices = choices
        self.answer = answer; self.accepted = accepted; self.pairs = pairs
        self.items = items; self.hint = hint; self.explanation = explanation
    }
}

// MARK: - Dialogue

public struct DialogueEffect: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case setFlag, startQuest, giveCosmetic }
    public var kind: Kind
    public var value: String
    public init(kind: Kind, value: String) { self.kind = kind; self.value = value }
}

public struct DialogueChoice: Codable, Hashable, Sendable {
    public var text: VText
    public var gloss: String
    public var next: String
    /// nil = any reply is fine (social choice). false = gentle redirect.
    public var correct: Bool?
    public var feedback: String?
    public init(text: VText, gloss: String, next: String, correct: Bool? = nil, feedback: String? = nil) {
        self.text = text; self.gloss = gloss; self.next = next; self.correct = correct; self.feedback = feedback
    }
}

public struct DialogueNode: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var speaker: String
    public var line: VText
    public var gloss: String
    public var choices: [DialogueChoice]?
    public var next: String?
    public var effects: [DialogueEffect]?
    /// A safe, pre-written hint (Coco the parrot). Never generated.
    public var hint: String?

    public init(id: String, speaker: String, line: VText, gloss: String, choices: [DialogueChoice]? = nil,
                next: String? = nil, effects: [DialogueEffect]? = nil, hint: String? = nil) {
        self.id = id; self.speaker = speaker; self.line = line; self.gloss = gloss
        self.choices = choices; self.next = next; self.effects = effects; self.hint = hint
    }
}

public struct Dialogue: Codable, Hashable, Sendable {
    public var start: String
    public var nodes: [DialogueNode]

    public init(start: String, nodes: [DialogueNode]) { self.start = start; self.nodes = nodes }

    public func node(_ id: String) -> DialogueNode? { nodes.first { $0.id == id } }
}
