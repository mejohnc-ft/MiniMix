import CoreAudio
import Foundation

struct AudioProcessSnapshot: Equatable {
    let processObjectID: UInt32?
    let isRunningOutput: Bool
}

protocol AudioProcessInspecting {
    func snapshot(for pid: pid_t) -> AudioProcessSnapshot
}

final class CoreAudioProcessInspector: AudioProcessInspecting {
    func snapshot(for pid: pid_t) -> AudioProcessSnapshot {
        guard let processObjectID = processObjectID(for: pid), processObjectID != kAudioObjectUnknown else {
            return AudioProcessSnapshot(processObjectID: nil, isRunningOutput: false)
        }

        return AudioProcessSnapshot(
            processObjectID: processObjectID,
            isRunningOutput: boolProperty(kAudioProcessPropertyIsRunningOutput, objectID: processObjectID)
        )
    }

    private func processObjectID(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var qualifierPID = pid
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &qualifierPID,
            &dataSize,
            &processObjectID
        )

        guard status == noErr else {
            return nil
        }

        return processObjectID
    }

    private func boolProperty(_ selector: AudioObjectPropertySelector, objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)

        return status == noErr && value != 0
    }
}
