#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
output_file="$(mktemp -t minimix-ls-mic-denied.XXXXXX)"
build_log="$(mktemp -t minimix-ls-mic-denied-build.XXXXXX)"

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

permissions_status=0
permissions="$(scripts/probe-packaged-voice-permissions-launchservices.sh "$configuration" 2>&1)" || permissions_status=$?
printf '%s\n' "$permissions"

if [[ "$permissions_status" -eq 0 || "$permissions" == *"Mic Authorized"* ]]; then
  echo "packagedVoiceMicDeniedHarness ready=false authoritativeForPackagedApp=true reason=packaged microphone is already authorized; denied proof not applicable"
  exit 66
fi

open -g -W -n "$app" --args \
  --voice-mic-denied-harness \
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
  echo "packagedVoiceMicDeniedHarness ready=false authoritativeForPackagedApp=true reason=no harness output from LaunchServices app run" >&2
  exit 65
fi

status="$(cat "$output_file")"
status="${status/voiceMicDeniedHarness/packagedVoiceMicDeniedHarness authoritativeForPackagedApp=true ready=true}"
printf '%s\n' "$status"

if [[ "$status" == *"ready=true"* &&
      "$status" == *"immediateActiveAfterPress=1"* &&
      "$status" == *"immediateDuckedVolume=0.35"* &&
      "$status" == *"activeAfterFailure=0"* &&
      "$status" == *"restoredVolume=1.0"* &&
      "$status" == *"status=idle"* &&
      "$status" == *"insertedText=nil"* &&
      "$status" == *"sttLoadedAfterFailure=false"* &&
      "$status" == *"error=Microphone permission is required."* &&
      "$status" == *"tapCount=0"* ]]; then
  exit 0
fi

exit 1
