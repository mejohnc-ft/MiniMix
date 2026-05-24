#!/usr/bin/env bash
set -euo pipefail

configuration="release"
check_only=false
wait_for_ready=false
allow_adhoc=false
wait_seconds="${MINIMIX_PERMISSION_WAIT_SECONDS:-60}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"

usage() {
  cat <<'EOF'
Usage:
  scripts/request-packaged-voice-permissions.sh [debug|release] [--check-only] [--wait] [--allow-adhoc]

Builds and opens packaged MiniMix, opens the menu panel, and clicks the
Permissions button so macOS can grant microphone, Speech, and Accessibility
access to the app bundle identity.

This does not record, transcribe, paste, or play audio.

Use --check-only for automation: it verifies the packaged permission status UI
and Permissions button without clicking it.

Use --wait to poll live voice readiness after clicking Permissions. Override the
timeout with MINIMIX_PERMISSION_WAIT_SECONDS.

By default, clicking Permissions is blocked for ad-hoc signed builds because
packaged macOS privacy grants are more repeatable with a stable signing
identity. Use --allow-adhoc only when you intentionally want to grant
permissions to the current ad-hoc build.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    debug|release)
      configuration="$1"
      shift
      ;;
    --check-only)
      check_only=true
      shift
      ;;
    --wait)
      wait_for_ready=true
      shift
      ;;
    --allow-adhoc)
      allow_adhoc=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cleanup() {
  if [[ "$check_only" == true ]]; then
    "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "$repo_root"
"$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
scripts/build-app-bundle.sh "$configuration" >/dev/null

signature="$(codesign -dv "$app" 2>&1 || true)"
signature_summary="$(printf '%s\n' "$signature" | grep -E 'Signature=|Authority=|TeamIdentifier=|CodeDirectory' | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/ $//')"
is_adhoc=false
if [[ "$signature" == *"Signature=adhoc"* || "$signature" == *"TeamIdentifier=not set"* ]]; then
  is_adhoc=true
fi

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

if ! launch_app; then
  echo "voicePermissionRequest=false reason=MiniMix did not launch" >&2
  exit 3
fi

for _ in {1..40}; do
  if osascript -e 'tell application "System Events" to tell process "MiniMix" to exists menu bar item 1 of menu bar 1' 2>/dev/null | grep -q true; then
    break
  fi
  sleep 0.2
done

open_panel() {
  xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.mejohncft.MiniMix.showPanel"), object: nil, userInfo: nil, deliverImmediately: true)' >/dev/null 2>&1
}

window_count() {
  osascript -e 'tell application "System Events" to tell process "MiniMix" to count of windows' 2>/dev/null || echo 0
}

ensure_panel_open() {
  for _ in {1..6}; do
    if [[ "$(window_count)" != "0" ]]; then
      return 0
    fi
    open_panel
    sleep 0.7
  done

  [[ "$(window_count)" != "0" ]]
}

for _ in {1..6}; do
  open_panel
  sleep 0.7
  if [[ "$(window_count)" != "0" ]]; then
    break
  fi
done

ensure_panel_open >/dev/null || true

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

echo "packagedVoicePermissions $status"

if [[ "$status" == *"Voice permissions ready"* ]]; then
  echo "voicePermissionRequest=ready"
  exit 0
fi

if [[ "$status" != *"Permissions"* ]]; then
  echo "voicePermissionRequest=false reason=Permissions button was not visible" >&2
  exit 4
fi

if [[ "$check_only" == true ]]; then
  echo "voicePermissionRequest=checkOnly button=visible"
  exit 0
fi

if [[ "$is_adhoc" == true && "$allow_adhoc" != true ]]; then
  echo "voicePermissionRequest=false reason=ad-hoc signature would make packaged voice permissions unstable" >&2
  echo "codeSignature ${signature_summary:-unavailable}" >&2
  echo "Create/select a stable identity first:" >&2
  echo "  scripts/setup-local-codesign-identity.sh" >&2
  echo "  scripts/setup-local-codesign-identity.sh --install MiniMix\\ Local\\ Code\\ Signing" >&2
  echo "After install, scripts/build-app-bundle.sh auto-selects that identity." >&2
  echo "Override only if intentional:" >&2
  echo "  scripts/request-packaged-voice-permissions.sh $configuration --allow-adhoc" >&2
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
  exit 65
fi

osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
  tell process "MiniMix"
    tell window 1
      click button "Permissions"
    end tell
  end tell
end tell
APPLESCRIPT

cat <<'EOF'
voicePermissionRequest=clicked

Handle the macOS prompts now:
- Allow microphone access when prompted.
- Allow Speech Recognition when prompted.
- For Accessibility, open System Settings if prompted and enable MiniMix.

Then run:
  scripts/probe-live-voice-readiness.sh release
  scripts/probe-live-voice-paste.sh release
EOF

if [[ "$wait_for_ready" == true ]]; then
  echo
  echo "voicePermissionRequest=waiting seconds=$wait_seconds"
  deadline=$((SECONDS + wait_seconds))
  while [[ "$SECONDS" -lt "$deadline" ]]; do
    if scripts/probe-live-voice-readiness.sh "$configuration" >/tmp/minimix-permission-wait.txt 2>&1; then
      cat /tmp/minimix-permission-wait.txt
      echo "voicePermissionRequest=ready"
      exit 0
    fi
    sleep 2
  done

  cat /tmp/minimix-permission-wait.txt 2>/dev/null || true
  echo "voicePermissionRequest=notReadyAfterWait seconds=$wait_seconds" >&2
  exit 66
fi
