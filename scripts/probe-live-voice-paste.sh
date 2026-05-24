#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
duration="${MINIMIX_LIVE_VOICE_SECONDS:-5}"
trigger="${MINIMIX_LIVE_VOICE_TRIGGER:-automation}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
status_file="$(mktemp -t minimix-live-voice-status.XXXXXX)"
automation_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"

usage() {
  cat <<'EOF'
Usage:
  scripts/probe-live-voice-paste.sh [debug|release]

Live packaged-app voice proof. This does not play audio. It requires MiniMix
packaged-app mic, Speech, and Accessibility permissions to already be granted.

The script opens TextEdit, focuses a blank document, records for
MINIMIX_LIVE_VOICE_SECONDS seconds (default 5), and verifies that recognized
text was pasted into TextEdit.

By default the script starts/stops dictation through MiniMix automation URL
events without opening the panel or synthesizing the global hotkey. Set
MINIMIX_LIVE_VOICE_TRIGGER=hotkey to prove the push-to-talk hotkey path, or
MINIMIX_LIVE_VOICE_TRIGGER=ui only when you specifically need to test the panel
path.

Speak a short phrase while the script is recording.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  echo "configuration must be debug or release" >&2
  exit 2
fi

if ! [[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "MINIMIX_LIVE_VOICE_SECONDS must be a positive number" >&2
  exit 2
fi

if [[ "$trigger" == "notification" ]]; then
  trigger="automation"
fi

if [[ "$trigger" != "hotkey" && "$trigger" != "automation" && "$trigger" != "ui" ]]; then
  echo "MINIMIX_LIVE_VOICE_TRIGGER must be automation, hotkey, or ui" >&2
  exit 2
fi

cleanup() {
  rm -f "$status_file"
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$repo_root"

scripts/build-app-bundle.sh "$configuration" >/dev/null

if ! scripts/probe-live-voice-readiness.sh "$configuration" >/tmp/minimix-live-voice-readiness.txt 2>&1; then
  cat /tmp/minimix-live-voice-readiness.txt
  echo "liveVoicePaste=false reason=packaged voice permissions are not ready" >&2
  exit 66
fi

cleanup
open -g "$app" --args --automation-token "$automation_token"
for _ in {1..40}; do
  pgrep -x MiniMix >/dev/null && break
  sleep 0.2
done

if ! pgrep -x MiniMix >/dev/null; then
  echo "liveVoicePaste=false reason=MiniMix did not launch" >&2
  exit 3
fi

open_panel() {
  open -g "minimix://show-panel" >/dev/null 2>&1
}

post_automation_event() {
  local name="$1"
  local path="${2:-}"
  local host=""
  case "$name" in
    com.mejohncft.MiniMix.startDictation)
      host="start-dictation"
      ;;
    com.mejohncft.MiniMix.stopDictation)
      host="stop-dictation"
      ;;
    com.mejohncft.MiniMix.writeAutomationStatus)
      host="automation-status"
      ;;
    *)
      echo "Unknown MiniMix automation event: $name" >&2
      return 2
      ;;
  esac

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
  post_automation_event "com.mejohncft.MiniMix.writeAutomationStatus" "$status_file"
  for _ in {1..20}; do
    if [[ -s "$status_file" ]]; then
      cat "$status_file"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_status() {
  local expected="$1"
  local timeout_seconds="$2"
  local label="$3"
  local deadline=$((SECONDS + timeout_seconds))
  local status=""

  while [[ "$SECONDS" -le "$deadline" ]]; do
    status="$(request_status 2>/dev/null || true)"
    if [[ "$status" == *"$expected"* ]]; then
      printf '%s\n' "$status"
      return 0
    fi
    if [[ "$status" == *"errorPresent=true"* && "$expected" != "voiceStatus=idle" ]]; then
      echo "liveVoicePaste=false reason=MiniMix reported voice error during $label status=${status}" >&2
      return 2
    fi
    sleep 0.25
  done

  echo "liveVoicePaste=false reason=MiniMix did not reach $expected during $label lastStatus=${status:-missing}" >&2
  return 1
}

window_count() {
  osascript -e 'tell application "System Events" to tell process "MiniMix" to count of windows' 2>/dev/null || echo 0
}

ensure_panel_open() {
  for _ in {1..8}; do
    if [[ "$(window_count)" != "0" ]]; then
      return 0
    fi
    open_panel
    sleep 0.5
  done

  [[ "$(window_count)" != "0" ]]
}

osascript <<'APPLESCRIPT'
tell application "TextEdit"
  activate
  make new document with properties {text:""}
end tell
APPLESCRIPT

sleep 1

before="$(osascript <<'APPLESCRIPT'
tell application "TextEdit"
  if (count of documents) = 0 then return ""
  return text of document 1
end tell
APPLESCRIPT
)"

echo "liveVoicePaste=recording duration=${duration}s trigger=${trigger} prompt='speak now'"

if [[ "$trigger" == "hotkey" ]]; then
  swift - "$duration" <<'SWIFT'
import CoreGraphics
import Foundation

let duration = Double(CommandLine.arguments.dropFirst().first ?? "5") ?? 5
let source = CGEventSource(stateID: .hidSystemState)
let keyCode: CGKeyCode = 49 // Space
let flags: CGEventFlags = [.maskControl, .maskAlternate]

let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
down?.flags = flags
down?.post(tap: .cghidEventTap)

Thread.sleep(forTimeInterval: duration)

let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
up?.flags = flags
up?.post(tap: .cghidEventTap)
SWIFT
elif [[ "$trigger" == "automation" ]]; then
  status_before="$(request_status 2>/dev/null || true)"
  [[ -z "$status_before" ]] || echo "liveVoicePaste=statusBefore ${status_before}"

  post_automation_event "com.mejohncft.MiniMix.startDictation"
  start_status="$(wait_for_status "voiceStatus=recording" 8 "start")" || exit $?
  echo "liveVoicePaste=statusAfterStart ${start_status}"

  sleep "$duration"

  post_automation_event "com.mejohncft.MiniMix.stopDictation"
  stop_status="$(wait_for_status "voiceStatus=idle" 30 "stop")" || exit $?
  echo "liveVoicePaste=statusAfterStop ${stop_status}"
else
  ensure_panel_open || {
    echo "liveVoicePaste=false reason=MiniMix panel did not open for UI trigger" >&2
    exit 5
  }

  osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
  tell process "MiniMix"
    tell window 1
      click button "Start"
    end tell
  end tell
end tell
APPLESCRIPT

  sleep "$duration"

  osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
  tell process "MiniMix"
    tell window 1
      click button "Stop"
    end tell
  end tell
end tell
APPLESCRIPT
fi

for _ in {1..30}; do
  sleep 1
  after="$(osascript <<'APPLESCRIPT'
tell application "TextEdit"
  if (count of documents) = 0 then return ""
  return text of document 1
end tell
APPLESCRIPT
)"
  if [[ "$after" != "$before" && -n "${after//$'\n'/}" ]]; then
    compact="$(printf '%s' "$after" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    echo "liveVoicePaste=true text=${compact}"
    exit 0
  fi
done

echo "liveVoicePaste=false reason=no transcribed text was pasted into TextEdit" >&2
exit 4
