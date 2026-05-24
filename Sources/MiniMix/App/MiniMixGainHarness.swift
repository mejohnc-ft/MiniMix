import CoreAudio
import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Speech

enum MiniMixGainHarness {
    static var shouldRun: Bool {
        CommandLine.arguments.contains("--gain-harness") ||
            CommandLine.arguments.contains("--default-noop-harness") ||
            CommandLine.arguments.contains("--mute-harness") ||
            CommandLine.arguments.contains("--controller-harness") ||
            CommandLine.arguments.contains("--state-harness") ||
            CommandLine.arguments.contains("--process-inspector-harness") ||
            CommandLine.arguments.contains("--relaunch-harness") ||
            CommandLine.arguments.contains("--output-device-harness") ||
            CommandLine.arguments.contains("--active-benchmark-harness") ||
            CommandLine.arguments.contains("--multi-harness") ||
            CommandLine.arguments.contains("--voice-permission-harness") ||
            CommandLine.arguments.contains("--voice-permission-request-harness") ||
            CommandLine.arguments.contains("--microphone-recorder-harness") ||
            CommandLine.arguments.contains("--text-injector-harness") ||
            CommandLine.arguments.contains("--panel-focus-harness") ||
            CommandLine.arguments.contains("--apple-speech-harness") ||
            CommandLine.arguments.contains("--hotkey-harness") ||
            CommandLine.arguments.contains("--voice-harness") ||
            CommandLine.arguments.contains("--voice-real-recorder-harness") ||
            CommandLine.arguments.contains("--voice-shutdown-harness") ||
            CommandLine.arguments.contains("--voice-shutdown-during-start-harness") ||
            CommandLine.arguments.contains("--voice-early-release-harness") ||
            CommandLine.arguments.contains("--voice-hotkey-early-release-harness") ||
            CommandLine.arguments.contains("--voice-recorder-failure-harness") ||
            CommandLine.arguments.contains("--voice-mic-denied-harness") ||
            CommandLine.arguments.contains("--voice-speech-denied-harness") ||
            CommandLine.arguments.contains("--voice-accessibility-denied-harness") ||
            CommandLine.arguments.contains("--voice-paste-failure-harness") ||
            CommandLine.arguments.contains("--voice-stt-failure-harness")
    }

    @MainActor
    static func run() -> Int32 {
        if CommandLine.arguments.contains("--voice-harness") {
            return runVoiceHarness()
        }

        if CommandLine.arguments.contains("--voice-real-recorder-harness") {
            return runVoiceRealRecorderHarness()
        }

        if CommandLine.arguments.contains("--voice-shutdown-harness") {
            return runVoiceShutdownHarness()
        }

        if CommandLine.arguments.contains("--voice-shutdown-during-start-harness") {
            return runVoiceShutdownDuringStartHarness()
        }

        if CommandLine.arguments.contains("--voice-early-release-harness") {
            return runVoiceEarlyReleaseHarness()
        }

        if CommandLine.arguments.contains("--voice-hotkey-early-release-harness") {
            return runVoiceHotkeyEarlyReleaseHarness()
        }

        if CommandLine.arguments.contains("--voice-recorder-failure-harness") {
            return runVoiceRecorderFailureHarness()
        }

        if CommandLine.arguments.contains("--voice-mic-denied-harness") {
            return runVoiceMicDeniedHarness()
        }

        if CommandLine.arguments.contains("--voice-speech-denied-harness") {
            return runVoiceSpeechDeniedHarness()
        }

        if CommandLine.arguments.contains("--voice-accessibility-denied-harness") {
            return runVoiceAccessibilityDeniedHarness()
        }

        if CommandLine.arguments.contains("--voice-paste-failure-harness") {
            return runVoicePasteFailureHarness()
        }

        if CommandLine.arguments.contains("--voice-stt-failure-harness") {
            return runVoiceSTTFailureHarness()
        }

        if CommandLine.arguments.contains("--voice-permission-harness") {
            return runVoicePermissionHarness()
        }

        if CommandLine.arguments.contains("--voice-permission-request-harness") {
            return runVoicePermissionRequestHarness()
        }

        if CommandLine.arguments.contains("--microphone-recorder-harness") {
            return runMicrophoneRecorderHarness()
        }

        if CommandLine.arguments.contains("--text-injector-harness") {
            return runTextInjectorHarness()
        }

        if CommandLine.arguments.contains("--panel-focus-harness") {
            return runPanelFocusHarness()
        }

        if CommandLine.arguments.contains("--apple-speech-harness") {
            return runAppleSpeechHarness()
        }

        if CommandLine.arguments.contains("--hotkey-harness") {
            return runHotkeyHarness()
        }

        if CommandLine.arguments.contains("--controller-harness") {
            return runControllerHarness()
        }

        if CommandLine.arguments.contains("--state-harness") {
            return runStateHarness()
        }

        if CommandLine.arguments.contains("--process-inspector-harness") {
            return runProcessInspectorHarness()
        }

        if CommandLine.arguments.contains("--relaunch-harness") {
            return runRelaunchHarness()
        }

        if CommandLine.arguments.contains("--output-device-harness") {
            return runOutputDeviceHarness()
        }

        if CommandLine.arguments.contains("--active-benchmark-harness") {
            return runActiveBenchmarkHarness()
        }

        if CommandLine.arguments.contains("--multi-harness") {
            return runMultiHarness()
        }

        if CommandLine.arguments.contains("--default-noop-harness") {
            return runDefaultNoopHarness()
        }

        if CommandLine.arguments.contains("--mute-harness") {
            return runMuteHarness()
        }

        let gain = argument(after: "--gain-harness").flatMap(Double.init) ?? 0.35
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let pid = player.processIdentifier
            let audioState = CoreAudioProcessInspector().snapshot(for: pid)
            guard let audioObjectID = audioState.processObjectID else {
                fputs("Could not resolve Core Audio process object for pid \(pid)\n", stderr)
                player.terminate()
                return 3
            }

            let app = ManagedAudioApp(
                id: "com.apple.afplay",
                displayName: "afplay",
                bundleIdentifier: "com.apple.afplay",
                processIdentifier: pid,
                audioObjectID: audioObjectID,
                volume: gain,
                isMuted: false,
                isProducingAudio: audioState.isRunningOutput,
                isDucked: false
            )

            let engine = CoreAudioPerAppAudioEngine()
            engine.apply(app: app)
            Thread.sleep(forTimeInterval: 0.8)

            let activeAfterApply = engine.diagnostics.activeSessionCount
            let sessionsAfterApply = engine.activeSessions
            let errorAfterApply = engine.diagnostics.lastError
            let activeSession = sessionsAfterApply.first

            engine.remove(bundleIdentifier: app.bundleIdentifier)
            let activeAfterRemove = engine.diagnostics.activeSessionCount
            let sessionsAfterRemove = engine.activeSessions
            engine.shutdown()

            player.waitUntilExit()

            guard activeAfterApply == 1, sessionsAfterApply.count == 1, let activeSession else {
                fputs("Expected one active session after apply, got active=\(activeAfterApply) sessions=\(sessionsAfterApply). error=\(errorAfterApply ?? "nil")\n", stderr)
                return 4
            }

            guard activeSession.tapID != kAudioObjectUnknown, activeSession.aggregateDeviceID != kAudioObjectUnknown else {
                fputs("Expected active session to expose real tap and aggregate IDs, got \(activeSession)\n", stderr)
                return 5
            }

            guard abs(Double(activeSession.gain) - gain) < 0.0001, activeSession.isMuted == false else {
                fputs("Expected active gain=\(gain) unmuted=false? got gain=\(activeSession.gain) muted=\(activeSession.isMuted)\n", stderr)
                return 6
            }

            guard activeAfterRemove == 0 else {
                fputs("Expected zero active sessions after remove, got \(activeAfterRemove)\n", stderr)
                return 7
            }

            guard sessionsAfterRemove.isEmpty else {
                fputs("Expected no active sessions after remove, got \(sessionsAfterRemove)\n", stderr)
                return 8
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after cleanup, got \(tapCount)\n", stderr)
                return 9
            }

            print("gainHarness activeAfterApply=\(activeAfterApply) activeAfterRemove=\(activeAfterRemove) tapCount=\(tapCount) gain=\(gain) activeTapID=\(activeSession.tapID) activeAggregateDeviceID=\(activeSession.aggregateDeviceID) activeGain=\(activeSession.gain) activeMuted=\(activeSession.isMuted) sessionsAfterRemove=\(sessionsAfterRemove.count)")
            return 0
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func runDefaultNoopHarness() -> Int32 {
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let pid = player.processIdentifier
            let audioState = CoreAudioProcessInspector().snapshot(for: pid)
            guard let audioObjectID = audioState.processObjectID else {
                fputs("Could not resolve Core Audio process object for pid \(pid)\n", stderr)
                player.terminate()
                return 3
            }

            let defaultApp = ManagedAudioApp(
                id: "com.apple.afplay",
                displayName: "afplay",
                bundleIdentifier: "com.apple.afplay",
                processIdentifier: pid,
                audioObjectID: audioObjectID,
                volume: 1,
                isMuted: false,
                isProducingAudio: audioState.isRunningOutput,
                isDucked: false
            )

            let tapCountBefore = currentTapCount()
            let engine = CoreAudioPerAppAudioEngine()
            engine.apply(app: defaultApp)
            Thread.sleep(forTimeInterval: 0.3)

            let activeAfterDefault = engine.diagnostics.activeSessionCount
            let sessionsAfterDefault = engine.activeSessions
            let tapCountAfterDefault = currentTapCount()
            let errorAfterDefault = engine.diagnostics.lastError
            engine.shutdown()

            player.waitUntilExit()

            guard activeAfterDefault == 0, sessionsAfterDefault.isEmpty else {
                fputs("Expected default app to create no sessions, active=\(activeAfterDefault) sessions=\(sessionsAfterDefault) error=\(errorAfterDefault ?? "nil")\n", stderr)
                return 4
            }

            guard tapCountBefore == tapCountAfterDefault else {
                fputs("Expected default app to create no taps, before=\(tapCountBefore) after=\(tapCountAfterDefault)\n", stderr)
                return 5
            }

            emitHarnessLine("defaultNoopHarness activeAfterDefault=\(activeAfterDefault) tapCountBefore=\(tapCountBefore) tapCountAfterDefault=\(tapCountAfterDefault)")
            return 0
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func runMuteHarness() -> Int32 {
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let pid = player.processIdentifier
            let audioState = CoreAudioProcessInspector().snapshot(for: pid)
            guard let audioObjectID = audioState.processObjectID else {
                fputs("Could not resolve Core Audio process object for pid \(pid)\n", stderr)
                player.terminate()
                return 3
            }

            let mutedApp = ManagedAudioApp(
                id: "com.apple.afplay",
                displayName: "afplay",
                bundleIdentifier: "com.apple.afplay",
                processIdentifier: pid,
                audioObjectID: audioObjectID,
                volume: 1,
                isMuted: true,
                isProducingAudio: audioState.isRunningOutput,
                isDucked: false
            )

            let engine = CoreAudioPerAppAudioEngine()
            engine.apply(app: mutedApp)
            Thread.sleep(forTimeInterval: 0.8)

            let sessionsAfterMute = engine.activeSessions
            let activeAfterMute = engine.diagnostics.activeSessionCount
            let mutedSession = sessionsAfterMute.first { $0.bundleIdentifier == mutedApp.bundleIdentifier }
            let errorAfterMute = engine.diagnostics.lastError

            var unmutedDefaultApp = mutedApp
            unmutedDefaultApp.isMuted = false
            unmutedDefaultApp.volume = 1
            engine.apply(app: unmutedDefaultApp)
            let activeAfterUnmute = engine.diagnostics.activeSessionCount
            let sessionsAfterUnmute = engine.activeSessions
            engine.shutdown()

            player.waitUntilExit()

            guard activeAfterMute == 1, let mutedSession else {
                fputs("Expected one active muted session, got \(activeAfterMute). sessions=\(sessionsAfterMute) error=\(errorAfterMute ?? "nil")\n", stderr)
                return 4
            }

            guard mutedSession.isMuted, mutedSession.gain == 0 else {
                fputs("Expected muted zero-gain session, got \(mutedSession)\n", stderr)
                return 5
            }

            guard mutedSession.tapID != kAudioObjectUnknown, mutedSession.aggregateDeviceID != kAudioObjectUnknown else {
                fputs("Expected muted session to expose real tap and aggregate IDs, got \(mutedSession)\n", stderr)
                return 6
            }

            guard activeAfterUnmute == 0 else {
                fputs("Expected zero active sessions after unmute at 100%, got \(activeAfterUnmute)\n", stderr)
                return 7
            }

            guard sessionsAfterUnmute.isEmpty else {
                fputs("Expected no active sessions after unmute at 100%, got \(sessionsAfterUnmute)\n", stderr)
                return 8
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after mute cleanup, got \(tapCount)\n", stderr)
                return 9
            }

            emitHarnessLine("muteHarness activeAfterMute=\(activeAfterMute) muted=\(mutedSession.isMuted) gain=\(mutedSession.gain) activeAfterUnmute=\(activeAfterUnmute) tapCount=\(tapCount) activeTapID=\(mutedSession.tapID) activeAggregateDeviceID=\(mutedSession.aggregateDeviceID) sessionsAfterUnmute=\(sessionsAfterUnmute.count)")
            return 0
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runVoicePermissionHarness() -> Int32 {
        let permissions = VoicePermissionState.current()
        let ready = permissions.readiness == .ready
        let launchServicesPackaged = CommandLine.arguments.contains("--launchservices-packaged")
        let name = launchServicesPackaged ? "processVoicePermissionsLaunchServices" : "processVoicePermissionsHeadless"
        let line = "\(name) ready=\(ready) authoritativeForPackagedApp=\(launchServicesPackaged) summary=\(permissions.summary) detail=\(permissions.detailText)"
        emitHarnessLine(line)
        return ready ? 0 : 66
    }

    @MainActor
    private static func runVoicePermissionRequestHarness() -> Int32 {
        let launchServicesPackaged = CommandLine.arguments.contains("--launchservices-packaged")
        var permissions = VoicePermissionState.current()

        do {
            try awaitBlocking {
                permissions = await VoicePermissionRequester.requestNeededPermissions()
            }
        } catch {
            emitHarnessLine("voicePermissionRequestLaunchServices ready=false authoritativeForPackagedApp=\(launchServicesPackaged) error=\(error.localizedDescription)")
            return 1
        }

        let ready = permissions.readiness == .ready
        emitHarnessLine("voicePermissionRequestLaunchServices ready=\(ready) authoritativeForPackagedApp=\(launchServicesPackaged) summary=\(permissions.summary) detail=\(permissions.detailText)")
        return ready ? 0 : 66
    }

    @MainActor
    private static func runMicrophoneRecorderHarness() -> Int32 {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            emitHarnessLine("microphoneRecorderHarness ready=false status=\(microphoneAuthorizationStatusText(status))")
            return 66
        }

        let recorder = MicrophoneRecorder()
        var recordingURL: URL?

        do {
            try awaitBlocking {
                let startedURL = try await recorder.start()
                try await Task.sleep(for: .milliseconds(350))
                let stoppedURL = try await recorder.stop()

                guard startedURL == stoppedURL else {
                    throw HarnessError.unexpectedRecordingURL(started: startedURL.path, stopped: stoppedURL.path)
                }

                recordingURL = stoppedURL
            }

            guard let recordingURL else {
                emitHarnessLine("microphoneRecorderHarness ready=false error=missingRecordingURL")
                return 3
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)
            let byteCount = attributes[.size] as? UInt64 ?? 0
            try? FileManager.default.removeItem(at: recordingURL)

            guard byteCount > 0 else {
                emitHarnessLine("microphoneRecorderHarness ready=false error=emptyRecording path=\(recordingURL.path)")
                return 4
            }

            emitHarnessLine("microphoneRecorderHarness ready=true path=\(recordingURL.path) bytes=\(byteCount)")
            return 0
        } catch {
            if let recordingURL {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            emitHarnessLine("microphoneRecorderHarness ready=false error=\(error.localizedDescription)")
            return 1
        }
    }

    @MainActor
    private static func runTextInjectorHarness() -> Int32 {
        let trusted = AXIsProcessTrusted()
        emitHarnessLine("textInjectorHarness ready=\(trusted) accessibility=\(trusted ? "trusted" : "notTrusted") action=readinessOnly")
        return trusted ? 0 : 66
    }

    @MainActor
    private static func runPanelFocusHarness() -> Int32 {
        let panel = MiniMixPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 460)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let nonactivating = panel.styleMask.contains(.nonactivatingPanel)
        let cannotBecomeKey = !panel.canBecomeKey
        let cannotBecomeMain = !panel.canBecomeMain
        let cannotBecomeFirstResponder = !panel.acceptsFirstResponder
        let stableWhenAppDeactivates = !panel.hidesOnDeactivate
        let keyOnlyIfNeeded = panel.becomesKeyOnlyIfNeeded

        print("panelFocusHarness nonactivating=\(nonactivating) cannotBecomeKey=\(cannotBecomeKey) cannotBecomeMain=\(cannotBecomeMain) cannotBecomeFirstResponder=\(cannotBecomeFirstResponder) hidesOnDeactivate=\(panel.hidesOnDeactivate) becomesKeyOnlyIfNeeded=\(keyOnlyIfNeeded)")

        guard nonactivating, cannotBecomeKey, cannotBecomeMain, cannotBecomeFirstResponder, stableWhenAppDeactivates, keyOnlyIfNeeded else {
            return 4
        }
        return 0
    }

    @MainActor
    private static func runHotkeyHarness() -> Int32 {
        let firstController = PushToTalkHotkeyController()
        var pressCount = 0
        var releaseCount = 0

        firstController.start(
            onPress: {
                pressCount += 1
            },
            onRelease: {
                releaseCount += 1
            }
        )

        guard firstController.statusText == "Hold Control-Option-Space" else {
            fputs("Expected Control-Option-Space registration, got '\(firstController.statusText)'\n", stderr)
            firstController.stop()
            return 2
        }

        firstController.stop()

        let secondController = PushToTalkHotkeyController()
        secondController.start(onPress: {}, onRelease: {})
        guard secondController.statusText == "Hold Control-Option-Space" else {
            fputs("Expected Control-Option-Space to be reusable after stop, got '\(secondController.statusText)'\n", stderr)
            secondController.stop()
            return 3
        }
        secondController.stop()

        emitHarnessLine("hotkeyHarness registered=true reusableAfterStop=true pressCount=\(pressCount) releaseCount=\(releaseCount)")
        return 0
    }

    @MainActor
    private static func runAppleSpeechHarness() -> Int32 {
        guard AppleSpeechSTTEngine.authorizationStatus == .authorized else {
            emitHarnessLine("appleSpeechHarness ready=false status=\(speechAuthorizationStatusText(AppleSpeechSTTEngine.authorizationStatus))")
            return 66
        }

        let text = argument(after: "--text") ?? "MiniMix speech baseline"
        let audioURL = URL(fileURLWithPath: argument(after: "--speech-audio") ?? "/tmp/minimix-apple-speech-harness.aiff")

        do {
            if !FileManager.default.fileExists(atPath: audioURL.path) {
                try generateSpeechFixture(text: text, outputURL: audioURL)
            }

            let engine = AppleSpeechSTTEngine()
            try awaitBlocking {
                try await engine.load()
                let transcript = try await engine.transcribe(.file(audioURL))
                await engine.unloadIfIdle()

                let normalizedTranscript = normalizeForComparison(transcript.text)
                let normalizedExpected = normalizeForComparison(text)
                guard normalizedTranscript.contains(normalizedExpected) else {
                    throw HarnessError.unexpectedTranscript(expected: text, actual: transcript.text)
                }

                emitHarnessLine("appleSpeechHarness ready=true transcript=\(transcript.text) unloaded=\(!engine.isLoaded)")
            }
            return 0
        } catch {
            emitHarnessLine("appleSpeechHarness ready=false error=\(error.localizedDescription)")
            return 1
        }
    }

    @MainActor
    private static func runStateHarness() -> Int32 {
        let activeApp = ManagedAudioApp(
            id: "dev.minimix.harness.active",
            displayName: "Active Harness App",
            bundleIdentifier: "dev.minimix.harness.active",
            processIdentifier: nil,
            audioObjectID: nil,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )
        let inactiveApp = ManagedAudioApp(
            id: "dev.minimix.harness.inactive",
            displayName: "Inactive Harness App",
            bundleIdentifier: "dev.minimix.harness.inactive",
            processIdentifier: nil,
            audioObjectID: nil,
            volume: 1,
            isMuted: false,
            isProducingAudio: false,
            isDucked: false
        )

        let suiteName = "dev.minimix.harness.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("Could not create isolated UserDefaults suite\n", stderr)
            return 2
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let provider = HarnessRunningAudioAppProvider(apps: [activeApp, inactiveApp])
        let store = UserDefaultsAudioRuleStore(defaults: defaults)
        let trackingEngine = HarnessTrackingAudioEngine()
        let controller = MixerController(
            appProvider: provider,
            ruleStore: store,
            audioEngine: trackingEngine
        )

        let initialIDs = Set(controller.state.apps.map(\.id))
        guard initialIDs == Set([activeApp.id]) else {
            fputs("Expected only active app initially, got \(initialIDs)\n", stderr)
            return 3
        }

        controller.setIncludesInactiveApps(true)
        let allIDs = Set(controller.state.apps.map(\.id))
        guard allIDs == Set([activeApp.id, inactiveApp.id]) else {
            fputs("Expected active and inactive apps in All Apps mode, got \(allIDs)\n", stderr)
            return 4
        }

        controller.setVolume(for: activeApp.id, to: 1)
        guard store.loadRules()[activeApp.bundleIdentifier] == nil, trackingEngine.activeSessions.isEmpty else {
            fputs("Expected default 100% rule to be a no-op, rules=\(store.loadRules()) sessions=\(trackingEngine.activeSessions)\n", stderr)
            return 10
        }

        controller.toggleMute(for: inactiveApp.id)
        let mutedRule = store.loadRules()[inactiveApp.bundleIdentifier]
        let mutedSession = trackingEngine.activeSessions.first { $0.bundleIdentifier == inactiveApp.bundleIdentifier }
        guard mutedRule?.isMuted == true, mutedSession?.isMuted == true, mutedSession?.gain == 0 else {
            fputs("Expected inactive app mute rule and zero-gain session, rule=\(String(describing: mutedRule)) sessions=\(trackingEngine.activeSessions)\n", stderr)
            return 11
        }

        controller.toggleMute(for: inactiveApp.id)
        guard store.loadRules()[inactiveApp.bundleIdentifier] == nil, trackingEngine.activeSessions.isEmpty else {
            fputs("Expected unmute at 100% to remove inactive app rule/session, rules=\(store.loadRules()) sessions=\(trackingEngine.activeSessions)\n", stderr)
            return 12
        }

        controller.setVolume(for: inactiveApp.id, to: 0.42)
        guard store.loadRules()[inactiveApp.bundleIdentifier]?.volume == 0.42 else {
            fputs("Expected inactive app rule to persist at 0.42, got \(String(describing: store.loadRules()[inactiveApp.bundleIdentifier]))\n", stderr)
            return 5
        }

        guard trackingEngine.activeSessions.map(\.bundleIdentifier) == [inactiveApp.bundleIdentifier] else {
            fputs("Expected tracking engine to manage inactive app after rule, got \(trackingEngine.activeSessions)\n", stderr)
            return 6
        }

        provider.apps = [activeApp]
        controller.refresh()
        guard trackingEngine.activeSessions.isEmpty else {
            fputs("Expected disappeared app session to be removed, got \(trackingEngine.activeSessions)\n", stderr)
            return 7
        }

        provider.apps = [activeApp, inactiveApp]
        let reloadedController = MixerController(
            appProvider: provider,
            ruleStore: UserDefaultsAudioRuleStore(defaults: defaults),
            audioEngine: DisabledPerAppAudioEngine()
        )
        let reloadedApp = reloadedController.state.apps.first { $0.id == inactiveApp.id }
        guard reloadedApp?.volume == 0.42 else {
            fputs("Expected persisted inactive app rule to make app visible after reload, got \(String(describing: reloadedApp))\n", stderr)
            return 8
        }

        reloadedController.resetApp(inactiveApp.id)
        guard store.loadRules()[inactiveApp.bundleIdentifier] == nil else {
            fputs("Expected reset to remove persisted inactive app rule\n", stderr)
            return 9
        }

        emitHarnessLine("stateHarness initialVisible=\(initialIDs.count) allAppsVisible=\(allIDs.count) defaultRuleNoop=true mutePersisted=true unmuteRemovedRule=true persistedVolume=0.42 disappearedRemovedSession=true reloadedRuleVisible=true resetRemovedRule=true")
        return 0
    }

    private static func runProcessInspectorHarness() -> Int32 {
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = audioPlayer(soundPath: soundPath)
        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.2)

            let pid = player.processIdentifier
            let snapshot = CoreAudioProcessInspector().snapshot(for: pid)
            player.terminate()
            player.waitUntilExit()

            guard let processObjectID = snapshot.processObjectID, processObjectID != kAudioObjectUnknown else {
                fputs("Expected Core Audio process object for pid \(pid), got \(String(describing: snapshot.processObjectID))\n", stderr)
                return 3
            }

            guard snapshot.isRunningOutput else {
                fputs("Expected Core Audio running-output state for pid \(pid), processObjectID=\(processObjectID)\n", stderr)
                return 4
            }

            print("processInspectorHarness pid=\(pid) audioObjectID=\(processObjectID) runningOutput=\(snapshot.isRunningOutput)")
            return 0
        } catch {
            if player.isRunning {
                player.terminate()
            }
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runRelaunchHarness() -> Int32 {
        let bundleIdentifier = "dev.minimix.harness.relaunch"
        let volume = 0.31
        let oldApp = ManagedAudioApp(
            id: bundleIdentifier,
            displayName: "Relaunch Harness App",
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 1111,
            audioObjectID: 1001,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )
        let relaunchedApp = ManagedAudioApp(
            id: bundleIdentifier,
            displayName: "Relaunch Harness App",
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 2222,
            audioObjectID: 2002,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let provider = HarnessRunningAudioAppProvider(apps: [oldApp])
        let store = HarnessAudioRuleStore()
        let trackingEngine = HarnessTrackingAudioEngine()
        let controller = MixerController(
            appProvider: provider,
            ruleStore: store,
            audioEngine: trackingEngine
        )

        controller.setVolume(for: oldApp.id, to: volume)
        let oldSessionApplied = trackingEngine.activeSessions.count == 1 &&
            trackingEngine.appliedApps[bundleIdentifier]?.processIdentifier == oldApp.processIdentifier &&
            store.rules[bundleIdentifier]?.volume == volume
        guard oldSessionApplied else {
            fputs("Expected old process session and persisted rule, sessions=\(trackingEngine.activeSessions) applied=\(String(describing: trackingEngine.appliedApps[bundleIdentifier])) rules=\(store.rules)\n", stderr)
            return 2
        }

        provider.apps = []
        controller.refresh()
        let disappearedRemovedSession = trackingEngine.activeSessions.isEmpty
        guard disappearedRemovedSession else {
            fputs("Expected disappeared app session to be removed, got \(trackingEngine.activeSessions)\n", stderr)
            return 3
        }

        provider.apps = [relaunchedApp]
        controller.refresh()
        let visibleRelaunchedApp = controller.state.apps.first { $0.id == relaunchedApp.id }
        let relaunchedRuleVisible = visibleRelaunchedApp?.volume == volume &&
            visibleRelaunchedApp?.processIdentifier == relaunchedApp.processIdentifier
        let relaunchedSessionApplied = trackingEngine.activeSessions.count == 1 &&
            trackingEngine.appliedApps[bundleIdentifier]?.processIdentifier == relaunchedApp.processIdentifier

        guard relaunchedRuleVisible, relaunchedSessionApplied else {
            fputs("Expected persisted rule to apply to relaunched process, visible=\(String(describing: visibleRelaunchedApp)) sessions=\(trackingEngine.activeSessions) applied=\(String(describing: trackingEngine.appliedApps[bundleIdentifier]))\n", stderr)
            return 4
        }

        controller.resetApp(relaunchedApp.id)
        let resetRemovedSession = trackingEngine.activeSessions.isEmpty
        let resetRemovedRule = store.rules[bundleIdentifier] == nil
        guard resetRemovedSession, resetRemovedRule else {
            fputs("Expected reset to remove relaunched session and rule, sessions=\(trackingEngine.activeSessions) rules=\(store.rules)\n", stderr)
            return 5
        }

        emitHarnessLine("relaunchHarness oldSessionApplied=\(oldSessionApplied) disappearedRemovedSession=\(disappearedRemovedSession) relaunchedRuleVisible=\(relaunchedRuleVisible) relaunchedSessionApplied=\(relaunchedSessionApplied) resetRemovedSession=\(resetRemovedSession) resetRemovedRule=\(resetRemovedRule)")
        return 0
    }

    @MainActor
    private static func runOutputDeviceHarness() -> Int32 {
        let gain = argument(after: "--output-device-harness").flatMap(Double.init) ?? 0.35
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = audioPlayer(soundPath: soundPath)
        let engine = CoreAudioPerAppAudioEngine()

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let app = try managedApp(
                process: player,
                displayName: "afplay output device",
                bundleIdentifier: "dev.minimix.harness.output-device",
                volume: gain
            )

            engine.apply(app: app)
            Thread.sleep(forTimeInterval: 0.4)
            let activeBeforeRestart = engine.diagnostics.activeSessionCount
            let restartCountBefore = engine.diagnostics.restartCount
            let sessionsBeforeRestart = engine.activeSessions
            let errorBeforeRestart = engine.diagnostics.lastError

            engine.simulateOutputDeviceChangeForTesting()

            Thread.sleep(forTimeInterval: 0.4)
            let activeAfterRestart = engine.diagnostics.activeSessionCount
            let restartCountAfter = engine.diagnostics.restartCount
            let sessionsAfterRestart = engine.activeSessions
            let errorAfterRestart = engine.diagnostics.lastError

            engine.remove(bundleIdentifier: app.bundleIdentifier)
            let activeAfterRemove = engine.diagnostics.activeSessionCount
            let sessionsAfterRemove = engine.activeSessions
            engine.shutdown()
            player.waitUntilExit()

            guard activeBeforeRestart == 1, sessionsBeforeRestart.count == 1, let sessionBeforeRestart = sessionsBeforeRestart.first else {
                fputs("Expected one active session before output-device restart, got \(activeBeforeRestart). error=\(errorBeforeRestart ?? "nil") sessions=\(sessionsBeforeRestart)\n", stderr)
                return 4
            }

            guard activeAfterRestart == 1, sessionsAfterRestart.count == 1, let sessionAfterRestart = sessionsAfterRestart.first else {
                fputs("Expected one active session after output-device restart, got \(activeAfterRestart). error=\(errorAfterRestart ?? "nil") sessions=\(sessionsAfterRestart)\n", stderr)
                return 5
            }

            guard sessionBeforeRestart.tapID != kAudioObjectUnknown, sessionBeforeRestart.aggregateDeviceID != kAudioObjectUnknown, sessionAfterRestart.tapID != kAudioObjectUnknown, sessionAfterRestart.aggregateDeviceID != kAudioObjectUnknown else {
                fputs("Expected sessions before/after restart to expose real tap and aggregate IDs, before=\(sessionBeforeRestart) after=\(sessionAfterRestart)\n", stderr)
                return 6
            }

            guard sessionBeforeRestart.tapID != sessionAfterRestart.tapID, sessionBeforeRestart.aggregateDeviceID != sessionAfterRestart.aggregateDeviceID else {
                fputs("Expected output-device restart to recreate tap and aggregate IDs, before=\(sessionBeforeRestart) after=\(sessionAfterRestart)\n", stderr)
                return 7
            }

            guard abs(Double(sessionBeforeRestart.gain) - gain) < 0.0001, abs(Double(sessionAfterRestart.gain) - gain) < 0.0001 else {
                fputs("Expected gain \(gain) before/after restart, before=\(sessionBeforeRestart.gain) after=\(sessionAfterRestart.gain)\n", stderr)
                return 8
            }

            guard restartCountAfter == restartCountBefore + 1 else {
                fputs("Expected restart count to increase by one, before=\(restartCountBefore) after=\(restartCountAfter)\n", stderr)
                return 9
            }

            guard activeAfterRemove == 0 else {
                fputs("Expected zero active sessions after remove, got \(activeAfterRemove)\n", stderr)
                return 10
            }

            guard sessionsAfterRemove.isEmpty else {
                fputs("Expected no active sessions after remove, got \(sessionsAfterRemove)\n", stderr)
                return 11
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after cleanup, got \(tapCount)\n", stderr)
                return 12
            }

            emitHarnessLine("outputDeviceHarness activeBeforeRestart=\(activeBeforeRestart) activeAfterRestart=\(activeAfterRestart) restartCountBefore=\(restartCountBefore) restartCountAfter=\(restartCountAfter) activeAfterRemove=\(activeAfterRemove) tapCount=\(tapCount) gain=\(gain) tapBeforeRestart=\(sessionBeforeRestart.tapID) aggregateBeforeRestart=\(sessionBeforeRestart.aggregateDeviceID) tapAfterRestart=\(sessionAfterRestart.tapID) aggregateAfterRestart=\(sessionAfterRestart.aggregateDeviceID) gainAfterRestart=\(sessionAfterRestart.gain) sessionsAfterRemove=\(sessionsAfterRemove.count)")
            return 0
        } catch {
            engine.shutdown()
            player.terminate()
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runActiveBenchmarkHarness() -> Int32 {
        let gain = argument(after: "--active-benchmark-harness").flatMap(Double.init) ?? 0.35
        let duration = max(1, argument(after: "--duration").flatMap(TimeInterval.init) ?? 30)
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = audioPlayer(soundPath: soundPath)
        let engine = CoreAudioPerAppAudioEngine()

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let app = try managedApp(
                process: player,
                displayName: "afplay active benchmark",
                bundleIdentifier: "dev.minimix.harness.active-benchmark",
                volume: gain
            )

            engine.apply(app: app)
            Thread.sleep(forTimeInterval: 0.4)

            let activeDuringBenchmark = engine.diagnostics.activeSessionCount
            let errorDuringBenchmark = engine.diagnostics.lastError
            guard activeDuringBenchmark == 1 else {
                fputs("Expected one active session during benchmark, got \(activeDuringBenchmark). error=\(errorDuringBenchmark ?? "nil")\n", stderr)
                engine.shutdown()
                player.terminate()
                return 3
            }

            print("activeBenchmarkHarness ready=true activeSessionCount=\(activeDuringBenchmark) duration=\(duration) gain=\(gain)")
            fflush(stdout)
            spinRunLoop(for: duration)

            engine.remove(bundleIdentifier: app.bundleIdentifier)
            let activeAfterRemove = engine.diagnostics.activeSessionCount
            engine.shutdown()

            if player.isRunning {
                player.terminate()
            }
            player.waitUntilExit()
            spinRunLoop(for: 0.5)

            guard activeAfterRemove == 0 else {
                fputs("Expected zero active sessions after benchmark remove, got \(activeAfterRemove)\n", stderr)
                return 4
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after cleanup, got \(tapCount)\n", stderr)
                return 5
            }

            print("activeBenchmarkHarness complete=true activeAfterRemove=\(activeAfterRemove) tapCount=\(tapCount) gain=\(gain)")
            return 0
        } catch {
            engine.shutdown()
            if player.isRunning {
                player.terminate()
            }
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runMultiHarness() -> Int32 {
        let firstGain = argument(after: "--first-gain").flatMap(Double.init) ?? 0.35
        let secondGain = argument(after: "--second-gain").flatMap(Double.init) ?? 0.55
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let firstPlayer = audioPlayer(soundPath: soundPath)
        let secondPlayer = audioPlayer(soundPath: soundPath)
        let engine = CoreAudioPerAppAudioEngine()

        do {
            try firstPlayer.run()
            try secondPlayer.run()
            Thread.sleep(forTimeInterval: 0.2)

            let firstApp = try managedApp(
                process: firstPlayer,
                displayName: "afplay one",
                bundleIdentifier: "dev.minimix.harness.afplay.one",
                volume: firstGain
            )
            let secondApp = try managedApp(
                process: secondPlayer,
                displayName: "afplay two",
                bundleIdentifier: "dev.minimix.harness.afplay.two",
                volume: secondGain
            )

            engine.apply(app: firstApp)
            engine.apply(app: secondApp)
            Thread.sleep(forTimeInterval: 0.8)

            let activeAfterApply = engine.diagnostics.activeSessionCount
            let sessionsAfterApply = engine.activeSessions
            let errorAfterApply = engine.diagnostics.lastError

            engine.remove(bundleIdentifier: firstApp.bundleIdentifier)
            let activeAfterFirstRemove = engine.diagnostics.activeSessionCount
            let sessionsAfterFirstRemove = engine.activeSessions

            engine.remove(bundleIdentifier: secondApp.bundleIdentifier)
            let activeAfterSecondRemove = engine.diagnostics.activeSessionCount
            let sessionsAfterSecondRemove = engine.activeSessions
            engine.shutdown()

            firstPlayer.waitUntilExit()
            secondPlayer.waitUntilExit()

            guard activeAfterApply == 2 else {
                fputs("Expected two active sessions after apply, got \(activeAfterApply). error=\(errorAfterApply ?? "nil") sessions=\(sessionsAfterApply)\n", stderr)
                return 4
            }

            guard Set(sessionsAfterApply.map(\.bundleIdentifier)) == Set([firstApp.bundleIdentifier, secondApp.bundleIdentifier]) else {
                fputs("Expected active sessions for both harness apps, got \(sessionsAfterApply)\n", stderr)
                return 5
            }

            let sessionsByBundle = Dictionary(uniqueKeysWithValues: sessionsAfterApply.map { ($0.bundleIdentifier, $0) })
            guard let firstSession = sessionsByBundle[firstApp.bundleIdentifier], let secondSession = sessionsByBundle[secondApp.bundleIdentifier] else {
                fputs("Expected lookupable active sessions for both harness apps, got \(sessionsAfterApply)\n", stderr)
                return 6
            }

            guard firstSession.tapID != kAudioObjectUnknown, firstSession.aggregateDeviceID != kAudioObjectUnknown, secondSession.tapID != kAudioObjectUnknown, secondSession.aggregateDeviceID != kAudioObjectUnknown else {
                fputs("Expected both sessions to expose real tap and aggregate IDs, got first=\(firstSession) second=\(secondSession)\n", stderr)
                return 7
            }

            guard firstSession.tapID != secondSession.tapID, firstSession.aggregateDeviceID != secondSession.aggregateDeviceID else {
                fputs("Expected independent tap and aggregate IDs, got first=\(firstSession) second=\(secondSession)\n", stderr)
                return 8
            }

            guard abs(Double(firstSession.gain) - firstGain) < 0.0001, abs(Double(secondSession.gain) - secondGain) < 0.0001 else {
                fputs("Expected independent gains \(firstGain),\(secondGain), got first=\(firstSession.gain) second=\(secondSession.gain)\n", stderr)
                return 9
            }

            guard activeAfterFirstRemove == 1 else {
                fputs("Expected one active session after first remove, got \(activeAfterFirstRemove)\n", stderr)
                return 10
            }

            guard sessionsAfterFirstRemove.count == 1, sessionsAfterFirstRemove.first?.bundleIdentifier == secondApp.bundleIdentifier else {
                fputs("Expected only second session after first remove, got \(sessionsAfterFirstRemove)\n", stderr)
                return 11
            }

            guard activeAfterSecondRemove == 0 else {
                fputs("Expected zero active sessions after second remove, got \(activeAfterSecondRemove)\n", stderr)
                return 12
            }

            guard sessionsAfterSecondRemove.isEmpty else {
                fputs("Expected no active sessions after second remove, got \(sessionsAfterSecondRemove)\n", stderr)
                return 13
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after cleanup, got \(tapCount)\n", stderr)
                return 14
            }

            emitHarnessLine("multiHarness activeAfterApply=\(activeAfterApply) activeAfterFirstRemove=\(activeAfterFirstRemove) activeAfterSecondRemove=\(activeAfterSecondRemove) tapCount=\(tapCount) gains=\(firstGain),\(secondGain) firstTapID=\(firstSession.tapID) firstAggregateDeviceID=\(firstSession.aggregateDeviceID) firstActiveGain=\(firstSession.gain) secondTapID=\(secondSession.tapID) secondAggregateDeviceID=\(secondSession.aggregateDeviceID) secondActiveGain=\(secondSession.gain) sessionsAfterFirstRemove=\(sessionsAfterFirstRemove.count) sessionsAfterSecondRemove=\(sessionsAfterSecondRemove.count)")
            return 0
        } catch {
            firstPlayer.terminate()
            secondPlayer.terminate()
            engine.shutdown()
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runVoiceHarness() -> Int32 {
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"
        let transcript = argument(after: "--transcript") ?? "MiniMix voice harness"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let pid = player.processIdentifier
            let audioState = CoreAudioProcessInspector().snapshot(for: pid)
            guard let audioObjectID = audioState.processObjectID else {
                fputs("Could not resolve Core Audio process object for pid \(pid)\n", stderr)
                player.terminate()
                return 3
            }

            let app = ManagedAudioApp(
                id: "com.apple.afplay",
                displayName: "afplay",
                bundleIdentifier: "com.apple.afplay",
                processIdentifier: pid,
                audioObjectID: audioObjectID,
                volume: 1,
                isMuted: false,
                isProducingAudio: true,
                isDucked: false
            )

            let textInjector = HarnessTextInjector()
            let sttEngine = HarnessSTTEngine(transcript: transcript)
            let model = MiniMixModel(
                mixerController: MixerController(
                    appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                    ruleStore: HarnessAudioRuleStore(),
                    audioEngine: CoreAudioPerAppAudioEngine()
                ),
                voiceController: VoiceInputController(
                    recorder: HarnessMicrophoneRecorder(),
                    sttEngine: sttEngine,
                    textInjector: textInjector
                ),
                hotkeyController: HarnessHotkeyController()
            )

            model.startDictation()
            let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
            let immediateDuckedVolume = model.mixer.apps.first?.volume

            spinRunLoop(for: 0.4)

            let activeWhileRecording = model.mixer.activeAudioSessionCount
            let duckedVolume = model.mixer.apps.first?.volume
            let voiceStatusDuringRecording = model.voice.status
            let sttLoadedWhileRecording = sttEngine.isLoaded

            model.stopDictation()
            spinRunLoop(for: 0.4)

            let activeAfterStop = model.mixer.activeAudioSessionCount
            let restoredVolume = model.mixer.apps.first?.volume
            let insertedText = textInjector.insertedText
            let lastTranscript = model.voice.lastTranscript
            let sttLoadedAfterStop = sttEngine.isLoaded

            model.shutdown()
            player.waitUntilExit()

            guard immediateActiveAfterPress == 1 else {
                fputs("Expected one active session immediately after push-to-talk press, got \(immediateActiveAfterPress)\n", stderr)
                return 12
            }

            guard immediateDuckedVolume == 0.35 else {
                fputs("Expected immediate ducked volume 0.35, got \(String(describing: immediateDuckedVolume))\n", stderr)
                return 13
            }

            guard activeWhileRecording == 1 else {
                fputs("Expected one active session while recording, got \(activeWhileRecording)\n", stderr)
                return 4
            }

            guard duckedVolume == 0.35 else {
                fputs("Expected ducked volume 0.35, got \(String(describing: duckedVolume))\n", stderr)
                return 5
            }

            guard voiceStatusDuringRecording == .recording else {
                fputs("Expected recording voice state, got \(voiceStatusDuringRecording)\n", stderr)
                return 6
            }

            guard !sttLoadedWhileRecording else {
                fputs("Expected STT engine to remain unloaded while recording\n", stderr)
                return 14
            }

            guard activeAfterStop == 0 else {
                fputs("Expected zero active sessions after stop, got \(activeAfterStop)\n", stderr)
                return 7
            }

            guard restoredVolume == 1 else {
                fputs("Expected restored volume 1.0, got \(String(describing: restoredVolume))\n", stderr)
                return 8
            }

            guard insertedText == transcript, lastTranscript == transcript else {
                fputs("Expected transcript insertion '\(transcript)', got inserted=\(String(describing: insertedText)) last=\(String(describing: lastTranscript))\n", stderr)
                return 9
            }

            guard !sttLoadedAfterStop else {
                fputs("Expected STT engine to be unloaded after stop\n", stderr)
                return 10
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after cleanup, got \(tapCount)\n", stderr)
                return 11
            }

            emitHarnessLine("voiceHarness immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) activeWhileRecording=\(activeWhileRecording) duckedVolume=\(duckedVolume ?? -1) sttLoadedWhileRecording=\(sttLoadedWhileRecording) activeAfterStop=\(activeAfterStop) restoredVolume=\(restoredVolume ?? -1) insertedText=\(insertedText ?? "nil") sttLoadedAfterStop=\(sttLoadedAfterStop) tapCount=\(tapCount)")
            return 0
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runVoiceShutdownHarness() -> Int32 {
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let pid = player.processIdentifier
            let audioState = CoreAudioProcessInspector().snapshot(for: pid)
            guard let audioObjectID = audioState.processObjectID else {
                fputs("Could not resolve Core Audio process object for pid \(pid)\n", stderr)
                player.terminate()
                return 3
            }

            let app = ManagedAudioApp(
                id: "com.apple.afplay",
                displayName: "afplay",
                bundleIdentifier: "com.apple.afplay",
                processIdentifier: pid,
                audioObjectID: audioObjectID,
                volume: 1,
                isMuted: false,
                isProducingAudio: true,
                isDucked: false
            )

            let recorder = TrackingHarnessMicrophoneRecorder()
            let sttEngine = HarnessSTTEngine(transcript: "MiniMix shutdown harness")
            let textInjector = HarnessTextInjector()
            let model = MiniMixModel(
                mixerController: MixerController(
                    appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                    ruleStore: HarnessAudioRuleStore(),
                    audioEngine: CoreAudioPerAppAudioEngine()
                ),
                voiceController: VoiceInputController(
                    recorder: recorder,
                    sttEngine: sttEngine,
                    textInjector: textInjector
                ),
                hotkeyController: HarnessHotkeyController()
            )

            model.startDictation()
            let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
            let immediateDuckedVolume = model.mixer.apps.first?.volume

            spinRunLoop(for: 0.4)

            let activeWhileRecording = model.mixer.activeAudioSessionCount
            let duckedVolume = model.mixer.apps.first?.volume
            let sttLoadedWhileRecording = sttEngine.isLoaded
            let voiceStatusWhileRecording = model.voice.status

            var recorderStatus = (didStart: false, didStop: false, path: "")
            try awaitBlocking {
                await model.shutdownNow()
                recorderStatus = await recorder.status()
            }

            let activeAfterShutdown = model.mixer.activeAudioSessionCount
            let restoredVolume = model.mixer.apps.first?.volume
            let voiceStatusAfterShutdown = model.voice.status
            let sttLoadedAfterShutdown = sttEngine.isLoaded
            let insertedText = textInjector.insertedText
            let recordingFileExists = FileManager.default.fileExists(atPath: recorderStatus.path)

            player.waitUntilExit()

            guard immediateActiveAfterPress == 1, immediateDuckedVolume == 0.35 else {
                fputs("Expected immediate duck on shutdown harness, active=\(immediateActiveAfterPress) volume=\(String(describing: immediateDuckedVolume))\n", stderr)
                return 4
            }

            guard activeWhileRecording == 1, duckedVolume == 0.35, voiceStatusWhileRecording == .recording else {
                fputs("Expected recording state before shutdown, active=\(activeWhileRecording) volume=\(String(describing: duckedVolume)) voice=\(voiceStatusWhileRecording)\n", stderr)
                return 5
            }

            guard !sttLoadedWhileRecording else {
                fputs("Expected STT unloaded while recording before shutdown\n", stderr)
                return 6
            }

            guard recorderStatus.didStart, recorderStatus.didStop else {
                fputs("Expected recorder start/stop during shutdown, status=\(recorderStatus)\n", stderr)
                return 7
            }

            guard activeAfterShutdown == 0, restoredVolume == 1.0, voiceStatusAfterShutdown == .idle else {
                fputs("Expected shutdown to restore and idle, active=\(activeAfterShutdown) volume=\(String(describing: restoredVolume)) voice=\(voiceStatusAfterShutdown)\n", stderr)
                return 8
            }

            guard !sttLoadedAfterShutdown, insertedText == nil else {
                fputs("Expected shutdown cancel to avoid STT/paste, sttLoaded=\(sttLoadedAfterShutdown) inserted=\(String(describing: insertedText))\n", stderr)
                return 9
            }

            guard !recordingFileExists else {
                fputs("Expected shutdown cancel to remove recording file \(recorderStatus.path)\n", stderr)
                return 10
            }

            print("voiceShutdownHarness immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) activeWhileRecording=\(activeWhileRecording) duckedVolume=\(duckedVolume ?? -1) activeAfterShutdown=\(activeAfterShutdown) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatusAfterShutdown) recorderStarted=\(recorderStatus.didStart) recorderStopped=\(recorderStatus.didStop) sttLoadedAfterShutdown=\(sttLoadedAfterShutdown) insertedText=\(insertedText ?? "nil") recordingFileExists=\(recordingFileExists)")
            return 0
        } catch {
            player.terminate()
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runVoiceRealRecorderHarness() -> Int32 {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            print("voiceRealRecorderHarness ready=false status=\(microphoneAuthorizationStatusText(status))")
            return 66
        }

        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"
        let transcript = argument(after: "--transcript") ?? "MiniMix real recorder harness"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            var app = try managedApp(
                process: player,
                displayName: "afplay real recorder",
                bundleIdentifier: "dev.minimix.harness.real-recorder",
                volume: 1
            )
            app.isProducingAudio = true

            let textInjector = HarnessTextInjector()
            let sttEngine = HarnessSTTEngine(transcript: transcript)
            let model = MiniMixModel(
                mixerController: MixerController(
                    appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                    ruleStore: HarnessAudioRuleStore(),
                    audioEngine: CoreAudioPerAppAudioEngine()
                ),
                voiceController: VoiceInputController(
                    recorder: MicrophoneRecorder(),
                    sttEngine: sttEngine,
                    textInjector: textInjector
                ),
                hotkeyController: HarnessHotkeyController()
            )

            model.startDictation()
            let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
            let immediateDuckedVolume = model.mixer.apps.first?.volume

            _ = waitFor(timeout: 5) {
                model.voice.status == .recording || model.voice.errorMessage != nil
            }

            let activeWhileRecording = model.mixer.activeAudioSessionCount
            let duckedVolume = model.mixer.apps.first?.volume
            let voiceStatusDuringRecording = model.voice.status
            let sttLoadedWhileRecording = sttEngine.isLoaded
            let startErrorMessage = model.voice.errorMessage

            model.stopDictation()
            _ = waitFor(timeout: 5) {
                model.voice.status == .idle && (textInjector.insertedText != nil || model.voice.errorMessage != nil)
            }

            let activeAfterStop = model.mixer.activeAudioSessionCount
            let restoredVolume = model.mixer.apps.first?.volume
            let insertedText = textInjector.insertedText
            let lastTranscript = model.voice.lastTranscript
            let sttLoadedAfterStop = sttEngine.isLoaded
            let transcribedFilePath = sttEngine.transcribedFilePath
            let transcribedFileBytes = sttEngine.transcribedFileBytes ?? 0
            let recordingFileRemoved = transcribedFilePath.map { !FileManager.default.fileExists(atPath: $0) } ?? false

            model.shutdown()
            player.waitUntilExit()

            guard immediateActiveAfterPress == 1 else {
                fputs("Expected one active session immediately after real-recorder press, got \(immediateActiveAfterPress)\n", stderr)
                return 3
            }

            guard immediateDuckedVolume == 0.35 else {
                fputs("Expected immediate ducked volume 0.35, got \(String(describing: immediateDuckedVolume))\n", stderr)
                return 4
            }

            guard activeWhileRecording == 1, duckedVolume == 0.35, voiceStatusDuringRecording == .recording else {
                fputs("Expected active recording with ducking, active=\(activeWhileRecording) ducked=\(String(describing: duckedVolume)) status=\(voiceStatusDuringRecording) error=\(startErrorMessage ?? "nil")\n", stderr)
                return 5
            }

            guard !sttLoadedWhileRecording else {
                fputs("Expected STT to remain unloaded while real microphone is recording\n", stderr)
                return 6
            }

            guard transcribedFileBytes > 0, transcribedFilePath != nil else {
                fputs("Expected real recorder to produce a non-empty CAF before fake STT, path=\(String(describing: transcribedFilePath)) bytes=\(transcribedFileBytes)\n", stderr)
                return 7
            }

            guard activeAfterStop == 0, restoredVolume == 1 else {
                fputs("Expected audio restored after real-recorder stop, active=\(activeAfterStop) volume=\(String(describing: restoredVolume))\n", stderr)
                return 8
            }

            guard insertedText == transcript, lastTranscript == transcript else {
                fputs("Expected fake STT transcript insertion after real recording, inserted=\(String(describing: insertedText)) last=\(String(describing: lastTranscript))\n", stderr)
                return 9
            }

            guard !sttLoadedAfterStop else {
                fputs("Expected STT unloaded after real-recorder stop\n", stderr)
                return 10
            }

            guard recordingFileRemoved else {
                fputs("Expected VoiceInputController to remove real recording file, path=\(String(describing: transcribedFilePath))\n", stderr)
                return 11
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after real-recorder cleanup, got \(tapCount)\n", stderr)
                return 12
            }

            print("voiceRealRecorderHarness ready=true immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) activeWhileRecording=\(activeWhileRecording) duckedVolume=\(duckedVolume ?? -1) status=\(voiceStatusDuringRecording) sttLoadedWhileRecording=\(sttLoadedWhileRecording) activeAfterStop=\(activeAfterStop) restoredVolume=\(restoredVolume ?? -1) insertedText=\(insertedText ?? "nil") sttLoadedAfterStop=\(sttLoadedAfterStop) recordingBytes=\(transcribedFileBytes) recordingFileRemoved=\(recordingFileRemoved) tapCount=\(tapCount)")
            return 0
        } catch {
            if player.isRunning {
                player.terminate()
            }
            fputs("voiceRealRecorderHarness ready=false error=\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runVoiceShutdownDuringStartHarness() -> Int32 {
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let pid = player.processIdentifier
            let audioState = CoreAudioProcessInspector().snapshot(for: pid)
            guard let audioObjectID = audioState.processObjectID else {
                fputs("Could not resolve Core Audio process object for pid \(pid)\n", stderr)
                player.terminate()
                return 3
            }

            let app = ManagedAudioApp(
                id: "com.apple.afplay",
                displayName: "afplay",
                bundleIdentifier: "com.apple.afplay",
                processIdentifier: pid,
                audioObjectID: audioObjectID,
                volume: 1,
                isMuted: false,
                isProducingAudio: true,
                isDucked: false
            )

            let recorder = DelayedHarnessMicrophoneRecorder(delayNanoseconds: 250_000_000)
            let sttEngine = HarnessSTTEngine(transcript: "MiniMix shutdown during start harness")
            let textInjector = HarnessTextInjector()
            let model = MiniMixModel(
                mixerController: MixerController(
                    appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                    ruleStore: HarnessAudioRuleStore(),
                    audioEngine: CoreAudioPerAppAudioEngine()
                ),
                voiceController: VoiceInputController(
                    recorder: recorder,
                    sttEngine: sttEngine,
                    textInjector: textInjector
                ),
                hotkeyController: HarnessHotkeyController()
            )

            model.startDictation()
            let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
            let immediateDuckedVolume = model.mixer.apps.first?.volume
            let immediateVoiceStatus = model.voice.status

            var recorderStatus = (didStart: false, didStop: false, path: "")
            try awaitBlocking {
                await model.shutdownNow()
                recorderStatus = await recorder.status()
            }

            let activeAfterShutdown = model.mixer.activeAudioSessionCount
            let restoredVolume = model.mixer.apps.first?.volume
            let voiceStatusAfterShutdown = model.voice.status
            let sttLoadedAfterShutdown = sttEngine.isLoaded
            let insertedText = textInjector.insertedText
            let recordingFileExists = FileManager.default.fileExists(atPath: recorderStatus.path)

            player.waitUntilExit()

            guard immediateActiveAfterPress == 1, immediateDuckedVolume == 0.35, immediateVoiceStatus == .idle else {
                fputs("Expected immediate duck while recorder startup is pending, active=\(immediateActiveAfterPress) volume=\(String(describing: immediateDuckedVolume)) voice=\(immediateVoiceStatus)\n", stderr)
                return 4
            }

            guard recorderStatus.didStart, recorderStatus.didStop else {
                fputs("Expected delayed recorder start/stop during shutdown, status=\(recorderStatus)\n", stderr)
                return 5
            }

            guard activeAfterShutdown == 0, restoredVolume == 1.0, voiceStatusAfterShutdown == .idle else {
                fputs("Expected shutdown during startup to restore and idle, active=\(activeAfterShutdown) volume=\(String(describing: restoredVolume)) voice=\(voiceStatusAfterShutdown)\n", stderr)
                return 6
            }

            guard !sttLoadedAfterShutdown, insertedText == nil else {
                fputs("Expected shutdown during startup to avoid STT/paste, sttLoaded=\(sttLoadedAfterShutdown) inserted=\(String(describing: insertedText))\n", stderr)
                return 7
            }

            guard !recordingFileExists else {
                fputs("Expected shutdown during startup to remove recording file \(recorderStatus.path)\n", stderr)
                return 8
            }

            print("voiceShutdownDuringStartHarness immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) immediateStatus=\(immediateVoiceStatus) activeAfterShutdown=\(activeAfterShutdown) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatusAfterShutdown) recorderStarted=\(recorderStatus.didStart) recorderStopped=\(recorderStatus.didStop) sttLoadedAfterShutdown=\(sttLoadedAfterShutdown) insertedText=\(insertedText ?? "nil") recordingFileExists=\(recordingFileExists)")
            return 0
        } catch {
            player.terminate()
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func runVoiceEarlyReleaseHarness() -> Int32 {
        let transcript = argument(after: "--transcript") ?? "MiniMix early release harness"
        let app = ManagedAudioApp(
            id: "com.example.silent",
            displayName: "Silent Harness",
            bundleIdentifier: "com.example.silent",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let textInjector = HarnessTextInjector()
        let sttEngine = HarnessSTTEngine(transcript: transcript)
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: DelayedHarnessMicrophoneRecorder(delayNanoseconds: 250_000_000),
                sttEngine: sttEngine,
                textInjector: textInjector
            ),
            hotkeyController: HarnessHotkeyController()
        )

        model.startDictation()
        let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
        let immediateDuckedVolume = model.mixer.apps.first?.volume

        model.stopDictation()
        let activeAfterEarlyRelease = model.mixer.activeAudioSessionCount
        let volumeAfterEarlyRelease = model.mixer.apps.first?.volume

        spinRunLoop(for: 0.8)

        let activeAfterSettled = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatus = model.voice.status
        let insertedText = textInjector.insertedText
        let sttLoadedAfterStop = sttEngine.isLoaded
        model.shutdown()

        guard immediateActiveAfterPress == 1 else {
            fputs("Expected one active session immediately after push-to-talk press, got \(immediateActiveAfterPress)\n", stderr)
            return 2
        }

        guard immediateDuckedVolume == 0.35 else {
            fputs("Expected immediate ducked volume 0.35, got \(String(describing: immediateDuckedVolume))\n", stderr)
            return 3
        }

        guard activeAfterEarlyRelease == 0 else {
            fputs("Expected zero active sessions immediately after early release, got \(activeAfterEarlyRelease)\n", stderr)
            return 4
        }

        guard volumeAfterEarlyRelease == 1 else {
            fputs("Expected volume restored immediately after early release, got \(String(describing: volumeAfterEarlyRelease))\n", stderr)
            return 5
        }

        guard activeAfterSettled == 0 else {
            fputs("Expected zero active sessions after delayed startup settled, got \(activeAfterSettled)\n", stderr)
            return 6
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after delayed startup settled, got \(String(describing: restoredVolume))\n", stderr)
            return 7
        }

        guard voiceStatus == .idle else {
            fputs("Expected idle voice state after early release settled, got \(voiceStatus)\n", stderr)
            return 8
        }

        guard insertedText == transcript else {
            fputs("Expected transcript insertion '\(transcript)', got \(String(describing: insertedText))\n", stderr)
            return 9
        }

        guard !sttLoadedAfterStop else {
            fputs("Expected STT engine to be unloaded after early release stop\n", stderr)
            return 10
        }

        emitHarnessLine("voiceEarlyReleaseHarness immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) activeAfterEarlyRelease=\(activeAfterEarlyRelease) volumeAfterEarlyRelease=\(volumeAfterEarlyRelease ?? -1) activeAfterSettled=\(activeAfterSettled) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatus) insertedText=\(insertedText ?? "nil") sttLoadedAfterStop=\(sttLoadedAfterStop)")
        return 0
    }

    @MainActor
    private static func runVoiceHotkeyEarlyReleaseHarness() -> Int32 {
        let transcript = argument(after: "--transcript") ?? "MiniMix hotkey early release harness"
        let app = ManagedAudioApp(
            id: "com.example.hotkey-early-release",
            displayName: "Hotkey Early Release Harness",
            bundleIdentifier: "com.example.hotkey-early-release",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let textInjector = HarnessTextInjector()
        let sttEngine = HarnessSTTEngine(transcript: transcript)
        let hotkeyController = HarnessHotkeyController()
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: DelayedHarnessMicrophoneRecorder(delayNanoseconds: 250_000_000),
                sttEngine: sttEngine,
                textInjector: textInjector
            ),
            hotkeyController: hotkeyController
        )

        hotkeyController.simulatePress()
        let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
        let immediateDuckedVolume = model.mixer.apps.first?.volume

        hotkeyController.simulateRelease()
        let activeAfterEarlyRelease = model.mixer.activeAudioSessionCount
        let volumeAfterEarlyRelease = model.mixer.apps.first?.volume

        spinRunLoop(for: 0.8)

        let activeAfterSettled = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatus = model.voice.status
        let insertedText = textInjector.insertedText
        let sttLoadedAfterStop = sttEngine.isLoaded
        model.shutdown()

        guard immediateActiveAfterPress == 1 else {
            fputs("Expected one active session immediately after hotkey press, got \(immediateActiveAfterPress)\n", stderr)
            return 2
        }

        guard immediateDuckedVolume == 0.35 else {
            fputs("Expected immediate hotkey ducked volume 0.35, got \(String(describing: immediateDuckedVolume))\n", stderr)
            return 3
        }

        guard activeAfterEarlyRelease == 0 else {
            fputs("Expected zero active sessions immediately after hotkey early release, got \(activeAfterEarlyRelease)\n", stderr)
            return 4
        }

        guard volumeAfterEarlyRelease == 1 else {
            fputs("Expected volume restored immediately after hotkey early release, got \(String(describing: volumeAfterEarlyRelease))\n", stderr)
            return 5
        }

        guard activeAfterSettled == 0 else {
            fputs("Expected zero active sessions after delayed hotkey startup settled, got \(activeAfterSettled)\n", stderr)
            return 6
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after delayed hotkey startup settled, got \(String(describing: restoredVolume))\n", stderr)
            return 7
        }

        guard voiceStatus == .idle else {
            fputs("Expected idle voice state after hotkey early release settled, got \(voiceStatus)\n", stderr)
            return 8
        }

        guard insertedText == transcript else {
            fputs("Expected hotkey transcript insertion '\(transcript)', got \(String(describing: insertedText))\n", stderr)
            return 9
        }

        guard !sttLoadedAfterStop else {
            fputs("Expected STT engine to be unloaded after hotkey early release stop\n", stderr)
            return 10
        }

        emitHarnessLine("voiceHotkeyEarlyReleaseHarness immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) activeAfterEarlyRelease=\(activeAfterEarlyRelease) volumeAfterEarlyRelease=\(volumeAfterEarlyRelease ?? -1) activeAfterSettled=\(activeAfterSettled) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatus) insertedText=\(insertedText ?? "nil") sttLoadedAfterStop=\(sttLoadedAfterStop)")
        return 0
    }

    @MainActor
    private static func runVoiceSTTFailureHarness() -> Int32 {
        let app = ManagedAudioApp(
            id: "com.example.stt-failure",
            displayName: "STT Failure Harness",
            bundleIdentifier: "com.example.stt-failure",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let textInjector = HarnessTextInjector()
        let sttEngine = FailingHarnessSTTEngine()
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: HarnessMicrophoneRecorder(),
                sttEngine: sttEngine,
                textInjector: textInjector
            ),
            hotkeyController: HarnessHotkeyController()
        )

        model.startDictation()
        spinRunLoop(for: 0.2)

        let activeWhileRecording = model.mixer.activeAudioSessionCount
        let duckedVolume = model.mixer.apps.first?.volume
        let voiceStatusDuringRecording = model.voice.status
        let sttLoadedWhileRecording = sttEngine.isLoaded

        model.stopDictation()
        spinRunLoop(for: 0.4)

        let activeAfterStop = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatusAfterStop = model.voice.status
        let errorMessage = model.voice.errorMessage
        let insertedText = textInjector.insertedText
        let sttLoadedAfterStop = sttEngine.isLoaded
        model.shutdown()

        guard activeWhileRecording == 1 else {
            fputs("Expected one active session while recording, got \(activeWhileRecording)\n", stderr)
            return 2
        }

        guard duckedVolume == 0.35 else {
            fputs("Expected ducked volume 0.35, got \(String(describing: duckedVolume))\n", stderr)
            return 3
        }

        guard voiceStatusDuringRecording == .recording else {
            fputs("Expected recording voice state, got \(voiceStatusDuringRecording)\n", stderr)
            return 4
        }

        guard !sttLoadedWhileRecording else {
            fputs("Expected STT engine to remain unloaded while recording\n", stderr)
            return 5
        }

        guard activeAfterStop == 0 else {
            fputs("Expected zero active sessions after STT failure, got \(activeAfterStop)\n", stderr)
            return 6
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after STT failure, got \(String(describing: restoredVolume))\n", stderr)
            return 7
        }

        guard voiceStatusAfterStop == .idle else {
            fputs("Expected idle voice state after STT failure, got \(voiceStatusAfterStop)\n", stderr)
            return 8
        }

        guard errorMessage == HarnessError.sttLoadFailed.errorDescription else {
            fputs("Expected STT failure error message, got \(String(describing: errorMessage))\n", stderr)
            return 9
        }

        guard insertedText == nil else {
            fputs("Expected no text insertion after STT failure, got \(String(describing: insertedText))\n", stderr)
            return 10
        }

        guard !sttLoadedAfterStop else {
            fputs("Expected STT engine to be unloaded after STT failure\n", stderr)
            return 11
        }

        print("voiceSTTFailureHarness activeWhileRecording=\(activeWhileRecording) duckedVolume=\(duckedVolume ?? -1) sttLoadedWhileRecording=\(sttLoadedWhileRecording) activeAfterStop=\(activeAfterStop) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatusAfterStop) insertedText=\(insertedText ?? "nil") sttLoadedAfterStop=\(sttLoadedAfterStop) error=\(errorMessage ?? "nil")")
        return 0
    }

    @MainActor
    private static func runVoiceRecorderFailureHarness() -> Int32 {
        let app = ManagedAudioApp(
            id: "com.example.recorder-failure",
            displayName: "Recorder Failure Harness",
            bundleIdentifier: "com.example.recorder-failure",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let textInjector = HarnessTextInjector()
        let sttEngine = HarnessSTTEngine(transcript: "should not transcribe")
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: FailingHarnessMicrophoneRecorder(),
                sttEngine: sttEngine,
                textInjector: textInjector
            ),
            hotkeyController: HarnessHotkeyController()
        )

        model.startDictation()
        let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
        let immediateDuckedVolume = model.mixer.apps.first?.volume

        spinRunLoop(for: 0.4)

        let activeAfterFailure = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatus = model.voice.status
        let errorMessage = model.voice.errorMessage
        let insertedText = textInjector.insertedText
        let sttLoadedAfterFailure = sttEngine.isLoaded
        model.shutdown()

        guard immediateActiveAfterPress == 1 else {
            fputs("Expected one active session immediately after push-to-talk press, got \(immediateActiveAfterPress)\n", stderr)
            return 2
        }

        guard immediateDuckedVolume == 0.35 else {
            fputs("Expected immediate ducked volume 0.35, got \(String(describing: immediateDuckedVolume))\n", stderr)
            return 3
        }

        guard activeAfterFailure == 0 else {
            fputs("Expected zero active sessions after recorder failure, got \(activeAfterFailure)\n", stderr)
            return 4
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after recorder failure, got \(String(describing: restoredVolume))\n", stderr)
            return 5
        }

        guard voiceStatus == .idle else {
            fputs("Expected idle voice state after recorder failure, got \(voiceStatus)\n", stderr)
            return 6
        }

        guard errorMessage == HarnessError.recorderStartFailed.errorDescription else {
            fputs("Expected recorder failure error message, got \(String(describing: errorMessage))\n", stderr)
            return 7
        }

        guard insertedText == nil else {
            fputs("Expected no text insertion after recorder failure, got \(String(describing: insertedText))\n", stderr)
            return 8
        }

        guard !sttLoadedAfterFailure else {
            fputs("Expected STT engine to remain unloaded after recorder failure\n", stderr)
            return 9
        }

        print("voiceRecorderFailureHarness immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) activeAfterFailure=\(activeAfterFailure) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatus) insertedText=\(insertedText ?? "nil") sttLoadedAfterFailure=\(sttLoadedAfterFailure) error=\(errorMessage ?? "nil")")
        return 0
    }

    @MainActor
    private static func runVoiceMicDeniedHarness() -> Int32 {
        let app = ManagedAudioApp(
            id: "com.example.mic-denied",
            displayName: "Mic Denied Harness",
            bundleIdentifier: "com.example.mic-denied",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let textInjector = HarnessTextInjector()
        let sttEngine = HarnessSTTEngine(transcript: "should not transcribe")
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: MicrophoneRecorder(),
                sttEngine: sttEngine,
                textInjector: textInjector
            ),
            hotkeyController: HarnessHotkeyController()
        )

        model.startDictation()
        let immediateActiveAfterPress = model.mixer.activeAudioSessionCount
        let immediateDuckedVolume = model.mixer.apps.first?.volume

        spinRunLoop(for: 0.4)

        let activeAfterFailure = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatus = model.voice.status
        let errorMessage = model.voice.errorMessage
        let insertedText = textInjector.insertedText
        let sttLoadedAfterFailure = sttEngine.isLoaded
        let tapCount = currentTapCount()
        model.shutdown()

        guard immediateActiveAfterPress == 1 else {
            fputs("Expected one active session immediately after mic-denied start, got \(immediateActiveAfterPress)\n", stderr)
            return 2
        }

        guard immediateDuckedVolume == 0.35 else {
            fputs("Expected immediate ducked volume 0.35 for mic-denied start, got \(String(describing: immediateDuckedVolume))\n", stderr)
            return 3
        }

        guard activeAfterFailure == 0 else {
            fputs("Expected zero active sessions after mic-denied failure, got \(activeAfterFailure)\n", stderr)
            return 4
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after mic-denied failure, got \(String(describing: restoredVolume))\n", stderr)
            return 5
        }

        guard voiceStatus == .idle else {
            fputs("Expected idle voice state after mic-denied failure, got \(voiceStatus)\n", stderr)
            return 6
        }

        guard errorMessage == MicrophoneRecorderError.microphoneDenied.errorDescription else {
            fputs("Expected microphone permission error message, got \(String(describing: errorMessage))\n", stderr)
            return 7
        }

        guard insertedText == nil else {
            fputs("Expected no text insertion after mic-denied failure, got \(String(describing: insertedText))\n", stderr)
            return 8
        }

        guard !sttLoadedAfterFailure else {
            fputs("Expected STT engine to remain unloaded after mic-denied failure\n", stderr)
            return 9
        }

        guard tapCount == 0 else {
            fputs("Expected no Core Audio taps after mic-denied failure, got \(tapCount)\n", stderr)
            return 10
        }

        emitHarnessLine("voiceMicDeniedHarness immediateActiveAfterPress=\(immediateActiveAfterPress) immediateDuckedVolume=\(immediateDuckedVolume ?? -1) activeAfterFailure=\(activeAfterFailure) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatus) insertedText=\(insertedText ?? "nil") sttLoadedAfterFailure=\(sttLoadedAfterFailure) error=\(errorMessage ?? "nil") tapCount=\(tapCount)")
        return 0
    }

    @MainActor
    private static func runVoiceSpeechDeniedHarness() -> Int32 {
        guard AppleSpeechSTTEngine.authorizationStatus != .authorized else {
            emitHarnessLine("voiceSpeechDeniedHarness ready=false reason=speechAuthorized")
            return 66
        }

        let app = ManagedAudioApp(
            id: "com.example.speech-denied",
            displayName: "Speech Denied Harness",
            bundleIdentifier: "com.example.speech-denied",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let textInjector = HarnessTextInjector()
        let recorder = TrackingHarnessMicrophoneRecorder()
        let sttEngine = AppleSpeechSTTEngine()
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: recorder,
                sttEngine: sttEngine,
                textInjector: textInjector
            ),
            hotkeyController: HarnessHotkeyController()
        )

        model.startDictation()
        spinRunLoop(for: 0.2)

        let activeWhileRecording = model.mixer.activeAudioSessionCount
        let duckedVolume = model.mixer.apps.first?.volume
        let voiceStatusDuringRecording = model.voice.status
        let sttLoadedWhileRecording = sttEngine.isLoaded

        model.stopDictation()
        spinRunLoop(for: 0.4)

        let activeAfterStop = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatusAfterStop = model.voice.status
        let errorMessage = model.voice.errorMessage
        let insertedText = textInjector.insertedText
        let sttLoadedAfterStop = sttEngine.isLoaded
        var recorderStatus = (didStart: false, didStop: false, path: "")
        try? awaitBlocking {
            recorderStatus = await recorder.status()
        }
        let recordingFileExists = FileManager.default.fileExists(atPath: recorderStatus.path)
        let tapCount = currentTapCount()
        model.shutdown()
        try? FileManager.default.removeItem(atPath: recorderStatus.path)

        guard activeWhileRecording == 1 else {
            fputs("Expected one active session while recording before Speech denial, got \(activeWhileRecording)\n", stderr)
            return 2
        }

        guard duckedVolume == 0.35 else {
            fputs("Expected ducked volume 0.35 before Speech denial, got \(String(describing: duckedVolume))\n", stderr)
            return 3
        }

        guard voiceStatusDuringRecording == .recording else {
            fputs("Expected recording state before Speech denial, got \(voiceStatusDuringRecording)\n", stderr)
            return 4
        }

        guard !sttLoadedWhileRecording else {
            fputs("Expected Apple Speech STT to remain unloaded while recording\n", stderr)
            return 5
        }

        guard activeAfterStop == 0 else {
            fputs("Expected zero active sessions after Speech denial, got \(activeAfterStop)\n", stderr)
            return 6
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after Speech denial, got \(String(describing: restoredVolume))\n", stderr)
            return 7
        }

        guard voiceStatusAfterStop == .idle else {
            fputs("Expected idle voice state after Speech denial, got \(voiceStatusAfterStop)\n", stderr)
            return 8
        }

        guard errorMessage == AppleSpeechError.recognitionDenied.errorDescription else {
            fputs("Expected Speech permission error, got \(String(describing: errorMessage))\n", stderr)
            return 9
        }

        guard insertedText == nil else {
            fputs("Expected no text insertion after Speech denial, got \(String(describing: insertedText))\n", stderr)
            return 10
        }

        guard !sttLoadedAfterStop else {
            fputs("Expected Apple Speech STT to remain unloaded after Speech denial\n", stderr)
            return 11
        }

        guard recorderStatus.didStart, recorderStatus.didStop else {
            fputs("Expected recorder start/stop before Speech denial, got start=\(recorderStatus.didStart) stop=\(recorderStatus.didStop)\n", stderr)
            return 12
        }

        guard !recordingFileExists else {
            fputs("Expected recording file removed after Speech denial, path=\(recorderStatus.path)\n", stderr)
            return 13
        }

        guard tapCount == 0 else {
            fputs("Expected no Core Audio taps after Speech denial, got \(tapCount)\n", stderr)
            return 14
        }

        emitHarnessLine("voiceSpeechDeniedHarness activeWhileRecording=\(activeWhileRecording) duckedVolume=\(duckedVolume ?? -1) sttLoadedWhileRecording=\(sttLoadedWhileRecording) activeAfterStop=\(activeAfterStop) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatusAfterStop) insertedText=\(insertedText ?? "nil") sttLoadedAfterStop=\(sttLoadedAfterStop) recorderStarted=\(recorderStatus.didStart) recorderStopped=\(recorderStatus.didStop) recordingFileExists=\(recordingFileExists) error=\(errorMessage ?? "nil") tapCount=\(tapCount)")
        return 0
    }

    @MainActor
    private static func runVoiceAccessibilityDeniedHarness() -> Int32 {
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options) else {
            emitHarnessLine("voiceAccessibilityDeniedHarness ready=false reason=accessibilityTrusted")
            return 66
        }

        let app = ManagedAudioApp(
            id: "com.example.accessibility-denied",
            displayName: "Accessibility Denied Harness",
            bundleIdentifier: "com.example.accessibility-denied",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let recorder = TrackingHarnessMicrophoneRecorder()
        let sttEngine = HarnessSTTEngine(transcript: "MiniMix accessibility denied harness")
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: recorder,
                sttEngine: sttEngine,
                textInjector: PasteboardTextInjector()
            ),
            hotkeyController: HarnessHotkeyController()
        )

        model.startDictation()
        spinRunLoop(for: 0.2)

        let activeWhileRecording = model.mixer.activeAudioSessionCount
        let duckedVolume = model.mixer.apps.first?.volume
        let voiceStatusDuringRecording = model.voice.status
        let sttLoadedWhileRecording = sttEngine.isLoaded

        model.stopDictation()
        spinRunLoop(for: 0.4)

        let activeAfterStop = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatusAfterStop = model.voice.status
        let errorMessage = model.voice.errorMessage
        let sttLoadedAfterStop = sttEngine.isLoaded
        var recorderStatus = (didStart: false, didStop: false, path: "")
        try? awaitBlocking {
            recorderStatus = await recorder.status()
        }
        let recordingFileExists = FileManager.default.fileExists(atPath: recorderStatus.path)
        let tapCount = currentTapCount()
        model.shutdown()
        try? FileManager.default.removeItem(atPath: recorderStatus.path)

        guard activeWhileRecording == 1 else {
            fputs("Expected one active session while recording before Accessibility denial, got \(activeWhileRecording)\n", stderr)
            return 2
        }

        guard duckedVolume == 0.35 else {
            fputs("Expected ducked volume 0.35 before Accessibility denial, got \(String(describing: duckedVolume))\n", stderr)
            return 3
        }

        guard voiceStatusDuringRecording == .recording else {
            fputs("Expected recording state before Accessibility denial, got \(voiceStatusDuringRecording)\n", stderr)
            return 4
        }

        guard !sttLoadedWhileRecording else {
            fputs("Expected harness STT to remain unloaded while recording\n", stderr)
            return 5
        }

        guard activeAfterStop == 0 else {
            fputs("Expected zero active sessions after Accessibility denial, got \(activeAfterStop)\n", stderr)
            return 6
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after Accessibility denial, got \(String(describing: restoredVolume))\n", stderr)
            return 7
        }

        guard voiceStatusAfterStop == .idle else {
            fputs("Expected idle voice state after Accessibility denial, got \(voiceStatusAfterStop)\n", stderr)
            return 8
        }

        guard errorMessage == TextInjectionError.accessibilityNotTrusted.errorDescription else {
            fputs("Expected Accessibility permission error, got \(String(describing: errorMessage))\n", stderr)
            return 9
        }

        guard !sttLoadedAfterStop else {
            fputs("Expected harness STT to unload after Accessibility denial\n", stderr)
            return 10
        }

        guard recorderStatus.didStart, recorderStatus.didStop else {
            fputs("Expected recorder start/stop before Accessibility denial, got start=\(recorderStatus.didStart) stop=\(recorderStatus.didStop)\n", stderr)
            return 11
        }

        guard !recordingFileExists else {
            fputs("Expected recording file removed after Accessibility denial, path=\(recorderStatus.path)\n", stderr)
            return 12
        }

        guard tapCount == 0 else {
            fputs("Expected no Core Audio taps after Accessibility denial, got \(tapCount)\n", stderr)
            return 13
        }

        emitHarnessLine("voiceAccessibilityDeniedHarness activeWhileRecording=\(activeWhileRecording) duckedVolume=\(duckedVolume ?? -1) sttLoadedWhileRecording=\(sttLoadedWhileRecording) activeAfterStop=\(activeAfterStop) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatusAfterStop) pasteDenied=true insertedText=nil sttLoadedAfterStop=\(sttLoadedAfterStop) recorderStarted=\(recorderStatus.didStart) recorderStopped=\(recorderStatus.didStop) recordingFileExists=\(recordingFileExists) error=\(errorMessage ?? "nil") tapCount=\(tapCount)")
        return 0
    }

    @MainActor
    private static func runVoicePasteFailureHarness() -> Int32 {
        let app = ManagedAudioApp(
            id: "com.example.paste-failure",
            displayName: "Paste Failure Harness",
            bundleIdentifier: "com.example.paste-failure",
            processIdentifier: getpid(),
            audioObjectID: 1,
            volume: 1,
            isMuted: false,
            isProducingAudio: true,
            isDucked: false
        )

        let textInjector = FailingHarnessTextInjector()
        let sttEngine = HarnessSTTEngine(transcript: "MiniMix paste failure harness")
        let model = MiniMixModel(
            mixerController: MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: HarnessAudioRuleStore(),
                audioEngine: HarnessTrackingAudioEngine()
            ),
            voiceController: VoiceInputController(
                recorder: HarnessMicrophoneRecorder(),
                sttEngine: sttEngine,
                textInjector: textInjector
            ),
            hotkeyController: HarnessHotkeyController()
        )

        model.startDictation()
        spinRunLoop(for: 0.2)

        let activeWhileRecording = model.mixer.activeAudioSessionCount
        let duckedVolume = model.mixer.apps.first?.volume
        let sttLoadedWhileRecording = sttEngine.isLoaded

        model.stopDictation()
        spinRunLoop(for: 0.4)

        let activeAfterStop = model.mixer.activeAudioSessionCount
        let restoredVolume = model.mixer.apps.first?.volume
        let voiceStatusAfterStop = model.voice.status
        let errorMessage = model.voice.errorMessage
        let insertedText = textInjector.insertedText
        let attemptedText = textInjector.attemptedText
        let sttLoadedAfterStop = sttEngine.isLoaded
        model.shutdown()

        guard activeWhileRecording == 1 else {
            fputs("Expected one active session while recording, got \(activeWhileRecording)\n", stderr)
            return 2
        }

        guard duckedVolume == 0.35 else {
            fputs("Expected ducked volume 0.35, got \(String(describing: duckedVolume))\n", stderr)
            return 3
        }

        guard !sttLoadedWhileRecording else {
            fputs("Expected STT engine to remain unloaded while recording\n", stderr)
            return 4
        }

        guard activeAfterStop == 0 else {
            fputs("Expected zero active sessions after paste failure, got \(activeAfterStop)\n", stderr)
            return 5
        }

        guard restoredVolume == 1 else {
            fputs("Expected restored volume 1.0 after paste failure, got \(String(describing: restoredVolume))\n", stderr)
            return 6
        }

        guard voiceStatusAfterStop == .idle else {
            fputs("Expected idle voice state after paste failure, got \(voiceStatusAfterStop)\n", stderr)
            return 7
        }

        guard errorMessage == HarnessError.pasteFailed.errorDescription else {
            fputs("Expected paste failure error message, got \(String(describing: errorMessage))\n", stderr)
            return 8
        }

        guard insertedText == nil, attemptedText == "MiniMix paste failure harness" else {
            fputs("Expected attempted paste with no insertion, got attempted=\(String(describing: attemptedText)) inserted=\(String(describing: insertedText))\n", stderr)
            return 9
        }

        guard !sttLoadedAfterStop else {
            fputs("Expected STT engine to be unloaded after paste failure\n", stderr)
            return 10
        }

        print("voicePasteFailureHarness activeWhileRecording=\(activeWhileRecording) duckedVolume=\(duckedVolume ?? -1) sttLoadedWhileRecording=\(sttLoadedWhileRecording) activeAfterStop=\(activeAfterStop) restoredVolume=\(restoredVolume ?? -1) status=\(voiceStatusAfterStop) attemptedText=\(attemptedText ?? "nil") insertedText=\(insertedText ?? "nil") sttLoadedAfterStop=\(sttLoadedAfterStop) error=\(errorMessage ?? "nil")")
        return 0
    }

    @MainActor
    private static func runControllerHarness() -> Int32 {
        let gain = argument(after: "--controller-harness").flatMap(Double.init) ?? 0.35
        let soundPath = argument(after: "--sound") ?? "/System/Library/Sounds/Ping.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            fputs("Missing sound file: \(soundPath)\n", stderr)
            return 2
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]

        do {
            try player.run()
            Thread.sleep(forTimeInterval: 0.15)

            let pid = player.processIdentifier
            let audioState = CoreAudioProcessInspector().snapshot(for: pid)
            guard let audioObjectID = audioState.processObjectID else {
                fputs("Could not resolve Core Audio process object for pid \(pid)\n", stderr)
                player.terminate()
                return 3
            }

            let app = ManagedAudioApp(
                id: "com.apple.afplay",
                displayName: "afplay",
                bundleIdentifier: "com.apple.afplay",
                processIdentifier: pid,
                audioObjectID: audioObjectID,
                volume: 1,
                isMuted: false,
                isProducingAudio: true,
                isDucked: false
            )

            let ruleStore = HarnessAudioRuleStore()
            let audioEngine = CoreAudioPerAppAudioEngine()
            let controller = MixerController(
                appProvider: HarnessRunningAudioAppProvider(apps: [app]),
                ruleStore: ruleStore,
                audioEngine: audioEngine
            )

            let initialAppCount = controller.state.apps.count
            controller.setVolume(for: app.id, to: gain)
            Thread.sleep(forTimeInterval: 0.8)

            let activeAfterVolume = controller.state.activeAudioSessionCount
            let sessionsAfterVolume = audioEngine.activeSessions
            let activeSession = sessionsAfterVolume.first
            let savedRule = ruleStore.rules[app.bundleIdentifier]
            let errorAfterVolume = controller.state.audioEngineLastError

            controller.resetApp(app.id)
            let activeAfterReset = controller.state.activeAudioSessionCount
            let sessionsAfterReset = audioEngine.activeSessions
            let ruleAfterReset = ruleStore.rules[app.bundleIdentifier]
            controller.shutdown()

            player.waitUntilExit()

            guard initialAppCount == 1 else {
                fputs("Expected one detected app, got \(initialAppCount)\n", stderr)
                return 4
            }

            guard activeAfterVolume == 1, sessionsAfterVolume.count == 1, let activeSession else {
                fputs("Expected one active session after volume change, got active=\(activeAfterVolume) sessions=\(sessionsAfterVolume). error=\(errorAfterVolume ?? "nil")\n", stderr)
                return 5
            }

            guard activeSession.tapID != kAudioObjectUnknown, activeSession.aggregateDeviceID != kAudioObjectUnknown else {
                fputs("Expected controller session to expose real tap and aggregate IDs, got \(activeSession)\n", stderr)
                return 6
            }

            guard abs(Double(activeSession.gain) - gain) < 0.0001, activeSession.isMuted == false else {
                fputs("Expected controller gain=\(gain) and unmuted state, got gain=\(activeSession.gain) muted=\(activeSession.isMuted)\n", stderr)
                return 7
            }

            guard savedRule?.volume == gain else {
                fputs("Expected saved rule volume \(gain), got \(String(describing: savedRule?.volume))\n", stderr)
                return 8
            }

            guard activeAfterReset == 0 else {
                fputs("Expected zero active sessions after reset, got \(activeAfterReset)\n", stderr)
                return 9
            }

            guard sessionsAfterReset.isEmpty else {
                fputs("Expected no active sessions after reset, got \(sessionsAfterReset)\n", stderr)
                return 10
            }

            guard ruleAfterReset == nil else {
                fputs("Expected rule removal after reset\n", stderr)
                return 11
            }

            let tapCount = currentTapCount()
            guard tapCount == 0 else {
                fputs("Expected zero Core Audio taps after cleanup, got \(tapCount)\n", stderr)
                return 12
            }

            emitHarnessLine("controllerHarness detectedApps=\(initialAppCount) activeAfterVolume=\(activeAfterVolume) activeAfterReset=\(activeAfterReset) tapCount=\(tapCount) gain=\(gain) activeTapID=\(activeSession.tapID) activeAggregateDeviceID=\(activeSession.aggregateDeviceID) activeGain=\(activeSession.gain) activeMuted=\(activeSession.isMuted) savedRuleVolume=\(savedRule?.volume ?? -1) ruleAfterReset=nil sessionsAfterReset=\(sessionsAfterReset.count)")
            return 0
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func argument(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = CommandLine.arguments.index(after: index)
        guard CommandLine.arguments.indices.contains(valueIndex) else {
            return nil
        }

        return CommandLine.arguments[valueIndex]
    }

    private static func emitHarnessLine(_ line: String) {
        print(line)

        guard let outputPath = argument(after: "--harness-output") else {
            return
        }

        do {
            try line.appending("\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
        } catch {
            fputs("Could not write harness output to \(outputPath): \(error.localizedDescription)\n", stderr)
        }
    }

    private static func speechAuthorizationStatusText(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        case .restricted:
            "restricted"
        case .notDetermined:
            "notDetermined"
        @unknown default:
            "unknown"
        }
    }

    private static func microphoneAuthorizationStatusText(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        case .restricted:
            "restricted"
        case .notDetermined:
            "notDetermined"
        @unknown default:
            "unknown"
        }
    }

    private static func generateSpeechFixture(text: String, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", outputURL.path, text]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HarnessError.speechFixtureFailed(process.terminationStatus)
        }
    }

    @MainActor
    private static func awaitBlocking(_ operation: @escaping () async throws -> Void) throws {
        var result: Result<Void, Error>?
        Task {
            do {
                try await operation()
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }

        while result == nil {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        try result!.get()
    }

    private static func normalizeForComparison(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func audioPlayer(soundPath: String) -> Process {
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [soundPath]
        return player
    }

    private static func managedApp(
        process: Process,
        displayName: String,
        bundleIdentifier: String,
        volume: Double
    ) throws -> ManagedAudioApp {
        let pid = process.processIdentifier
        let audioState = CoreAudioProcessInspector().snapshot(for: pid)
        guard let audioObjectID = audioState.processObjectID else {
            throw HarnessError.missingAudioProcess(pid)
        }

        return ManagedAudioApp(
            id: bundleIdentifier,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: pid,
            audioObjectID: audioObjectID,
            volume: volume,
            isMuted: false,
            isProducingAudio: audioState.isRunningOutput,
            isDucked: false
        )
    }

    private static func currentTapCount() -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return -1
        }

        return Int(size) / MemoryLayout<AudioObjectID>.size
    }

    private static func spinRunLoop(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor
    private static func waitFor(timeout seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return condition()
    }
}

private enum HarnessError: LocalizedError {
    case missingAudioProcess(pid_t)
    case speechFixtureFailed(Int32)
    case unexpectedTranscript(expected: String, actual: String)
    case unexpectedRecordingURL(started: String, stopped: String)
    case recorderStartFailed
    case pasteFailed
    case sttLoadFailed

    var errorDescription: String? {
        switch self {
        case let .missingAudioProcess(pid):
            "Could not resolve Core Audio process object for pid \(pid)"
        case let .speechFixtureFailed(status):
            "Could not generate Apple Speech audio fixture, say exited with status \(status)"
        case let .unexpectedTranscript(expected, actual):
            "Apple Speech transcript did not contain expected text. expected='\(expected)' actual='\(actual)'"
        case let .unexpectedRecordingURL(started, stopped):
            "Microphone recorder returned different URLs. started='\(started)' stopped='\(stopped)'"
        case .recorderStartFailed:
            "Harness recorder start failed."
        case .pasteFailed:
            "Harness paste failed."
        case .sttLoadFailed:
            "Harness STT load failed."
        }
    }
}

private final class HarnessRunningAudioAppProvider: RunningAudioAppProviding {
    var apps: [ManagedAudioApp]

    init(apps: [ManagedAudioApp]) {
        self.apps = apps
    }

    func runningApps() -> [ManagedAudioApp] {
        apps
    }
}

private final class HarnessAudioRuleStore: AudioRuleStoring {
    var rules: [String: AudioAppRule] = [:]

    func loadRules() -> [String: AudioAppRule] {
        rules
    }

    func saveRule(_ rule: AudioAppRule) {
        rules[rule.bundleIdentifier] = rule
    }

    func removeRule(for bundleIdentifier: String) {
        rules.removeValue(forKey: bundleIdentifier)
    }
}

private final class HarnessTrackingAudioEngine: PerAppAudioControlling {
    private var sessions: [String: PerAppAudioSessionStatus] = [:]
    private(set) var appliedApps: [String: ManagedAudioApp] = [:]

    var activeSessions: [PerAppAudioSessionStatus] {
        sessions.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }

    var diagnostics: PerAppAudioEngineDiagnostics {
        PerAppAudioEngineDiagnostics(activeSessionCount: sessions.count)
    }

    func apply(app: ManagedAudioApp) {
        guard app.needsAudioProcessing else {
            remove(bundleIdentifier: app.bundleIdentifier)
            return
        }

        appliedApps[app.bundleIdentifier] = app
        sessions[app.bundleIdentifier] = PerAppAudioSessionStatus(
            bundleIdentifier: app.bundleIdentifier,
            tapID: 1,
            aggregateDeviceID: 1,
            gain: app.processingGain,
            isMuted: app.isMuted
        )
    }

    func remove(bundleIdentifier: String) {
        sessions.removeValue(forKey: bundleIdentifier)
        appliedApps.removeValue(forKey: bundleIdentifier)
    }

    func shutdown() {
        sessions.removeAll()
        appliedApps.removeAll()
    }
}

@MainActor
private final class HarnessHotkeyController: PushToTalkHotkeyControlling {
    private(set) var statusText = "Harness hotkey"
    private var onPress: (@MainActor () -> Void)?
    private var onRelease: (@MainActor () -> Void)?

    func start(onPress: @escaping @MainActor () -> Void, onRelease: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        statusText = "Hold Control-Option-Space"
    }

    func stop() {
        onPress = nil
        onRelease = nil
        statusText = "Harness hotkey"
    }

    func simulatePress() {
        onPress?()
    }

    func simulateRelease() {
        onRelease?()
    }
}

private actor HarnessMicrophoneRecorder: MicrophoneRecording {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MiniMixHarness-\(UUID().uuidString)")
        .appendingPathExtension("caf")

    func start() async throws -> URL {
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        return url
    }

    func stop() async throws -> URL {
        url
    }
}

private actor TrackingHarnessMicrophoneRecorder: MicrophoneRecording {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MiniMixTrackingHarness-\(UUID().uuidString)")
        .appendingPathExtension("caf")
    private var didStart = false
    private var didStop = false

    func start() async throws -> URL {
        didStart = true
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        return url
    }

    func stop() async throws -> URL {
        didStop = true
        return url
    }

    func status() -> (didStart: Bool, didStop: Bool, path: String) {
        (didStart, didStop, url.path)
    }
}

private actor DelayedHarnessMicrophoneRecorder: MicrophoneRecording {
    private let delayNanoseconds: UInt64
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MiniMixDelayedHarness-\(UUID().uuidString)")
        .appendingPathExtension("caf")
    private var didStart = false
    private var didStop = false

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func start() async throws -> URL {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        didStart = true
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        return url
    }

    func stop() async throws -> URL {
        didStop = true
        return url
    }

    func status() -> (didStart: Bool, didStop: Bool, path: String) {
        (didStart, didStop, url.path)
    }
}

private actor FailingHarnessMicrophoneRecorder: MicrophoneRecording {
    func start() async throws -> URL {
        throw HarnessError.recorderStartFailed
    }

    func stop() async throws -> URL {
        throw HarnessError.recorderStartFailed
    }
}

@MainActor
private final class HarnessSTTEngine: STTEngine {
    private let transcript: String
    private(set) var isLoaded = false
    private(set) var transcribedFilePath: String?
    private(set) var transcribedFileBytes: UInt64?

    init(transcript: String) {
        self.transcript = transcript
    }

    func load() async throws {
        isLoaded = true
    }

    func transcribe(_ source: AudioSource) async throws -> Transcript {
        if case let .file(url) = source {
            transcribedFilePath = url.path
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            transcribedFileBytes = attributes?[.size] as? UInt64
        }
        return Transcript(text: transcript)
    }

    func unloadIfIdle() async {
        isLoaded = false
    }
}

@MainActor
private final class FailingHarnessSTTEngine: STTEngine {
    private(set) var isLoaded = false

    func load() async throws {
        throw HarnessError.sttLoadFailed
    }

    func transcribe(_ source: AudioSource) async throws -> Transcript {
        throw HarnessError.sttLoadFailed
    }

    func unloadIfIdle() async {
        isLoaded = false
    }
}

@MainActor
private final class HarnessTextInjector: TextInjecting {
    private(set) var insertedText: String?

    func insert(_ text: String) throws {
        insertedText = text
    }
}

@MainActor
private final class FailingHarnessTextInjector: TextInjecting {
    private(set) var attemptedText: String?
    private(set) var insertedText: String?

    func insert(_ text: String) throws {
        attemptedText = text
        throw HarnessError.pasteFailed
    }
}
