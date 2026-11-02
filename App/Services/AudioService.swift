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
    private(set) var currentMusic: MusicTrack?
    var effectsOn = true
    var musicOn = true { didSet { applyMusic() } }

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
    }

    /// Starts lazily (and only while the app is in the foreground).
    private func ensureStarted() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
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

    func setMusic(_ track: MusicTrack?) {
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

    /// Lower the music while the voice speaks Spanish.
    func duck(_ on: Bool) { mixer.musicVolume = on ? 0.35 : 1 }

    func suspend() {
        mixer.setMusic(nil)
        if started { engine.pause(); started = false }
    }

    func resume() { applyMusic() }
}
