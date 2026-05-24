import Foundation

struct PerAppAudioSessionStatus: Equatable {
    let bundleIdentifier: String
    let tapID: UInt32
    let aggregateDeviceID: UInt32
    let gain: Float
    let isMuted: Bool
}

struct PerAppAudioEngineDiagnostics: Equatable {
    var activeSessionCount: Int = 0
    var lastError: String?
    var restartCount: Int = 0
}

protocol PerAppAudioControlling: AnyObject {
    var activeSessions: [PerAppAudioSessionStatus] { get }
    var diagnostics: PerAppAudioEngineDiagnostics { get }
    func apply(app: ManagedAudioApp)
    func remove(bundleIdentifier: String)
    func shutdown()
}

final class DisabledPerAppAudioEngine: PerAppAudioControlling {
    var activeSessions: [PerAppAudioSessionStatus] { [] }
    var diagnostics: PerAppAudioEngineDiagnostics { PerAppAudioEngineDiagnostics() }
    func apply(app: ManagedAudioApp) {}
    func remove(bundleIdentifier: String) {}
    func shutdown() {}
}
