#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${1:-2}"

if pgrep -x MiniMix >/dev/null 2>&1; then
  osascript -e 'tell application "MiniMix" to quit' >/dev/null 2>&1 &
  quit_pid=$!
  deadline=$((SECONDS + timeout_seconds))

  while kill -0 "$quit_pid" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      kill "$quit_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.1
  done

  wait "$quit_pid" >/dev/null 2>&1 || true
fi

pkill -x MiniMix >/dev/null 2>&1 || true
