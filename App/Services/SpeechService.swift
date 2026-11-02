import AVFoundation
import LQCore

/// Text-to-speech using voices already on the device. This is a stand-in for
/// native-speaker recordings (see docs/CURRICULUM.md "Audio"). Voices differ by
/// device and iOS version, so we pick the best available match at runtime.
@MainActor
final class SpeechService {
    private let synth = AVSpeechSynthesizer()

    init() {
        // Plays alongside other audio and respects the silent switch only for effects.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
    }

    /// Best voice for a variant: exact locale, then the variant's fallbacks, then any Spanish voice.
    static func voice(for v: LanguageVariant?) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let wanted = v?.voiceLocales ?? ["es-MX"]
        for loc in wanted {
            let matches = all.filter { $0.language.caseInsensitiveCompare(loc) == .orderedSame }
            if let best = matches.max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return best }
        }
        return all.filter { $0.language.hasPrefix("es") }.max(by: { $0.quality.rawValue < $1.quality.rawValue })
    }

    func speakSpanish(_ text: String, variant: LanguageVariant?, settings: LearnerSettings) {
        speak(text, voice: Self.voice(for: variant), settings: settings)
    }

    func speakEnglish(_ text: String, settings: LearnerSettings) {
        speak(text, voice: AVSpeechSynthesisVoice(language: "en-US"), settings: settings)
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?, settings: LearnerSettings) {
        guard settings.voiceVolume > 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text.replacingOccurrences(of: "…", with: ""))
        u.voice = voice
        u.rate = Float(settings.speechRate)
        u.volume = Float(settings.voiceVolume)
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    /// Names of the Spanish voices on this device, for the parent settings screen.
    static func availableSpanishVoices() -> [String] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("es") }.map { "\($0.name) (\($0.language))" }.sorted()
    }
}
