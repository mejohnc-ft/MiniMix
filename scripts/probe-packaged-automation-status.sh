#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
status_file="$(mktemp -t minimix-automation-status.XXXXXX)"
build_log="$(mktemp -t minimix-automation-status-build.XXXXXX)"
automation_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"

cleanup() {
  rm -f "$status_file" "$build_log"
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
  echo "packagedAutomationStatus ready=false reason=missing app bundle" >&2
  exit 3
fi

cleanup
for _ in {1..30}; do
  if ! pgrep -x MiniMix >/dev/null; then
    break
  fi
  sleep 0.1
done

if pgrep -x MiniMix >/dev/null; then
  echo "packagedAutomationStatus ready=false reason=MiniMix did not quit before probe launch" >&2
  exit 8
fi

open -g -n "$app" --args --automation-token "$automation_token"

for _ in {1..40}; do
  pgrep -x MiniMix >/dev/null && break
  sleep 0.2
done

if ! pgrep -x MiniMix >/dev/null; then
  echo "packagedAutomationStatus ready=false reason=MiniMix did not launch" >&2
  exit 5
fi

unauthorized_file="$(mktemp -t minimix-automation-status-unauthorized.XXXXXX)"
trap 'rm -f "$status_file" "$build_log" "$unauthorized_file"; "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true' EXIT
: >"$unauthorized_file"
unauthorized_url="$(xcrun swift - "$unauthorized_file" <<'SWIFT'
import Foundation

let path = CommandLine.arguments[1]
var components = URLComponents()
components.scheme = "minimix"
components.host = "automation-status"
components.queryItems = [URLQueryItem(name: "path", value: path)]
print(components.url!.absoluteString)
SWIFT
)"
open -g "$unauthorized_url" >/dev/null 2>&1
sleep 0.6
if [[ -s "$unauthorized_file" ]]; then
  status="$(cat "$unauthorized_file" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
  echo "packagedAutomationStatus ready=false reason=unauthorized status URL wrote output status=${status}" >&2
  exit 7
fi

: >"$status_file"
status_url="$(xcrun swift - "$status_file" "$automation_token" <<'SWIFT'
import Foundation

let path = CommandLine.arguments[1]
let token = CommandLine.arguments[2]
var components = URLComponents()
components.scheme = "minimix"
components.host = "automation-status"
components.queryItems = [
    URLQueryItem(name: "path", value: path),
    URLQueryItem(name: "token", value: token)
]
print(components.url!.absoluteString)
SWIFT
)"

for attempt in {1..40}; do
  open -g "$status_url" >/dev/null 2>&1
  sleep 0.2
  if [[ -s "$status_file" ]]; then
    status="$(cat "$status_file" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    if [[ "$status" == miniMixAutomationStatus* ]]; then
      echo "packagedAutomationStatus ready=true unauthorizedIgnored=true tokenRequired=true ${status}"
      exit 0
    fi
    echo "packagedAutomationStatus ready=false reason=unexpected status=${status}" >&2
    exit 6
  fi
done

echo "packagedAutomationStatus ready=false reason=no status response" >&2
exit 65
