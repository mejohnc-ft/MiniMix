import Foundation

struct VoiceInputState: Equatable {
    enum Status: Equatable {
        case idle
        case recordingPreview
        case recording
        case transcribing
    }

    var status: Status
    var engineName: String = "Not loaded"
    var lastTranscript: String?
    var errorMessage: String?

    var isActive: Bool {
        status != .idle
    }

    var label: String {
        switch status {
        case .idle:
            lastTranscript == nil ? "Idle" : "Ready"
        case .recordingPreview:
            "Ducking Preview"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        }
    }
}
