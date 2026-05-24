import Foundation

struct MixerState: Equatable {
    enum Source: Equatable {
        case runningApplications
        case coreAudio
    }

    var apps: [ManagedAudioApp]
    var source: Source
    var includesInactiveApps: Bool = false
    var activeAudioSessionCount: Int = 0
    var audioEngineLastError: String?
    var audioEngineRestartCount: Int = 0
    var lastUpdated: Date = .now

    var statusText: String {
        switch source {
        case .runningApplications:
            return apps.isEmpty ? "No regular apps found" : "\(apps.count) running app controls"
        case .coreAudio:
            if includesInactiveApps {
                return apps.isEmpty ? "No running apps found" : "\(apps.count) running app controls"
            }
            return apps.isEmpty ? "Listening for active app audio" : "\(apps.count) active audio controls"
        }
    }

    var footerText: String {
        switch source {
        case .runningApplications:
            "Discovery: running apps; no driver or daemon"
        case .coreAudio:
            if activeAudioSessionCount == 0 {
                "No active MiniMix taps"
            } else if activeAudioSessionCount == 1 {
                "1 active MiniMix tap"
            } else {
                "\(activeAudioSessionCount) active MiniMix taps"
            }
        }
    }

    func withUpdatedTimestamp() -> MixerState {
        var copy = self
        copy.lastUpdated = .now
        return copy
    }
}
