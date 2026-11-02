import AVFoundation
import Speech
import LQCore

/// Optional speaking check. On-device recognition ONLY: if the device can't
/// recognise the chosen Spanish locale offline, speaking falls back to the
/// no-microphone self-check. Audio is streamed to the recognizer in memory and
/// is never written to disk or sent anywhere.
@MainActor
final class SpeechRecognitionService: ObservableObject {
    enum Availability: Equatable {
        case available
        case notAllowedByParent
        case needsPermission
        case denied
        case unsupportedOnDevice
    }

    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// First speech locale for the variant that supports on-device recognition.
    static func recognizer(for v: LanguageVariant?) -> SFSpeechRecognizer? {
        for loc in v?.speechLocales ?? ["es-MX"] {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: loc)), r.supportsOnDeviceRecognition { return r }
        }
        return nil
    }

    func availability(variant: LanguageVariant?, parentAllowed: Bool) -> Availability {
        guard parentAllowed else { return .notAllowedByParent }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: break
        case .notDetermined: return .needsPermission
        default: return .denied
        }
        if AVAudioApplication.shared.recordPermission == .denied { return .denied }
        guard let r = Self.recognizer(for: variant), r.isAvailable else { return .unsupportedOnDevice }
        return .available
    }

    /// Asked only from the parent area, after a grown-up turns speech practice on.
    static func requestPermissions() async -> Bool {
        let speechOK: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(variant: LanguageVariant?) {
        stop()
        transcript = ""
        guard let recognizer = Self.recognizer(for: variant) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.requiresOnDeviceRecognition = true
            req.shouldReportPartialResults = true
            req.addsPunctuation = false

            let eng = AVAudioEngine()
            let input = eng.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            eng.prepare()
            try eng.start()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let done = (result?.isFinal ?? false) || error != nil
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if done { self.stop() }
                }
            }
            engine = eng
            request = req
            isListening = true
        } catch {
            stop()
        }
    }

    func stop() {
        if let eng = engine {
            eng.stop()
            eng.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }
}
