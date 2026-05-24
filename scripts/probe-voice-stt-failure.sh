#!/usr/bin/env bash
set -euo pipefail

swift build
.build/debug/MiniMix --voice-stt-failure-harness
