import AVFoundation
import LQCore

/// Plays LQCore's synthesized chiptune music and sound effects through one
/// AVAudioSourceNode. Everything is generated on device; no audio files.
@MainActor
final class AudioService {
    private let engine = AVAudioEngine()
    private let mixer = ChipMixer()
    private var source: AVAudioSourceNode?
    private var started = false
    private(set) var currentMusic: GameMusic?
    var effectsOn = true
    var musicOn = true { didSet { applyMusic() } }
    /// The explorer's chosen music level (0…1).
    var musicLevel: Double = LearnerSettings.defaultMusicVolume { didSet { applyVolume() } }
    /// True while a lesson, review or game screen is open: music sits far in the background.
    var lessonMode = false { didSet { applyVolume() } }
    /// True while the voice is speaking: music drops out so every word is clear.
    var voiceSpeaking = false { didSet { applyVolume() } }

    /// Music level in lessons, relative to the chosen level.
    static let lessonFactor = 0.3

    init() {
        let mixer = self.mixer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buf = abl.first, let data = buf.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            mixer.render(into: data, count: Int(frameCount), sampleRate: 44_100)
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.8
        applyVolume()
    }

    private func applyVolume() {
        let level = voiceSpeaking ? 0 : musicLevel * (lessonMode ? Self.lessonFactor : 1)
        mixer.musicVolume = Float(level)
    }

    /// Starts lazily (and only while the app is in the foreground).
    private func ensureStarted() {
        // The engine stops on its own when another part of the app (speech recognition) reconfigures the session.
        guard !(started && engine.isRunning) else { return }
        do {
            // Same category as SpeechService so effects and Spanish voice share one session.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    func play(_ e: SoundEffect) {
        guard effectsOn else { return }
        ensureStarted()
        mixer.play(e)
    }

    func setMusic(_ track: GameMusic?) {
        currentMusic = track
        applyMusic()
    }

    private func applyMusic() {
        if musicOn, let t = currentMusic {
            ensureStarted()
            mixer.setMusic(t)
        } else {
            mixer.setMusic(nil)
        }
    }


    func suspend() {
        mixer.setMusic(nil)
        if started { engine.pause(); started = false }
    }

    func resume() { applyMusic() }
}
