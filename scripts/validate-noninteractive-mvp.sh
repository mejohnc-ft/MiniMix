#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
  osascript -e 'tell application "QuickTime Player" to quit' >/dev/null 2>&1 || pkill -x "QuickTime Player" >/dev/null 2>&1 || true
  pkill -x afplay >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$repo_root"

require_clean_coreaudio() {
  local status
  status="$(scripts/probe-coreaudio-residue.sh)"
  if [[ "$status" != *"count=0"* ]]; then
    echo "Core Audio taps were not clean: $status" >&2
    exit 20
  fi
  if [[ "$status" != *"minimixDeviceCount=0"* ]]; then
    echo "Core Audio MiniMix devices were not clean: $status" >&2
    exit 20
  fi
  echo "$status"
}

launch_minimix_for_check() {
  open -g "$repo_root/build/MiniMix.app" >/dev/null 2>&1 || (
    "$repo_root/build/MiniMix.app/Contents/MacOS/MiniMix" >/tmp/minimix-release-idle.log 2>&1 &
  )
}

cleanup

echo "== Build =="
swift build
scripts/build-app-bundle.sh debug >/dev/null
swift build -c release
scripts/build-app-bundle.sh release >/dev/null

echo "== Silent Core Audio probes =="
scripts/probe-app-state.sh
scripts/probe-single-app-gain.sh 0.35
scripts/probe-app-engine-gain.sh 0.35
scripts/probe-controller-gain.sh 0.35
scripts/probe-multi-app-gain.sh 0.35 0.55

echo "== Silent voice probes =="
scripts/probe-hotkey-registration.sh
scripts/probe-voice-flow.sh
scripts/probe-voice-early-release.sh
scripts/probe-voice-hotkey-early-release.sh
scripts/probe-voice-recorder-failure.sh
scripts/probe-voice-stt-failure.sh
scripts/probe-voice-paste-failure.sh

if [[ "${MINIMIX_RUN_UI_PROBES:-0}" == "1" ]]; then
  echo "== Packaged UI probes =="
  scripts/probe-packaged-voice-permissions.sh release
  scripts/probe-packaged-ui-gain.sh release
else
  echo "packagedUI skipped reason=MINIMIX_RUN_UI_PROBES not set"
fi

echo "== Release idle footprint =="
launch_minimix_for_check
sleep 6
pid="$(pgrep -x MiniMix | head -1)"
if [[ -z "$pid" ]]; then
  echo "MiniMix did not launch for idle footprint check" >&2
  exit 21
fi
footprint="$(ps -o pid=,%cpu=,rss=,comm= -p "$pid")"
echo "$footprint"
rss_kb="$(awk '{print $3}' <<< "$footprint")"
if [[ -z "$rss_kb" || "$rss_kb" -gt 51200 ]]; then
  echo "Release RSS expected <= 51200 KB, got ${rss_kb:-unknown}" >&2
  exit 22
fi

minimix_processes="$(pgrep -x MiniMix || true)"
echo "$minimix_processes"
minimix_process_count="$(printf '%s\n' "$minimix_processes" | rg -c '^[0-9]+$' || true)"
if [[ "$minimix_process_count" -ne 1 ]]; then
  echo "Expected exactly one MiniMix process while app is running" >&2
  exit 27
fi

if find /Library/Audio/Plug-Ins/HAL -maxdepth 3 -iname '*MiniMix*' -print 2>/dev/null | rg -q .; then
  echo "Unexpected MiniMix HAL driver found while app is running" >&2
  exit 28
fi

if find "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons -maxdepth 1 -iname '*MiniMix*' -print 2>/dev/null | rg -q .; then
  echo "Unexpected MiniMix launch agent or daemon found while app is running" >&2
  exit 29
fi

cleanup
sleep 0.5

echo "== Cleanup checks =="
require_clean_coreaudio

if pmset -g assertions | rg -i 'MiniMix|QuickTime'; then
  echo "MiniMix or QuickTime sleep assertion remained" >&2
  exit 23
fi

if pgrep -x MiniMix || pgrep -x "QuickTime Player" || pgrep -x afplay; then
  echo "MiniMix, QuickTime Player, or afplay remained running" >&2
  exit 24
fi

if find /Library/Audio/Plug-Ins/HAL -maxdepth 3 -iname '*MiniMix*' -print 2>/dev/null | rg -q .; then
  echo "Unexpected MiniMix HAL driver found" >&2
  exit 25
fi

if find "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons -maxdepth 1 -iname '*MiniMix*' -print 2>/dev/null | rg -q .; then
  echo "Unexpected MiniMix launch agent or daemon found" >&2
  exit 26
fi

echo "noninteractiveMVP ok"
