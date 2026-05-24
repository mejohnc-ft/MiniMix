#!/usr/bin/env bash
set -euo pipefail

gain="${1:-0.35}"
sound="${2:-$(scripts/ensure-silent-audio-fixture.sh)}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
scripts/guard-coreaudio-load.sh

swift build
.build/debug/MiniMix --output-device-harness "$gain" --sound "$sound"
