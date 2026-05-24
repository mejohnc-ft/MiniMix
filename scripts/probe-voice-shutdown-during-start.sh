#!/usr/bin/env bash
set -euo pipefail

sound="${1:-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
scripts/guard-coreaudio-load.sh

if [[ -z "$sound" ]]; then
  sound="$(scripts/ensure-silent-audio-fixture.sh)"
fi

swift build
.build/debug/MiniMix --voice-shutdown-during-start-harness --sound "$sound"
