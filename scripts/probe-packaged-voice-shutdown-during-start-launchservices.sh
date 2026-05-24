#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
sound="$(mktemp -t minimix-packaged-voice-shutdown-start.XXXXXX).caf"
output_file="$(mktemp -t minimix-ls-voice-shutdown-start.XXXXXX)"
build_log="$(mktemp -t minimix-ls-voice-shutdown-start-build.XXXXXX)"

cleanup() {
  rm -f "$sound" "$output_file" "$build_log"
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
  pkill -x afplay >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  echo "configuration must be debug or release" >&2
  exit 2
fi

cd "$repo_root"
scripts/guard-coreaudio-load.sh

MINIMIX_SILENT_SECONDS=3 scripts/ensure-silent-audio-fixture.sh "$sound" >/dev/null

if ! scripts/build-app-bundle.sh "$configuration" >"$build_log" 2>&1; then
  cat "$build_log" >&2
  exit 4
fi

if [[ ! -d "$app" ]]; then
  echo "packagedVoiceShutdownDuringStartHarness ready=false authoritativeForPackagedApp=true reason=missing app bundle" >&2
  exit 3
fi

open -g -W -n "$app" --args \
  --voice-shutdown-during-start-harness \
  --launchservices-packaged \
  --sound "$sound" \
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
  echo "packagedVoiceShutdownDuringStartHarness ready=false authoritativeForPackagedApp=true reason=no harness output from LaunchServices app run" >&2
  exit 65
fi

status="$(cat "$output_file")"
status="${status/voiceShutdownDuringStartHarness/packagedVoiceShutdownDuringStartHarness authoritativeForPackagedApp=true ready=true}"
printf '%s\n' "$status"

if [[ "$status" == *"ready=true"* &&
      "$status" == *"immediateActiveAfterPress=1"* &&
      "$status" == *"immediateDuckedVolume=0.35"* &&
      "$status" == *"immediateStatus=idle"* &&
      "$status" == *"activeAfterShutdown=0"* &&
      "$status" == *"restoredVolume=1.0"* &&
      "$status" == *"status=idle"* &&
      "$status" == *"recorderStarted=true"* &&
      "$status" == *"recorderStopped=true"* &&
      "$status" == *"sttLoadedAfterShutdown=false"* &&
      "$status" == *"insertedText=nil"* &&
      "$status" == *"recordingFileExists=false"* ]]; then
  exit 0
fi

exit 1
