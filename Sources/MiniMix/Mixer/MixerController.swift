import Foundation

@MainActor
protocol MixerControlling: AnyObject {
    var state: MixerState { get }
    func refresh()
    func setVolume(for appID: ManagedAudioApp.ID, to volume: Double)
    func toggleMute(for appID: ManagedAudioApp.ID)
    func resetApp(_ appID: ManagedAudioApp.ID)
    func beginVoiceDucking()
    func endVoiceDucking()
    func setIncludesInactiveApps(_ includesInactiveApps: Bool)
    func shutdown()
}

@MainActor
final class MixerController: MixerControlling {
    private var preDuckingState: [ManagedAudioApp.ID: (volume: Double, isMuted: Bool)] = [:]
    private let appProvider: RunningAudioAppProviding
    private let ruleStore: AudioRuleStoring
    private let audioEngine: PerAppAudioControlling
    private var includesInactiveApps = false

    private(set) var state = MixerState(apps: [], source: .runningApplications)

    init(
        appProvider: RunningAudioAppProviding = WorkspaceRunningAudioAppProvider(),
        ruleStore: AudioRuleStoring = UserDefaultsAudioRuleStore(),
        audioEngine: PerAppAudioControlling = CoreAudioPerAppAudioEngine()
    ) {
        self.appProvider = appProvider
        self.ruleStore = ruleStore
        self.audioEngine = audioEngine
        refresh()
    }

    func refresh() {
        let rules = ruleStore.loadRules()
        let discoveredApps = appProvider.runningApps()

        state = MixerState(
            apps: discoveredApps.compactMap { app in
                var copy = app
                if let rule = rules[app.bundleIdentifier] {
                    copy.volume = rule.volume
                    copy.isMuted = rule.isMuted
                }
                guard includesInactiveApps || copy.isProducingAudio || rules[copy.bundleIdentifier] != nil else {
                    return nil
                }
                return copy
            },
            source: .coreAudio,
            includesInactiveApps: includesInactiveApps,
            activeAudioSessionCount: audioEngine.diagnostics.activeSessionCount,
            audioEngineLastError: audioEngine.diagnostics.lastError,
            audioEngineRestartCount: audioEngine.diagnostics.restartCount
        )

        reconcileAudioSessions()
    }

    func setVolume(for appID: ManagedAudioApp.ID, to volume: Double) {
        update(appID) { app in
            app.volume = min(max(volume, 0), 1)
            app.isMuted = app.volume == 0
        }
        persistRule(for: appID)
        applyAudioRule(for: appID)
    }

    func toggleMute(for appID: ManagedAudioApp.ID) {
        update(appID) { app in
            app.isMuted.toggle()
        }
        persistRule(for: appID)
        applyAudioRule(for: appID)
    }

    func resetApp(_ appID: ManagedAudioApp.ID) {
        update(appID) { app in
            app.volume = 1
            app.isMuted = false
            app.isDucked = false
        }
        guard let app = state.apps.first(where: { $0.id == appID }) else {
            return
        }
        ruleStore.removeRule(for: app.bundleIdentifier)
        audioEngine.remove(bundleIdentifier: app.bundleIdentifier)
        updateEngineDiagnostics()
    }

    func beginVoiceDucking() {
        if preDuckingState.isEmpty {
            preDuckingState = Dictionary(
                uniqueKeysWithValues: state.apps.map { app in
                    (app.id, (volume: app.volume, isMuted: app.isMuted))
                }
            )
        }

        state.apps = state.apps.map { app in
            var copy = app
            if !copy.isMuted {
                copy.volume = min(copy.volume, 0.35)
                copy.isDucked = true
            }
            return copy
        }
        state.apps.forEach(audioEngine.apply(app:))
        updateEngineDiagnostics()
        state = state.withUpdatedTimestamp()
    }

    func endVoiceDucking() {
        state.apps = state.apps.map { app in
            var copy = app
            if let previous = preDuckingState[copy.id] {
                copy.volume = previous.volume
                copy.isMuted = previous.isMuted
                copy.isDucked = false
            }
            return copy
        }
        state.apps.forEach(audioEngine.apply(app:))
        updateEngineDiagnostics()
        preDuckingState.removeAll()
        state = state.withUpdatedTimestamp()
    }

    func setIncludesInactiveApps(_ includesInactiveApps: Bool) {
        self.includesInactiveApps = includesInactiveApps
        refresh()
    }

    func shutdown() {
        audioEngine.shutdown()
        updateEngineDiagnostics()
    }

    private func update(_ appID: ManagedAudioApp.ID, mutation: (inout ManagedAudioApp) -> Void) {
        guard let index = state.apps.firstIndex(where: { $0.id == appID }) else {
            return
        }

        mutation(&state.apps[index])
        state = state.withUpdatedTimestamp()
    }

    private func persistRule(for appID: ManagedAudioApp.ID) {
        guard let app = state.apps.first(where: { $0.id == appID }) else {
            return
        }

        if app.volume == 1, !app.isMuted {
            ruleStore.removeRule(for: app.bundleIdentifier)
        } else {
            ruleStore.saveRule(AudioAppRule(bundleIdentifier: app.bundleIdentifier, volume: app.volume, isMuted: app.isMuted))
        }
    }

    private func applyAudioRule(for appID: ManagedAudioApp.ID) {
        guard let app = state.apps.first(where: { $0.id == appID }) else {
            return
        }

        audioEngine.apply(app: app)
        updateEngineDiagnostics()
    }

    private func reconcileAudioSessions() {
        let currentBundleIDs = Set(state.apps.map(\.bundleIdentifier))

        for session in audioEngine.activeSessions where !currentBundleIDs.contains(session.bundleIdentifier) {
            audioEngine.remove(bundleIdentifier: session.bundleIdentifier)
        }

        for app in state.apps {
            audioEngine.apply(app: app)
        }

        updateEngineDiagnostics()
    }

    private func updateEngineDiagnostics() {
        let diagnostics = audioEngine.diagnostics
        state.activeAudioSessionCount = diagnostics.activeSessionCount
        state.audioEngineLastError = diagnostics.lastError
        state.audioEngineRestartCount = diagnostics.restartCount
    }
}
