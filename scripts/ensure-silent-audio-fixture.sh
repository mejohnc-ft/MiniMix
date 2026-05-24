#!/usr/bin/env bash
set -euo pipefail

fixture="${1:-/tmp/minimix-silent-fixture.caf}"
duration_seconds="${MINIMIX_SILENT_SECONDS:-3}"

if [[ ! -f "$fixture" ]]; then
  xcrun swift - "$fixture" "$duration_seconds" 2>/dev/null <<'SWIFT'
import AVFAudio
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let sampleRate = 48_000.0
let durationSeconds = Int(CommandLine.arguments[2]) ?? 3
let frameCount = AVAudioFrameCount(Int(sampleRate) * durationSeconds)
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
let file = try AVAudioFile(forWriting: url, settings: format.settings)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
buffer.frameLength = frameCount
try file.write(from: buffer)
SWIFT
fi

printf '%s\n' "$fixture"
