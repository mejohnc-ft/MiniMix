import AppKit
import Foundation

protocol RunningAudioAppProviding {
    func runningApps() -> [ManagedAudioApp]
}

final class WorkspaceRunningAudioAppProvider: RunningAudioAppProviding {
    private let audioInspector: AudioProcessInspecting

    init(audioInspector: AudioProcessInspecting = CoreAudioProcessInspector()) {
        self.audioInspector = audioInspector
    }

    func runningApps() -> [ManagedAudioApp] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                    app.bundleIdentifier != nil &&
                    app.localizedName != nil
            }
            .map { app in
                let bundleIdentifier = app.bundleIdentifier ?? "unknown.\(app.processIdentifier)"
                let audioState = audioInspector.snapshot(for: app.processIdentifier)
                return ManagedAudioApp(
                    id: bundleIdentifier,
                    displayName: app.localizedName ?? bundleIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: app.processIdentifier,
                    audioObjectID: audioState.processObjectID,
                    volume: 1,
                    isMuted: false,
                    isProducingAudio: audioState.isRunningOutput,
                    isDucked: false
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }
}
