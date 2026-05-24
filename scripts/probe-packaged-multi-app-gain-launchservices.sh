#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
first_gain="${2:-0.35}"
second_gain="${3:-0.55}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
sound="$(mktemp -t minimix-packaged-multi-app-gain.XXXXXX).caf"
output_file="$(mktemp -t minimix-ls-multi-app-gain.XXXXXX)"
build_log="$(mktemp -t minimix-ls-multi-app-gain-build.XXXXXX)"

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

for gain in "$first_gain" "$second_gain"; do
  if ! [[ "$gain" =~ ^0([.][0-9]+)?$|^1([.]0+)?$ ]]; then
    echo "gain must be between 0.0 and 1.0" >&2
    exit 2
  fi
done

cd "$repo_root"
scripts/guard-coreaudio-load.sh

MINIMIX_SILENT_SECONDS=3 scripts/ensure-silent-audio-fixture.sh "$sound" >/dev/null

if ! scripts/build-app-bundle.sh "$configuration" >"$build_log" 2>&1; then
  cat "$build_log" >&2
  exit 4
fi

if [[ ! -d "$app" ]]; then
  echo "packagedMultiAppGainHarness ready=false authoritativeForPackagedApp=true reason=missing app bundle" >&2
  exit 3
fi

open -g -W -n "$app" --args \
  --multi-harness \
  --first-gain "$first_gain" \
  --second-gain "$second_gain" \
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
  echo "packagedMultiAppGainHarness ready=false authoritativeForPackagedApp=true reason=no harness output from LaunchServices app run" >&2
  exit 65
fi

status="$(cat "$output_file")"
status="${status/multiHarness/packagedMultiAppGainHarness authoritativeForPackagedApp=true ready=true}"
printf '%s\n' "$status"

if [[ "$status" == *"ready=true"* &&
      "$status" == *"activeAfterApply=2"* &&
      "$status" == *"activeAfterFirstRemove=1"* &&
      "$status" == *"activeAfterSecondRemove=0"* &&
      "$status" == *"tapCount=0"* &&
      "$status" == *"gains=$first_gain,$second_gain"* &&
      "$status" == *"firstTapID="* &&
      "$status" == *"firstAggregateDeviceID="* &&
      "$status" == *"firstActiveGain=$first_gain"* &&
      "$status" == *"secondTapID="* &&
      "$status" == *"secondAggregateDeviceID="* &&
      "$status" == *"secondActiveGain=$second_gain"* &&
      "$status" == *"sessionsAfterFirstRemove=1"* &&
      "$status" == *"sessionsAfterSecondRemove=0"* ]]; then
  exit 0
fi

exit 1
