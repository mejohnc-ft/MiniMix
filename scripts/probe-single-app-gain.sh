#!/usr/bin/env bash
set -euo pipefail

gain="${1:-0.35}"
sound="${2:-$(scripts/ensure-silent-audio-fixture.sh)}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$repo_root/scripts/guard-coreaudio-load.sh"

if [ ! -f "$sound" ]; then
  echo "Missing sound file: $sound" >&2
  exit 1
fi

tmp_dir="$(mktemp -d -t minimix-gain-probe.XXXXXX)"
tmp_swift="$tmp_dir/main.swift"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_swift" <<'SWIFT'
import AudioToolbox
import CoreAudio
import Foundation

final class ProbeState {
    let gain: Float
    var callbacks = 0

    init(gain: Float) {
        self.gain = gain
    }
}

enum ProbeError: Error {
    case operationFailed(String, OSStatus)
    case missingDefaultOutput
}

let ioProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
    guard let clientData else { return noErr }
    let state = Unmanaged<ProbeState>.fromOpaque(clientData).takeUnretainedValue()
    state.callbacks += 1

    let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
    let count = min(inputBuffers.count, outputBuffers.count)

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
            outputSamples[frame] = inputSamples[frame] * state.gain
        }

        outputBuffer.mDataByteSize = UInt32(byteCount)
    }

    return noErr
}

func check(_ operation: String, _ status: OSStatus) throws {
    guard status == noErr else {
        throw ProbeError.operationFailed(operation, status)
    }
}

func processObjectID(for pid: pid_t) throws -> AudioObjectID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var qualifierPID = pid
    var processObjectID = AudioObjectID(kAudioObjectUnknown)
    var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
    try check(
        "kAudioHardwarePropertyTranslatePIDToProcessObject",
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &qualifierPID,
            &dataSize,
            &processObjectID
        )
    )
    return processObjectID
}

func defaultOutputDeviceID() throws -> AudioObjectID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
    try check(
        "kAudioHardwarePropertyDefaultOutputDevice",
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
    )
    return deviceID
}

func stringProperty(_ selector: AudioObjectPropertySelector, objectID: AudioObjectID) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    try check("AudioObjectGetPropertyDataSize", AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize))

    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
    }
    try check("AudioObjectGetPropertyData", status)

    guard let value else {
        throw ProbeError.missingDefaultOutput
    }
    return value as String
}

let pid = pid_t(CommandLine.arguments[1])!
let gain = Float(CommandLine.arguments[2])!
let targetProcessObjectID = try processObjectID(for: pid)
let outputUID = try stringProperty(kAudioDevicePropertyDeviceUID, objectID: try defaultOutputDeviceID())
let tapUUID = UUID()

let tap = CATapDescription(stereoMixdownOfProcesses: [targetProcessObjectID])
tap.name = "MiniMix Gain Probe"
tap.uuid = tapUUID
tap.isPrivate = true
tap.muteBehavior = CATapMuteBehavior.mutedWhenTapped

var tapID = AudioObjectID(kAudioObjectUnknown)
try check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(tap, &tapID))

var aggregateID = AudioObjectID(kAudioObjectUnknown)
let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceUIDKey: "dev.minimix.gainprobe.\(UUID().uuidString)",
    kAudioAggregateDeviceNameKey: "MiniMix Gain Probe",
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceMainSubDeviceKey: outputUID,
    kAudioAggregateDeviceSubDeviceListKey: [[
        kAudioSubDeviceUIDKey: outputUID,
        kAudioSubDeviceDriftCompensationKey: true
    ]],
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceTapListKey: [[
        kAudioSubTapUIDKey: tapUUID.uuidString,
        kAudioSubTapDriftCompensationKey: true
    ]]
]

try check("AudioHardwareCreateAggregateDevice", AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID))

let state = ProbeState(gain: gain)
let statePointer = Unmanaged.passRetained(state).toOpaque()
var ioProcID: AudioDeviceIOProcID?
try check("AudioDeviceCreateIOProcID", AudioDeviceCreateIOProcID(aggregateID, ioProc, statePointer, &ioProcID))
try check("AudioDeviceStart", AudioDeviceStart(aggregateID, ioProcID))

Thread.sleep(forTimeInterval: 1.0)

_ = AudioDeviceStop(aggregateID, ioProcID)
if let ioProcID {
    _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
}
_ = AudioHardwareDestroyAggregateDevice(aggregateID)
_ = AudioHardwareDestroyProcessTap(tapID)
Unmanaged<ProbeState>.fromOpaque(statePointer).release()

print("processObjectID=\(targetProcessObjectID) tapID=\(tapID) aggregateID=\(aggregateID) callbacks=\(state.callbacks) gain=\(gain)")
SWIFT

afplay "$sound" >/dev/null 2>&1 &
player_pid=$!
sleep 0.15

xcrun swift "$tmp_swift" "$player_pid" "$gain"
wait "$player_pid" 2>/dev/null || true
