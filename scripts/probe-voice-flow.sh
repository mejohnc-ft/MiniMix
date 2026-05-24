#!/usr/bin/env bash
set -euo pipefail

sound="${1:-}"

if [[ -z "$sound" ]]; then
  scripts/guard-coreaudio-load.sh
  sound="$(scripts/ensure-silent-audio-fixture.sh)"
fi

swift build
.build/debug/MiniMix --voice-harness --sound "$sound"
