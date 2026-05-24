import Foundation

struct ManagedAudioApp: Identifiable, Equatable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let processIdentifier: Int32?
    let audioObjectID: UInt32?
    var volume: Double
    var isMuted: Bool
    var isProducingAudio: Bool
    var isDucked: Bool

    var effectiveVolume: Double {
        isMuted ? 0 : volume
    }

    var needsAudioProcessing: Bool {
        isMuted || volume < 0.999
    }

    var processingGain: Float {
        isMuted ? 0 : Float(max(0, min(volume, 1)))
    }

    var volumePercentText: String {
        "\(Int((effectiveVolume * 100).rounded()))%"
    }

    var detailText: String {
        var parts = [bundleIdentifier]
        if let processIdentifier {
            parts.append("pid \(processIdentifier)")
        }
        if let audioObjectID {
            parts.append("audio \(audioObjectID)")
        }
        if isProducingAudio {
            parts.append("active audio")
        }
        return parts.joined(separator: " · ")
    }
}
