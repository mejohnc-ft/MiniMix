#!/usr/bin/env bash
set -euo pipefail

sound="${1:-$(scripts/ensure-silent-audio-fixture.sh)}"

swift build
.build/debug/MiniMix --voice-real-recorder-harness --sound "$sound"
