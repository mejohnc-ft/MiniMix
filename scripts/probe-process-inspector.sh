#!/usr/bin/env bash
set -euo pipefail

sound="${1:-$(scripts/ensure-silent-audio-fixture.sh)}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
scripts/guard-coreaudio-load.sh

swift build
.build/debug/MiniMix --process-inspector-harness --sound "$sound"
