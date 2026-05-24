#!/usr/bin/env bash
set -euo pipefail

text="${1:-MiniMix speech baseline}"
audio="${2:-/tmp/minimix-apple-speech-harness.aiff}"

swift build
.build/debug/MiniMix --apple-speech-harness --text "$text" --speech-audio "$audio"
