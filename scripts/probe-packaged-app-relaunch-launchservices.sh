#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
output_file="$(mktemp -t minimix-ls-app-relaunch.XXXXXX)"
build_log="$(mktemp -t minimix-ls-app-relaunch-build.XXXXXX)"

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
  echo "packagedRelaunchHarness ready=false authoritativeForPackagedApp=true reason=missing app bundle" >&2
  exit 3
fi

open -g -W -n "$app" --args \
  --relaunch-harness \
  --launchservices-packaged \
  --harness-output "$output_file" >/dev/null 2>&1 || true

if [[ ! -s "$output_file" ]]; then
  echo "packagedRelaunchHarness ready=false authoritativeForPackagedApp=true reason=no harness output from LaunchServices app run" >&2
  exit 65
fi

status="$(cat "$output_file")"
status="${status/relaunchHarness/packagedRelaunchHarness authoritativeForPackagedApp=true ready=true}"
printf '%s\n' "$status"

if [[ "$status" == *"ready=true"* &&
      "$status" == *"oldSessionApplied=true"* &&
      "$status" == *"disappearedRemovedSession=true"* &&
      "$status" == *"relaunchedRuleVisible=true"* &&
      "$status" == *"relaunchedSessionApplied=true"* &&
      "$status" == *"resetRemovedSession=true"* &&
      "$status" == *"resetRemovedRule=true"* ]]; then
  exit 0
fi

exit 1
