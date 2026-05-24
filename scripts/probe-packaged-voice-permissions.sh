#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"

cleanup() {
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$repo_root"
cleanup
scripts/build-app-bundle.sh "$configuration" >/dev/null

launch_app() {
  for _ in {1..3}; do
    open -g "$app" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      if pgrep -x MiniMix >/dev/null; then
        return 0
      fi
      sleep 0.2
    done
  done
  return 1
}

launch_app || {
  echo "MiniMix did not launch" >&2
  exit 4
}

for _ in {1..30}; do
  if osascript -e 'tell application "System Events" to tell process "MiniMix" to exists menu bar item 1 of menu bar 1' 2>/dev/null | grep -q true; then
    break
  fi
  sleep 0.2
done
sleep 1

click_status_item() {
  xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.mejohncft.MiniMix.showPanel"), object: nil, userInfo: nil, deliverImmediately: true)' >/dev/null 2>&1
}

for _ in {1..5}; do
  click_status_item >/dev/null
  sleep 0.8
  if osascript -e 'tell application "System Events" to tell process "MiniMix" to count of windows' 2>/dev/null | grep -qv '^0$'; then
    break
  fi
done


status="$(osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "MiniMix"
    if (count of windows) = 0 then return "no MiniMix window"
    set out to {}
    tell window 1
      repeat with i from 1 to count of static texts
        try
          set end of out to value of static text i
        end try
      end repeat
      repeat with i from 1 to count of buttons
        try
          set buttonTitle to title of button i
          if buttonTitle is not missing value and buttonTitle is not "" then
            set end of out to buttonTitle
          end if
        end try
      end repeat
    end tell
    return out
  end tell
end tell
APPLESCRIPT
)"

if [[ "$status" != *"Voice Input"* || "$status" != *"Hold Control-Option-Space"* || "$status" != *"Mic "* || "$status" != *"Speech "* || "$status" != *"Accessibility "* ]]; then
  echo "MiniMix packaged voice permission status was not visible:" >&2
  echo "$status" >&2
  exit 2
fi

if [[ "$status" == *"Needs:"* && "$status" != *"Permissions"* ]]; then
  echo "MiniMix packaged voice permission request button was not visible:" >&2
  echo "$status" >&2
  exit 3
fi

printf 'packagedVoicePermissions %s\n' "$status"
