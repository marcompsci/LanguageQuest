import Foundation

/// Original chiptune music and sound effects, synthesized at runtime.
/// No recorded or licensed audio. The app feeds `ChipMixer.render` into an
/// AVAudioSourceNode; everything here is pure and unit-tested.

public enum Waveform: Sendable, Equatable {
    case square(duty: Double)
    case triangle
    case noise
}

public struct ChipNote: Sendable, Equatable {
    /// MIDI note number (60 = middle C). nil = rest.
    public var midi: Int?
    public var beats: Double
    public init(_ midi: Int?, _ beats: Double) { self.midi = midi; self.beats = beats }
}

public struct ChipTrack: Sendable, Equatable {
    public var notes: [ChipNote]
    public var wave: Waveform
    public var volume: Float
    public var lengthBeats: Double { notes.reduce(0) { $0 + $1.beats } }
}

public struct ChipSong: Sendable, Equatable {
    public var bpm: Double
    public var tracks: [ChipTrack]
    public var loops: Bool
    public var lengthBeats: Double { tracks.map(\.lengthBeats).max() ?? 0 }
    public var lengthSeconds: Double { lengthBeats * 60 / bpm }

    /// Parses a compact melody string: "C5:1 E5:0.5 -:0.5" (note:beats, "-" = rest).
    public static func parse(_ s: String) -> [ChipNote] {
        s.split(separator: " ").compactMap { tok in
            let parts = tok.split(separator: ":")
            guard parts.count == 2, let beats = Double(parts[1]) else { return nil }
            return ChipNote(parts[0] == "-" ? nil : ChipSynth.midi(String(parts[0])), beats)
        }
    }
}

public enum ChipSynth {
    public static func frequency(midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// "C4" → 60, "A4" → 69, "F#3" → 54, "Bb4" → 70.
    public static func midi(_ name: String) -> Int? {
        let base: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var chars = Array(name)
        guard let letter = chars.first, let b = base[letter] else { return nil }
        chars.removeFirst()
        var acc = 0
        if chars.first == "#" { acc = 1; chars.removeFirst() } else if chars.first == "b" { acc = -1; chars.removeFirst() }
        guard let octave = Int(String(chars)) else { return nil }
        return (octave + 1) * 12 + b + acc
    }

    /// One sample of a waveform at phase 0..<1.
    public static func sample(_ w: Waveform, phase: Double, noiseState: inout UInt32) -> Float {
        switch w {
        case .square(let duty): return phase < duty ? 0.5 : -0.5
        case .triangle: return Float(phase < 0.5 ? (phase * 4 - 1) : (3 - phase * 4)) * 0.5
        case .noise:
            noiseState ^= noiseState << 13; noiseState ^= noiseState >> 17; noiseState ^= noiseState << 5
            return Float(Int32(bitPattern: noiseState)) / Float(Int32.max) * 0.4
        }
    }
}

/// Plays one song: tracks advance independently through their notes.
public struct ChipVoice: Sendable {
    public let song: ChipSong
    private var trackState: [(index: Int, remaining: Double, phase: Double)]
    private var noise: UInt32 = 0x1234_5678
    public private(set) var finished = false

    public init(_ song: ChipSong) {
        self.song = song
        trackState = song.tracks.map { (0, ($0.notes.first?.beats ?? 0) * 60 / song.bpm, 0) }
        if song.tracks.isEmpty { finished = true }
    }

    /// Returns the next mixed sample and advances time by 1/sampleRate.
    public mutating func next(sampleRate: Double) -> Float {
        guard !finished else { return 0 }
        let dt = 1 / sampleRate
        var out: Float = 0
        var allDone = true
        for t in song.tracks.indices {
            let track = song.tracks[t]
            var st = trackState[t]
            guard st.index < track.notes.count else { continue }
            allDone = false
            let note = track.notes[st.index]
            if let m = note.midi {
                let total = note.beats * 60 / song.bpm
                let elapsed = total - st.remaining
                // Short attack and release so notes don't click.
                let env = Float(min(1, elapsed / 0.005, st.remaining / 0.02))
                out += ChipSynth.sample(track.wave, phase: st.phase, noiseState: &noise) * track.volume * env
                st.phase += ChipSynth.frequency(midi: m) * dt
                st.phase -= floor(st.phase)
            }
            st.remaining -= dt
            if st.remaining <= 0 {
                st.index += 1
                if st.index >= track.notes.count, song.loops { st.index = 0 }
                if st.index < track.notes.count { st.remaining += track.notes[st.index].beats * 60 / song.bpm }
            }
            trackState[t] = st
        }
        if allDone { finished = true }
        return out
    }
}

public enum SoundEffect: String, CaseIterable, Sendable {
    case step, select, talk, correct, retry, reward, treasure, battleHit, coin

    public var song: ChipSong {
        func one(_ notes: String, _ wave: Waveform, _ vol: Float, bpm: Double = 600) -> ChipSong {
            ChipSong(bpm: bpm, tracks: [ChipTrack(notes: ChipSong.parse(notes), wave: wave, volume: vol)], loops: false)
        }
        switch self {
        case .step: return one("C2:0.25", .noise, 0.12)
        case .select: return one("A5:0.5", .square(duty: 0.25), 0.25)
        case .talk: return one("E5:0.25 G5:0.25", .square(duty: 0.5), 0.15)
        case .correct: return one("C5:0.5 E5:0.5 G5:0.5 C6:1.5", .square(duty: 0.25), 0.3)
        case .retry: return one("E4:0.75 C4:1.25", .triangle, 0.4)
        case .reward:
            return ChipSong(bpm: 300, tracks: [
                ChipTrack(notes: ChipSong.parse("G4:0.5 C5:0.5 E5:0.5 G5:1 E5:0.5 G5:2"), wave: .square(duty: 0.25), volume: 0.28),
                ChipTrack(notes: ChipSong.parse("C3:1 G3:1 C4:3"), wave: .triangle, volume: 0.35)], loops: false)
        case .treasure: return one("E6:0.25 G6:0.25 B6:0.25 E7:1", .square(duty: 0.125), 0.2, bpm: 480)
        case .battleHit: return one("C6:0.25 G5:0.25 C5:0.5", .square(duty: 0.5), 0.25)
        case .coin: return one("B5:0.25 E6:1", .square(duty: 0.25), 0.25)
        }
    }
}

public enum MusicTrack: String, CaseIterable, Sendable {
    case village, battle

    public var song: ChipSong {
        switch self {
        case .village:
            // An original, sunny 8-bar tune in C major.
            let melody = "E5:1 G5:0.5 E5:0.5 D5:1 C5:1 D5:1 E5:0.5 G5:0.5 A5:2 " +
                         "G5:1 E5:0.5 C5:0.5 D5:1 E5:1 C5:1 D5:0.5 B4:0.5 C5:2"
            let bass = "C3:2 G2:2 F2:2 C3:2 A2:2 F2:2 G2:2 C3:2"
            let tick = Array(repeating: "C2:0.5 -:0.5", count: 16).joined(separator: " ")
            return ChipSong(bpm: 112, tracks: [
                ChipTrack(notes: ChipSong.parse(melody), wave: .square(duty: 0.25), volume: 0.10),
                ChipTrack(notes: ChipSong.parse(bass), wave: .triangle, volume: 0.16),
                ChipTrack(notes: ChipSong.parse(tick), wave: .noise, volume: 0.03)], loops: true)
        case .battle:
            let melody = "A4:0.5 C5:0.5 E5:0.5 A5:0.5 G5:0.5 E5:0.5 C5:0.5 E5:0.5 " +
                         "F5:0.5 A5:0.5 G5:0.5 F5:0.5 E5:1 -:1"
            let bass = "A2:0.5 A2:0.5 A2:0.5 A2:0.5 C3:0.5 C3:0.5 C3:0.5 C3:0.5 F2:0.5 F2:0.5 F2:0.5 F2:0.5 E2:0.5 E2:0.5 E2:0.5 E2:0.5"
            return ChipSong(bpm: 140, tracks: [
                ChipTrack(notes: ChipSong.parse(melody), wave: .square(duty: 0.5), volume: 0.09),
                ChipTrack(notes: ChipSong.parse(bass), wave: .triangle, volume: 0.17)], loops: true)
        }
    }
}

/// Mixes background music with any number of sound effects.
/// `play`/`setMusic` may be called from any thread; `render` runs on the audio thread.
public final class ChipMixer: @unchecked Sendable {
    private let lock = NSLock()
    private var music: ChipVoice?
    private var effects: [ChipVoice] = []
    public var musicVolume: Float = 1
    public var effectsVolume: Float = 1
    public static let maxEffects = 6

    public init() {}

    public func setMusic(_ track: MusicTrack?) {
        lock.lock(); defer { lock.unlock() }
        if let t = track { if music?.song != t.song { music = ChipVoice(t.song) } } else { music = nil }
    }

    public func play(_ e: SoundEffect) {
        lock.lock(); defer { lock.unlock() }
        if effects.count >= Self.maxEffects { effects.removeFirst() }
        effects.append(ChipVoice(e.song))
    }

    public var activeEffects: Int { lock.lock(); defer { lock.unlock() }; return effects.count }

    /// Fills `count` mono samples.
    public func render(into buffer: UnsafeMutablePointer<Float>, count: Int, sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<count {
            var s: Float = 0
            if music != nil { s += music!.next(sampleRate: sampleRate) * musicVolume }
            for j in effects.indices { s += effects[j].next(sampleRate: sampleRate) * effectsVolume }
            buffer[i] = max(-1, min(1, s))
        }
        effects.removeAll { $0.finished }
    }
}
