import AVFoundation
import ApplicationServices
import Foundation
import Speech

enum VoicePermissionRequester {
    static func requestNeededPermissions() async -> VoicePermissionState {
        await requestMicrophoneIfNeeded()
        await requestSpeechIfNeeded()
        requestAccessibilityIfNeeded()
        return VoicePermissionState.current()
    }

    private static func requestMicrophoneIfNeeded() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            return
        }

        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    private static func requestSpeechIfNeeded() async {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
            return
        }

        _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else {
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
