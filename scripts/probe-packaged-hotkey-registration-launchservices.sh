#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
output_file="$(mktemp -t minimix-ls-hotkey.XXXXXX)"
build_log="$(mktemp -t minimix-ls-hotkey-build.XXXXXX)"

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

if [[ ! -d "$app" ]]; then
  echo "packagedHotkeyHarness ready=false authoritativeForPackagedApp=true reason=missing app bundle" >&2
  exit 3
fi

open -g -W -n "$app" --args \
  --hotkey-harness \
  --launchservices-packaged \
  --harness-output "$output_file" >/dev/null 2>&1 || true

if [[ ! -s "$output_file" ]]; then
  echo "packagedHotkeyHarness ready=false authoritativeForPackagedApp=true reason=no harness output from LaunchServices app run" >&2
  exit 65
fi

status="$(cat "$output_file")"
status="${status/hotkeyHarness/packagedHotkeyHarness authoritativeForPackagedApp=true ready=true}"
printf '%s\n' "$status"

if [[ "$status" == *"ready=true"* &&
      "$status" == *"registered=true"* &&
      "$status" == *"reusableAfterStop=true"* ]]; then
  exit 0
fi

exit 1
