import AVFoundation
import Foundation

enum MicrophoneRecorderError: LocalizedError {
    case microphoneDenied
    case alreadyRecording
    case notRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone permission is required."
        case .alreadyRecording:
            "MiniMix is already recording."
        case .notRecording:
            "MiniMix is not recording."
        }
    }
}

protocol MicrophoneRecording: Sendable {
    func start() async throws -> URL
    func stop() async throws -> URL
}

actor MicrophoneRecorder: MicrophoneRecording {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var outputURL: URL?

    func start() async throws -> URL {
        guard outputURL == nil else {
            throw MicrophoneRecorderError.alreadyRecording
        }

        guard await requestMicrophoneAccess() else {
            throw MicrophoneRecorderError.microphoneDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiniMix-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            try? audioFile.write(from: buffer)
        }

        engine.prepare()
        try engine.start()

        file = audioFile
        outputURL = url
        return url
    }

    func stop() async throws -> URL {
        guard let outputURL else {
            throw MicrophoneRecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        self.outputURL = nil

        return outputURL
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
