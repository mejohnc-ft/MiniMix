#!/usr/bin/env bash
set -euo pipefail

sound="${1:-$(scripts/ensure-silent-audio-fixture.sh)}"

swift build
.build/debug/MiniMix --process-inspector-harness --sound "$sound"
