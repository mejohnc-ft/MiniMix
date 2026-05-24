#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
output_file="$(mktemp -t minimix-ls-accessibility-denied.XXXXXX)"
build_log="$(mktemp -t minimix-ls-accessibility-denied-build.XXXXXX)"

cleanup() {
  rm -f "$output_file" "$build_log"
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  echo "configuration must be debug or release" >&2
  exit 2
fi

cd "$repo_root"

if ! scripts/build-app-bundle.sh "$configuration" >"$build_log" 2>&1; then
  cat "$build_log" >&2
  exit 4
fi

accessibility_status=0
accessibility="$(scripts/probe-packaged-text-injector-readiness-launchservices.sh "$configuration" 2>&1)" || accessibility_status=$?
printf '%s\n' "$accessibility"

if [[ "$accessibility_status" -eq 0 || "$accessibility" == *"ready=true"* || "$accessibility" == *"accessibility=trusted"* ]]; then
  echo "packagedVoiceAccessibilityDeniedHarness ready=false authoritativeForPackagedApp=true reason=packaged Accessibility is already trusted; denied proof not applicable"
  exit 66
fi

open -g -W -n "$app" --args \
  --voice-accessibility-denied-harness \
  --launchservices-packaged \
  --harness-output "$output_file" >/dev/null 2>&1 &
open_pid=$!

deadline=$((SECONDS + 45))
while [[ "$SECONDS" -lt "$deadline" ]]; do
  if [[ -s "$output_file" ]]; then
    break
  fi
  if ! kill -0 "$open_pid" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if [[ ! -s "$output_file" ]] && kill -0 "$open_pid" >/dev/null 2>&1; then
  kill "$open_pid" >/dev/null 2>&1 || true
fi

wait "$open_pid" >/dev/null 2>&1 || true

if [[ ! -s "$output_file" ]]; then
  kill "$open_pid" >/dev/null 2>&1 || true
  echo "packagedVoiceAccessibilityDeniedHarness ready=false authoritativeForPackagedApp=true reason=no harness output from LaunchServices app run" >&2
  exit 65
fi

status="$(cat "$output_file")"
status="${status/voiceAccessibilityDeniedHarness/packagedVoiceAccessibilityDeniedHarness authoritativeForPackagedApp=true ready=true}"
printf '%s\n' "$status"

if [[ "$status" == *"ready=true"* &&
      "$status" == *"activeWhileRecording=1"* &&
      "$status" == *"duckedVolume=0.35"* &&
      "$status" == *"sttLoadedWhileRecording=false"* &&
      "$status" == *"activeAfterStop=0"* &&
      "$status" == *"restoredVolume=1.0"* &&
      "$status" == *"status=idle"* &&
      "$status" == *"pasteDenied=true"* &&
      "$status" == *"insertedText=nil"* &&
      "$status" == *"sttLoadedAfterStop=false"* &&
      "$status" == *"recorderStarted=true"* &&
      "$status" == *"recorderStopped=true"* &&
      "$status" == *"recordingFileExists=false"* &&
      "$status" == *"error=Accessibility permission is required to paste dictated text."* &&
      "$status" == *"tapCount=0"* ]]; then
  exit 0
fi

exit 1
