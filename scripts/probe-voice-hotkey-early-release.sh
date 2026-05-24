#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swift build >/dev/null
.build/debug/MiniMix --voice-hotkey-early-release-harness
