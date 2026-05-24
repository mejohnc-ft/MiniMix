import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation

final class CoreAudioPerAppAudioEngine: PerAppAudioControlling {
    private var sessions: [String: CoreAudioManagedAudioSession] = [:]
    private var requestedApps: [String: ManagedAudioApp] = [:]
    private var restartCount = 0
    private var lastError: String?
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?

    var activeSessions: [PerAppAudioSessionStatus] {
        sessions.values.map(\.status).sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }

    var diagnostics: PerAppAudioEngineDiagnostics {
        PerAppAudioEngineDiagnostics(
            activeSessionCount: sessions.count,
            lastError: lastError,
            restartCount: restartCount
        )
    }

    func apply(app: ManagedAudioApp) {
        guard app.needsAudioProcessing else {
            remove(bundleIdentifier: app.bundleIdentifier)
            return
        }

        guard let processObjectID = app.audioObjectID else {
            remove(bundleIdentifier: app.bundleIdentifier)
            return
        }

        requestedApps[app.bundleIdentifier] = app

        if let session = sessions[app.bundleIdentifier] {
            session.update(gain: app.processingGain, isMuted: app.isMuted)
            return
        }

        do {
            try installOutputDeviceListenerIfNeeded()
            let session = CoreAudioManagedAudioSession(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.displayName,
                processObjectID: AudioObjectID(processObjectID),
                gain: app.processingGain,
                isMuted: app.isMuted
            )
            try session.start()
            sessions[app.bundleIdentifier] = session
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            remove(bundleIdentifier: app.bundleIdentifier)
        }
    }

    func remove(bundleIdentifier: String) {
        requestedApps.removeValue(forKey: bundleIdentifier)
        sessions.removeValue(forKey: bundleIdentifier)?.stop()
        if sessions.isEmpty {
            removeOutputDeviceListenerIfNeeded()
        }
    }

    func shutdown() {
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
        requestedApps.removeAll()
        removeOutputDeviceListenerIfNeeded()
    }

    deinit {
        shutdown()
    }

    func simulateOutputDeviceChangeForTesting() {
        restartSessionsForOutputDeviceChange()
    }

    private func restartSessionsForOutputDeviceChange() {
        let apps = requestedApps.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
        restartCount += 1

        for app in apps {
            apply(app: app)
        }
    }

    private func installOutputDeviceListenerIfNeeded() throws {
        guard outputDeviceListener == nil else {
            return
        }

        var address = Self.defaultOutputDeviceAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.restartSessionsForOutputDeviceChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )

        guard status == noErr else {
            throw CoreAudioEngineError.operationFailed("AudioObjectAddPropertyListenerBlock", status)
        }

        outputDeviceListener = listener
    }

    private func removeOutputDeviceListenerIfNeeded() {
        guard let outputDeviceListener else {
            return
        }

        var address = Self.defaultOutputDeviceAddress
        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            outputDeviceListener
        )
        self.outputDeviceListener = nil
    }

    private static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

private final class CoreAudioManagedAudioSession {
    private final class CallbackState {
        var gain: Float
        var isMuted: Bool

        init(gain: Float, isMuted: Bool) {
            self.gain = gain
            self.isMuted = isMuted
        }
    }

    private let bundleIdentifier: String
    private let displayName: String
    private let processObjectID: AudioObjectID
    private let tapUUID = UUID()
    private let callbackState: CallbackState

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var callbackStatePointer: UnsafeMutableRawPointer?
    private var isStarted = false

    init(
        bundleIdentifier: String,
        displayName: String,
        processObjectID: AudioObjectID,
        gain: Float,
        isMuted: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.processObjectID = processObjectID
        self.callbackState = CallbackState(gain: gain, isMuted: isMuted)
    }

    var status: PerAppAudioSessionStatus {
        PerAppAudioSessionStatus(
            bundleIdentifier: bundleIdentifier,
            tapID: tapID,
            aggregateDeviceID: aggregateDeviceID,
            gain: callbackState.gain,
            isMuted: callbackState.isMuted
        )
    }

    func start() throws {
        guard !isStarted else {
            return
        }

        do {
            let outputUID = try Self.defaultOutputDeviceUID()
            try createTap()
            try createAggregateDevice(outputUID: outputUID)
            try createAndStartIOProc()
            isStarted = true
        } catch {
            stop()
            throw error
        }
    }

    func update(gain: Float, isMuted: Bool) {
        callbackState.gain = gain
        callbackState.isMuted = isMuted
    }

    func stop() {
        if let ioProcID {
            _ = AudioDeviceStop(aggregateDeviceID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        if let callbackStatePointer {
            Unmanaged<CallbackState>.fromOpaque(callbackStatePointer).release()
            self.callbackStatePointer = nil
        }

        isStarted = false
    }

    deinit {
        stop()
    }

    private func createTap() throws {
        guard #available(macOS 14.2, *) else {
            throw CoreAudioEngineError.unsupportedPlatform("Core Audio process taps require macOS 14.2 or newer.")
        }

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.name = "MiniMix \(displayName)"
        tapDescription.uuid = tapUUID
        tapDescription.isPrivate = true
        if #available(macOS 26.0, *) {
            tapDescription.isProcessRestoreEnabled = true
        }
        tapDescription.muteBehavior = CATapMuteBehavior.mutedWhenTapped

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard status == noErr else {
            throw CoreAudioEngineError.operationFailed("AudioHardwareCreateProcessTap", status)
        }

        tapID = createdTapID
    }

    private func createAggregateDevice(outputUID: String) throws {
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceUIDKey: "dev.minimix.\(bundleIdentifier).\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "MiniMix \(displayName)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID,
                    kAudioSubDeviceDriftCompensationKey: true
                ]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var createdAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &createdAggregateDeviceID)
        guard status == noErr else {
            throw CoreAudioEngineError.operationFailed("AudioHardwareCreateAggregateDevice", status)
        }

        aggregateDeviceID = createdAggregateDeviceID
    }

    private func createAndStartIOProc() throws {
        let pointer = Unmanaged.passRetained(callbackState).toOpaque()
        var createdIOProcID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcID(aggregateDeviceID, Self.ioProc, pointer, &createdIOProcID)
        guard status == noErr, let createdIOProcID else {
            Unmanaged<CallbackState>.fromOpaque(pointer).release()
            throw CoreAudioEngineError.operationFailed("AudioDeviceCreateIOProcID", status)
        }

        callbackStatePointer = pointer
        ioProcID = createdIOProcID

        status = AudioDeviceStart(aggregateDeviceID, createdIOProcID)
        guard status == noErr else {
            throw CoreAudioEngineError.operationFailed("AudioDeviceStart", status)
        }
    }

    private static let ioProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
        guard let clientData else {
            return noErr
        }

        let state = Unmanaged<CallbackState>.fromOpaque(clientData).takeUnretainedValue()
        applyGain(inputData: inputData, outputData: outputData, gain: state.isMuted ? 0 : state.gain)
        return noErr
    }

    private static func applyGain(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        gain: Float
    ) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
        let count = min(inputBuffers.count, outputBuffers.count)

        guard count > 0 else {
            return
        }

        for index in 0..<count {
            let inputBuffer = inputBuffers[index]
            var outputBuffer = outputBuffers[index]
            let byteCount = min(Int(inputBuffer.mDataByteSize), Int(outputBuffer.mDataByteSize))

            guard byteCount > 0, let input = inputBuffer.mData, let output = outputBuffer.mData else {
                continue
            }

            let frameCount = byteCount / MemoryLayout<Float>.stride
            let inputSamples = input.assumingMemoryBound(to: Float.self)
            let outputSamples = output.assumingMemoryBound(to: Float.self)

            for frame in 0..<frameCount {
                outputSamples[frame] = inputSamples[frame] * gain
            }

            outputBuffer.mDataByteSize = UInt32(byteCount)
        }
    }

    private static func defaultOutputDeviceUID() throws -> String {
        let deviceID = try defaultOutputDeviceID()
        return try stringProperty(kAudioDevicePropertyDeviceUID, objectID: deviceID)
    }

    private static func defaultOutputDeviceID() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw CoreAudioEngineError.operationFailed("kAudioHardwarePropertyDefaultOutputDevice", status)
        }

        return deviceID
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, objectID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw CoreAudioEngineError.operationFailed("AudioObjectGetPropertyDataSize", status)
        }

        var value: CFString?
        status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
        }

        guard status == noErr, let value else {
            throw CoreAudioEngineError.operationFailed("AudioObjectGetPropertyData", status)
        }

        return value as String
    }
}

private enum CoreAudioEngineError: LocalizedError {
    case unsupportedPlatform(String)
    case operationFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unsupportedPlatform(message):
            message
        case let .operationFailed(operation, status):
            "\(operation) failed with OSStatus \(status)"
        }
    }
}
