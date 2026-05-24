import Foundation
import Speech

enum AppleSpeechError: LocalizedError {
    case recognizerUnavailable
    case recognitionDenied
    case sourceUnsupported
    case noResult
    case timedOut

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "Apple Speech recognition is unavailable for the current locale."
        case .recognitionDenied:
            "Speech recognition permission is required."
        case .sourceUnsupported:
            "Apple Speech currently supports file transcription in MiniMix."
        case .noResult:
            "No transcription result was returned."
        case .timedOut:
            "Apple Speech transcription timed out."
        }
    }
}

final class AppleSpeechSTTEngine: STTEngine {
    private static let transcriptionTimeoutNanoseconds: UInt64 = 30_000_000_000

    private let locale: Locale
    private var loaded = false

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    var isLoaded: Bool {
        loaded
    }

    func load() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            throw AppleSpeechError.recognitionDenied
        }

        loaded = true
    }

    func transcribe(_ source: AudioSource) async throws -> Transcript {
        guard case let .file(url) = source else {
            throw AppleSpeechError.sourceUnsupported
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await performRecognition(request: request, recognizer: recognizer)
    }

    private func performRecognition(
        request: SFSpeechURLRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) async throws -> Transcript {
        try await withCheckedThrowingContinuation { continuation in
            let state = SpeechRecognitionContinuationState()

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    state.resumeOnce {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                state.resumeOnce {
                    continuation.resume(returning: Transcript(text: result.bestTranscription.formattedString))
                }
            }
            state.task = task

            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(Self.transcriptionTimeoutNanoseconds))) {
                state.resumeOnce {
                    continuation.resume(throwing: AppleSpeechError.timedOut)
                }
            }
        }
    }

    func unloadIfIdle() async {
        loaded = false
    }
}

private final class SpeechRecognitionContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    var task: SFSpeechRecognitionTask?

    func resumeOnce(_ resume: () -> Void) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }

        didResume = true
        let task = task
        lock.unlock()

        task?.cancel()
        resume()
    }
}
