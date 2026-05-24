import Foundation

enum AudioSource: Equatable {
    case file(URL)
    case samples(RecordedAudio)
}

struct RecordedAudio: Equatable {
    let samples: [Float]
    let sampleRate: Double
}

struct Transcript: Equatable {
    let text: String
}

@MainActor
protocol STTEngine {
    var isLoaded: Bool { get }
    func load() async throws
    func transcribe(_ source: AudioSource) async throws -> Transcript
    func unloadIfIdle() async
}

struct UnconfiguredSTTEngine: STTEngine {
    var isLoaded: Bool { false }

    func load() async throws {}

    func transcribe(_ source: AudioSource) async throws -> Transcript {
        Transcript(text: "")
    }

    func unloadIfIdle() async {}
}
