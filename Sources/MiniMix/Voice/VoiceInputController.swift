import Foundation

@MainActor
protocol VoiceInputControlling: AnyObject {
    var state: VoiceInputState { get }
    func beginPreview()
    func endPreview()
    func startDictation() async
    func stopDictation() async
    func cancelDictation() async
}

@MainActor
final class VoiceInputController: VoiceInputControlling {
    private(set) var state = VoiceInputState(status: .idle)

    private let recorder: any MicrophoneRecording
    private let sttEngine: STTEngine
    private let textInjector: TextInjecting
    private var activeRecordingURL: URL?

    init(
        recorder: any MicrophoneRecording = MicrophoneRecorder(),
        sttEngine: STTEngine = AppleSpeechSTTEngine(),
        textInjector: TextInjecting = PasteboardTextInjector()
    ) {
        self.recorder = recorder
        self.sttEngine = sttEngine
        self.textInjector = textInjector
    }

    func beginPreview() {
        state = VoiceInputState(status: .recordingPreview)
    }

    func endPreview() {
        state = VoiceInputState(status: .idle)
    }

    func startDictation() async {
        do {
            activeRecordingURL = try await recorder.start()
            state = VoiceInputState(status: .recording, engineName: "Apple Speech")
        } catch {
            state = VoiceInputState(status: .idle, errorMessage: error.localizedDescription)
        }
    }

    func stopDictation() async {
        guard let activeRecordingURL else {
            state = VoiceInputState(status: .idle)
            return
        }

        do {
            let recordingURL = try await recorder.stop()
            self.activeRecordingURL = nil
            state = VoiceInputState(status: .transcribing, engineName: "Apple Speech")

            try await sttEngine.load()
            let transcript = try await sttEngine.transcribe(.file(recordingURL))
            if !transcript.text.isEmpty {
                try textInjector.insert(transcript.text)
            }

            await sttEngine.unloadIfIdle()

            state = VoiceInputState(
                status: .idle,
                engineName: "Apple Speech",
                lastTranscript: transcript.text
            )

            try? FileManager.default.removeItem(at: recordingURL)
        } catch {
            self.activeRecordingURL = nil
            await sttEngine.unloadIfIdle()
            state = VoiceInputState(status: .idle, engineName: "Apple Speech", errorMessage: error.localizedDescription)
            try? FileManager.default.removeItem(at: activeRecordingURL)
        }
    }

    func cancelDictation() async {
        guard let activeRecordingURL else {
            await sttEngine.unloadIfIdle()
            state = VoiceInputState(status: .idle)
            return
        }

        do {
            let recordingURL = try await recorder.stop()
            self.activeRecordingURL = nil
            await sttEngine.unloadIfIdle()
            state = VoiceInputState(status: .idle, engineName: "Apple Speech")
            try? FileManager.default.removeItem(at: recordingURL)
        } catch {
            self.activeRecordingURL = nil
            await sttEngine.unloadIfIdle()
            state = VoiceInputState(status: .idle, engineName: "Apple Speech", errorMessage: error.localizedDescription)
            try? FileManager.default.removeItem(at: activeRecordingURL)
        }
    }
}
