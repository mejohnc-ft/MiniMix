#!/usr/bin/env bash
set -euo pipefail

xcrun swift - <<'SWIFT'
import CoreAudio
import Foundation

func objectIDs(selector: AudioObjectPropertySelector, objectID: AudioObjectID = AudioObjectID(kAudioObjectSystemObject)) -> (OSStatus, OSStatus, [AudioObjectID]) {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var size: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
    guard sizeStatus == noErr, size > 0 else {
        return (sizeStatus, noErr, [])
    }

    var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    let dataStatus = values.withUnsafeMutableBufferPointer { buffer in
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer.baseAddress!)
    }

    return (sizeStatus, dataStatus, dataStatus == noErr ? values : [])
}

func stringProperty(_ selector: AudioObjectPropertySelector, objectID: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr else {
        return nil
    }

    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
    }

    guard status == noErr else {
        return nil
    }

    return value as String?
}

let taps = objectIDs(selector: kAudioHardwarePropertyTapList)
print("tapListStatus=\(taps.0)/\(taps.1) count=\(taps.2.count) taps=\(taps.2)")

let devices = objectIDs(selector: kAudioHardwarePropertyDevices)
let minimixDevices = devices.2.compactMap { deviceID -> String? in
    let name = stringProperty(kAudioObjectPropertyName, objectID: deviceID) ?? ""
    let uid = stringProperty(kAudioDevicePropertyDeviceUID, objectID: deviceID) ?? ""
    let combined = "\(name) \(uid)"
    guard combined.localizedCaseInsensitiveContains("MiniMix") || combined.localizedCaseInsensitiveContains("dev.minimix") else {
        return nil
    }
    return "\(deviceID):\(name):\(uid)"
}

print("audioDeviceStatus=\(devices.0)/\(devices.1) minimixDeviceCount=\(minimixDevices.count) devices=\(minimixDevices)")
SWIFT
