import AVFoundation
import ApplicationServices
import Foundation
import Speech

struct VoicePermissionState: Equatable {
    enum Readiness: Equatable {
        case ready
        case needsPermission
    }

    var microphone: String
    var speech: String
    var accessibility: String

    var readiness: Readiness {
        microphone == "Authorized" && speech == "Authorized" && accessibility == "Trusted" ? .ready : .needsPermission
    }

    var summary: String {
        switch readiness {
        case .ready:
            "Voice permissions ready"
        case .needsPermission:
            "Needs: \(missingPermissions.joined(separator: ", "))"
        }
    }

    var detailText: String {
        "Mic \(microphone) · Speech \(speech) · Accessibility \(accessibility)"
    }

    private var missingPermissions: [String] {
        var missing: [String] = []
        if microphone != "Authorized" {
            missing.append("Mic")
        }
        if speech != "Authorized" {
            missing.append("Speech")
        }
        if accessibility != "Trusted" {
            missing.append("Accessibility")
        }
        return missing
    }

    static func current() -> VoicePermissionState {
        VoicePermissionState(
            microphone: microphoneStatus(),
            speech: speechStatus(),
            accessibility: AXIsProcessTrusted() ? "Trusted" : "Not trusted"
        )
    }

    private static func microphoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            "Authorized"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }

    private static func speechStatus() -> String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            "Authorized"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }
}
