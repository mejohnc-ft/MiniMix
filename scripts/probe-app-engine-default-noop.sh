#!/usr/bin/env bash
set -euo pipefail

sound="${2:-${1:-}}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ -z "$sound" ]]; then
  sound="$(scripts/ensure-silent-audio-fixture.sh)"
fi

swift build
.build/debug/MiniMix --default-noop-harness --sound "$sound"
