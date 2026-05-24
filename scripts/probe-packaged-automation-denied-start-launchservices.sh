#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
sound="$(mktemp -t minimix-automation-denied-start.XXXXXX).caf"
status_file="$(mktemp -t minimix-automation-denied-status.XXXXXX)"
build_log="$(mktemp -t minimix-automation-denied-build.XXXXXX)"
automation_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"

cleanup() {
  rm -f "$sound" "$status_file" "$build_log"
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
  pkill -x afplay >/dev/null 2>&1 || true
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

if [[ "$permissions_status" -eq 0 ]]; then
  echo "packagedAutomationDeniedStart ready=false reason=voice permissions already ready; denied-start proof not applicable"
  exit 66
fi

if [[ "$permissions" == *"Mic Authorized"* ]]; then
  echo "packagedAutomationDeniedStart ready=false reason=packaged microphone is already authorized; denied-start proof would record"
  exit 66
fi

"$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
pkill -x afplay >/dev/null 2>&1 || true
MINIMIX_SILENT_SECONDS=4 scripts/ensure-silent-audio-fixture.sh "$sound" >/dev/null
afplay "$sound" >/dev/null 2>&1 &
player_pid=$!

open -g -n "$app" --args --automation-token "$automation_token"
for _ in {1..40}; do
  pgrep -x MiniMix >/dev/null && break
  sleep 0.2
done

if ! pgrep -x MiniMix >/dev/null; then
  echo "packagedAutomationDeniedStart ready=false reason=MiniMix did not launch" >&2
  exit 5
fi

post_event() {
  local host="$1"
  local path="${2:-}"
  local url
  url="$(xcrun swift - "$host" "$path" "$automation_token" <<'SWIFT'
import Foundation

let host = CommandLine.arguments[1]
let path = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let token = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
var components = URLComponents()
components.scheme = "minimix"
components.host = host
var queryItems = [URLQueryItem(name: "token", value: token)]
if !path.isEmpty {
    queryItems.append(URLQueryItem(name: "path", value: path))
}
components.queryItems = queryItems
print(components.url!.absoluteString)
SWIFT
)"
  open -g "$url" >/dev/null 2>&1
}

request_status() {
  : >"$status_file"
  post_event "automation-status" "$status_file"
  for _ in {1..30}; do
    if [[ -s "$status_file" ]]; then
      tr '\n' ' ' <"$status_file" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
      return 0
    fi
    sleep 0.1
  done
  return 1
}

post_event "start-dictation"

deadline=$((SECONDS + 10))
status=""
while [[ "$SECONDS" -le "$deadline" ]]; do
  status="$(request_status 2>/dev/null || true)"
  if [[ "$status" == *"voiceStatus=idle"* && "$status" == *"errorPresent=true"* ]]; then
    break
  fi
  sleep 0.25
done

pkill -x afplay >/dev/null 2>&1 || true
wait "$player_pid" >/dev/null 2>&1 || true

residue="$(scripts/probe-coreaudio-residue.sh)"
printf '%s\n' "$residue"

if [[ "$status" == *"voiceStatus=idle"* &&
      "$status" == *"voiceActive=false"* &&
      "$status" == *"activeAudioSessionCount=0"* &&
      "$status" == *"errorPresent=true"* &&
      "$residue" == *"count=0"* &&
      "$residue" == *"minimixDeviceCount=0"* ]]; then
  echo "packagedAutomationDeniedStart ready=true authoritativeForPackagedApp=true ${status}"
  exit 0
fi

echo "packagedAutomationDeniedStart ready=false reason=unexpected status status=${status:-missing}" >&2
exit 65
