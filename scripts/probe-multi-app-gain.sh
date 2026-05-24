#!/usr/bin/env bash
set -euo pipefail

first_gain="${1:-0.35}"
second_gain="${2:-0.55}"
sound="${3:-$(scripts/ensure-silent-audio-fixture.sh)}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
scripts/guard-coreaudio-load.sh

swift build
.build/debug/MiniMix --multi-harness --first-gain "$first_gain" --second-gain "$second_gain" --sound "$sound"
