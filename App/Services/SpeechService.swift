import AVFoundation
import LQCore

/// Text-to-speech using voices already on the device. This is a stand-in for
/// native-speaker recordings (see docs/CURRICULUM.md "Audio"). Voices differ by
/// device and iOS version, so we pick the best available match at runtime.
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    /// Called with true when the voice starts and false when it stops (used to duck music).
    var onSpeakingChanged: ((Bool) -> Void)?

    override init() {
        super.init()
        synth.delegate = self
        // Plays alongside other audio and respects the silent switch only for effects.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
    }

    // MARK: Choosing the most natural voice

    /// Higher is more natural: downloaded Premium and Enhanced voices beat the built-in
    /// compact ones; novelty and older "Eloquence" voices are avoided.
    static func naturalness(_ v: AVSpeechSynthesisVoice) -> Int {
        if v.voiceTraits.contains(.isNoveltyVoice) { return -10 }
        let id = v.identifier.lowercased()
        if id.contains("eloquence") { return -5 }
        var score: Int
        switch v.quality {
        case .premium: score = 30
        case .enhanced: score = 20
        default: score = 10
        }
        if id.contains("siri") { score += 3 }
        if id.contains("compact") || id.contains("speech.synthesis") { score -= 2 }
        return score
    }

    /// Most natural installed voice for the first locale that has one.
    static func bestVoice(_ locales: [String]) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        for loc in locales {
            let m = all.filter { $0.language.caseInsensitiveCompare(loc) == .orderedSame && naturalness($0) > 0 }
            if let b = m.max(by: { naturalness($0) < naturalness($1) }) { return b }
        }
        return nil
    }

    /// Best voice for a variant: its locales in order, then any Spanish voice (legacy fallback).
    static func voice(for v: LanguageVariant?) -> AVSpeechSynthesisVoice? {
        bestVoice(v?.voiceLocales ?? ["es-MX"]) ?? bestVoice(["es-MX", "es-US", "es-ES"])
    }

    /// What the settings screen tells the learner about this language's voice.
    static func voiceStatus(for v: LanguageVariant?) -> (name: String, natural: Bool)? {
        guard let v else { return nil }
        let voice = bestVoice(v.voiceLocales) ?? bestVoice(v.romanizedVoiceLocales ?? [])
        guard let voice else { return nil }
        return (voice.name, voice.quality == .premium || voice.quality == .enhanced)
    }

    func speakSpanish(_ text: String, variant: LanguageVariant?, settings: LearnerSettings) {
        speak(text, voice: Self.voice(for: variant), settings: settings)
    }

    /// Reads target-language text. When no voice for the language is installed (Amharic,
    /// Yoruba, Ancient Egyptian…), reads its Latin spelling with a fallback voice instead
    /// of handing the text to a voice for some other language.
    func speakTarget(_ text: String, romanized: String?, variant: LanguageVariant?, settings: LearnerSettings) {
        guard let v = variant else { return speakSpanish(text, variant: nil, settings: settings) }
        if let native = Self.bestVoice(v.voiceLocales) {
            speak(text, voice: native, settings: settings)
        } else if let fallback = Self.bestVoice(v.romanizedVoiceLocales ?? ["en-US"]) {
            speak(romanized ?? text, voice: fallback, settings: settings)
        }
    }

    func speakEnglish(_ text: String, settings: LearnerSettings) {
        speak(text, voice: Self.bestVoice(["en-US", "en-GB", "en-AU"]), settings: settings)
    }

    /// Speaks sentence by sentence with short, natural pauses instead of one flat run.
    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?, settings: LearnerSettings) {
        guard settings.voiceVolume > 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let clean = text.replacingOccurrences(of: "…", with: ",").replacingOccurrences(of: "\n", with: " ")
        let parts = Self.sentences(clean)
        for (i, part) in parts.enumerated() {
            let u = AVSpeechUtterance(string: part)
            u.voice = voice
            // The slider (0.3–0.55) maps around the system's natural rate (0.5).
            u.rate = Float(min(max(settings.speechRate, 0.3), 0.55))
            u.pitchMultiplier = 1.0
            u.volume = Float(settings.voiceVolume)
            u.preUtteranceDelay = i == 0 ? 0.05 : 0
            u.postUtteranceDelay = i == parts.count - 1 ? 0 : 0.22
            u.prefersAssistiveTechnologySettings = true
            synth.speak(u)
        }
    }

    /// Splits after sentence-ending punctuation in any script (. ! ? 。 ！ ？ ።), keeping it.
    static func sentences(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？", "።", ";"]
        for ch in s {
            cur.append(ch)
            if enders.contains(ch) {
                let t = cur.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { out.append(t) }
                cur = ""
            }
        }
        let t = cur.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append(t) }
        return out.isEmpty ? [s] : out
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onSpeakingChanged?(true) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onSpeakingChanged?(self.synth.isSpeaking) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onSpeakingChanged?(self.synth.isSpeaking) }
    }

    /// Names of the Spanish voices on this device, for the parent settings screen.
    static func availableSpanishVoices() -> [String] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("es") }.map { "\($0.name) (\($0.language))" }.sorted()
    }
}
