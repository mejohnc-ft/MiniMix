import Foundation

@MainActor
final class MiniMixModel {
    private(set) var mixer: MixerState
    private(set) var voice: VoiceInputState
    private(set) var voicePermissions: VoicePermissionState
    private(set) var pushToTalkStatus = "Hotkey inactive"

    private let mixerController: MixerControlling
    private let voiceController: VoiceInputControlling
    private let hotkeyController: PushToTalkHotkeyControlling
    private var isStartingDictation = false
    private var stopRequestedDuringStart = false
    private var isShuttingDown = false
    private var startDictationTask: Task<Void, Never>?

    init(
        mixerController: MixerControlling = MixerController(),
        voiceController: VoiceInputControlling = VoiceInputController(),
        hotkeyController: PushToTalkHotkeyControlling = PushToTalkHotkeyController()
    ) {
        self.mixerController = mixerController
        self.voiceController = voiceController
        self.hotkeyController = hotkeyController
        self.mixer = mixerController.state
        self.voice = voiceController.state
        self.voicePermissions = VoicePermissionState.current()
        configurePushToTalk()
    }

    func refresh() {
        guard !voice.isActive else {
            voicePermissions = VoicePermissionState.current()
            return
        }

        mixerController.refresh()
        mixer = mixerController.state
        voice = voiceController.state
        voicePermissions = VoicePermissionState.current()
    }

    func setVolume(for appID: ManagedAudioApp.ID, to volume: Double) {
        mixerController.setVolume(for: appID, to: volume)
        mixer = mixerController.state
    }

    func toggleMute(for appID: ManagedAudioApp.ID) {
        mixerController.toggleMute(for: appID)
        mixer = mixerController.state
    }

    func resetApp(_ appID: ManagedAudioApp.ID) {
        mixerController.resetApp(appID)
        mixer = mixerController.state
    }

    func setIncludesInactiveApps(_ includesInactiveApps: Bool) {
        mixerController.setIncludesInactiveApps(includesInactiveApps)
        mixer = mixerController.state
    }

    func beginVoicePreview() {
        voiceController.beginPreview()
        voice = voiceController.state
        mixerController.beginVoiceDucking()
        mixer = mixerController.state
    }

    func endVoicePreview() {
        voiceController.endPreview()
        voice = voiceController.state
        mixerController.endVoiceDucking()
        mixer = mixerController.state
    }

    func startDictation() {
        guard !voice.isActive, !isStartingDictation, !isShuttingDown else {
            return
        }

        isStartingDictation = true
        mixerController.beginVoiceDucking()
        mixer = mixerController.state

        startDictationTask = Task { @MainActor in
            await startDictationNow(duckingAlreadyStarted: true)
            isStartingDictation = false
            startDictationTask = nil
        }
    }

    func stopDictation() {
        if isStartingDictation, !voice.isActive {
            stopRequestedDuringStart = true
            mixerController.endVoiceDucking()
            mixer = mixerController.state
            return
        }

        Task {
            await stopDictationNow()
        }
    }

    func requestVoicePermissions() {
        Task {
            voicePermissions = await VoicePermissionRequester.requestNeededPermissions()
        }
    }

    func startDictationNow() async {
        await startDictationNow(duckingAlreadyStarted: false)
    }

    private func startDictationNow(duckingAlreadyStarted: Bool) async {
        guard !isShuttingDown else {
            return
        }

        if !duckingAlreadyStarted {
            mixerController.beginVoiceDucking()
            mixer = mixerController.state
        }

        await voiceController.startDictation()
        voice = voiceController.state
        voicePermissions = VoicePermissionState.current()

        if isShuttingDown {
            await voiceController.cancelDictation()
            voice = voiceController.state
            mixerController.endVoiceDucking()
            mixer = mixerController.state
            return
        }

        let shouldStopAfterStart = stopRequestedDuringStart
        stopRequestedDuringStart = false

        if !voice.isActive {
            mixerController.endVoiceDucking()
            mixer = mixerController.state
        } else if shouldStopAfterStart {
            await stopDictationNow(duckingAlreadyEnded: true)
        }
    }

    func stopDictationNow() async {
        await stopDictationNow(duckingAlreadyEnded: false)
    }

    private func stopDictationNow(duckingAlreadyEnded: Bool) async {
        if !duckingAlreadyEnded {
            mixerController.endVoiceDucking()
            mixer = mixerController.state
        }

        await voiceController.stopDictation()
        voice = voiceController.state
        voicePermissions = VoicePermissionState.current()
    }

    func shutdown() {
        Task {
            await shutdownNow()
        }
    }

    func shutdownNow() async {
        isShuttingDown = true
        hotkeyController.stop()
        if voice.isActive || isStartingDictation {
            mixerController.endVoiceDucking()
            mixer = mixerController.state
        }

        if let startDictationTask {
            await startDictationTask.value
        }

        await voiceController.cancelDictation()
        voice = voiceController.state
        mixerController.shutdown()
        mixer = mixerController.state
    }

    private func configurePushToTalk() {
        hotkeyController.start(
            onPress: { [weak self] in
                guard let self, !voice.isActive else {
                    return
                }
                startDictation()
            },
            onRelease: { [weak self] in
                guard let self, voice.isActive || isStartingDictation else {
                    return
                }
                stopDictation()
            }
        )
        pushToTalkStatus = hotkeyController.statusText
    }

    func automationStatusLine() -> String {
        refresh()
        let transcriptPresent = !(voice.lastTranscript ?? "").isEmpty
        let errorPresent = !(voice.errorMessage ?? "").isEmpty
        let permissionsReady = voicePermissions.readiness == .ready
        return [
            "miniMixAutomationStatus",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "voiceStatus=\(automationStatusText(voice.status))",
            "voiceActive=\(voice.isActive)",
            "activeAudioSessionCount=\(mixer.activeAudioSessionCount)",
            "appCount=\(mixer.apps.count)",
            "transcriptPresent=\(transcriptPresent)",
            "errorPresent=\(errorPresent)",
            "permissionsReady=\(permissionsReady)"
        ].joined(separator: " ") + "\n"
    }

    private func automationStatusText(_ status: VoiceInputState.Status) -> String {
        switch status {
        case .idle:
            "idle"
        case .recordingPreview:
            "recordingPreview"
        case .recording:
            "recording"
        case .transcribing:
            "transcribing"
        }
    }
}
