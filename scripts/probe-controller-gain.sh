#!/usr/bin/env bash
set -euo pipefail

gain="${1:-0.35}"
sound="${2:-$(scripts/ensure-silent-audio-fixture.sh)}"

swift build
.build/debug/MiniMix --controller-harness "$gain" --sound "$sound"
