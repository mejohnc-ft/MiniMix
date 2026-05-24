#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
scripts/guard-coreaudio-load.sh

swift build
.build/debug/MiniMix --voice-early-release-harness
