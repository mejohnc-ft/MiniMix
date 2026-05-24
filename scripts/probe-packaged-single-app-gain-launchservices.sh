#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
gain="${2:-0.35}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
sound="$(mktemp -t minimix-packaged-single-app-gain.XXXXXX).caf"
output_file="$(mktemp -t minimix-ls-single-app-gain.XXXXXX)"
build_log="$(mktemp -t minimix-ls-single-app-gain-build.XXXXXX)"

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

if ! [[ "$gain" =~ ^0([.][0-9]+)?$|^1([.]0+)?$ ]]; then
  echo "gain must be between 0.0 and 1.0" >&2
  exit 2
fi

cd "$repo_root"

MINIMIX_SILENT_SECONDS=3 scripts/ensure-silent-audio-fixture.sh "$sound" >/dev/null

if ! scripts/build-app-bundle.sh "$configuration" >"$build_log" 2>&1; then
  cat "$build_log" >&2
  exit 4
fi

if [[ ! -d "$app" ]]; then
  echo "packagedSingleAppGainHarness ready=false authoritativeForPackagedApp=true reason=missing app bundle" >&2
  exit 3
fi

run_harness_once() {
  : >"$output_file"

  open -g -W -n "$app" --args \
    --controller-harness "$gain" \
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
  [[ -s "$output_file" ]]
}

if ! run_harness_once; then
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
  pkill -x afplay >/dev/null 2>&1 || true
  sleep 1
  if ! run_harness_once; then
    echo "packagedSingleAppGainHarness ready=false authoritativeForPackagedApp=true reason=no harness output from LaunchServices app run" >&2
    exit 65
  fi
fi

status="$(cat "$output_file")"
status="${status/controllerHarness/packagedSingleAppGainHarness authoritativeForPackagedApp=true ready=true}"
printf '%s\n' "$status"

if [[ "$status" == *"ready=true"* &&
      "$status" == *"detectedApps=1"* &&
      "$status" == *"activeAfterVolume=1"* &&
      "$status" == *"activeAfterReset=0"* &&
      "$status" == *"tapCount=0"* &&
      "$status" == *"gain=$gain"* &&
      "$status" == *"activeTapID="* &&
      "$status" == *"activeAggregateDeviceID="* &&
      "$status" == *"activeGain=$gain"* &&
      "$status" == *"activeMuted=false"* &&
      "$status" == *"savedRuleVolume=$gain"* &&
      "$status" == *"ruleAfterReset=nil"* &&
      "$status" == *"sessionsAfterReset=0"* ]]; then
  exit 0
fi

exit 1
