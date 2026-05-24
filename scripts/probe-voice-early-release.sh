#!/usr/bin/env bash
set -euo pipefail

swift build
.build/debug/MiniMix --voice-early-release-harness
