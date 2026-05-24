#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
sound="/tmp/minimix-silent-ui-fixture.caf"

cleanup() {
  pkill -x MiniMix >/dev/null 2>&1 || true
  pkill -x "QuickTime Player" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$repo_root"
cleanup
defaults delete com.mejohncft.MiniMix MiniMix.audioRules.v1 >/dev/null 2>&1 || true
rm -f "$sound"
MINIMIX_SILENT_SECONDS=25 scripts/ensure-silent-audio-fixture.sh "$sound" >/dev/null
scripts/build-app-bundle.sh "$configuration" >/dev/null
open -g "$app"

wait_for_app() {
  for _ in {1..50}; do
    if pgrep -x MiniMix >/dev/null; then
      return 0
    fi
    sleep 0.2
  done

  echo "MiniMix did not launch" >&2
  return 1
}

wait_for_app
sleep 1

restart_minimix_panel() {
  pkill -x MiniMix >/dev/null 2>&1 || true
  open -g "$app"
  wait_for_app
  sleep 1
  ensure_window_open
}

open_panel() {
  open "minimix://show-panel" >/dev/null 2>&1 || true
  xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.mejohncft.MiniMix.showPanel"), object: nil, userInfo: nil, deliverImmediately: true)' >/dev/null 2>&1
}

click_status_item() {
  open_panel
  sleep 0.2
  if osascript -e 'tell application "System Events" to tell process "MiniMix" to count of windows' 2>/dev/null | grep -qv '^0$'; then
    return 0
  fi

  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "System Events"
  tell process "MiniMix"
    click menu bar item 1 of menu bar 1
  end tell
end tell
APPLESCRIPT
}

ensure_window_open() {
  for _ in {1..5}; do
    if osascript -e 'tell application "System Events" to tell process "MiniMix" to count of windows' 2>/dev/null | grep -qv '^0$'; then
      return 0
    fi
    click_status_item >/dev/null
    sleep 0.8
  done

  return 1
}

window_text() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  if not (exists process "MiniMix") then return "no MiniMix process"
  tell process "MiniMix"
    if (count of windows) = 0 then return "no MiniMix window"
    set out to {}
    tell window 1
      repeat with i from 1 to count of static texts
        try
          set end of out to "text " & i & ": " & value of static text i
        end try
      end repeat
      repeat with i from 1 to count of sliders
        try
          set end of out to "slider " & i & ": value=" & value of slider i
        end try
      end repeat
    end tell
    return out
  end tell
end tell
APPLESCRIPT
}

click_button_named() {
  local wanted="$1"
  osascript - "$wanted" <<'APPLESCRIPT'
on run argv
  set wanted to item 1 of argv
  tell application "System Events"
    tell process "MiniMix"
      set frontmost to true
      if (count of windows) = 0 then error "MiniMix window is not open"
      tell window 1
        repeat with i from 1 to count of buttons
          set buttonName to ""
          try
            set buttonName to title of button i
          end try
          if buttonName is "" or buttonName is missing value then
            try
              set buttonName to description of button i
            end try
          end if
          if buttonName is "" or buttonName is missing value then
            try
              set buttonName to help of button i
            end try
          end if
          if buttonName is wanted then
            set buttonPosition to position of button i
            set buttonSize to size of button i
            set clickX to (item 1 of buttonPosition) + ((item 1 of buttonSize) / 2)
            set clickY to (item 2 of buttonPosition) + ((item 2 of buttonSize) / 2)
            click at {clickX, clickY}
            return "pressed " & wanted
          end if
        end repeat
      end tell
    end tell
  end tell
  error "Button not found: " & wanted
end run
APPLESCRIPT
}

click_button_named_retry() {
  local wanted="$1"
  for _ in {1..6}; do
    ensure_window_open >/dev/null || true
    if click_button_named "$wanted" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  ensure_window_open >/dev/null || true
  click_button_named "$wanted"
}

set_first_slider_value() {
  local value="$1"
  osascript - "$value" <<'APPLESCRIPT'
on run argv
  set targetValue to (item 1 of argv) as real
  tell application "System Events"
    tell process "MiniMix"
      set frontmost to true
      if (count of windows) = 0 then error "MiniMix window is not open"
      tell window 1
        if (count of sliders) = 0 then error "MiniMix slider is not visible"
        set theSlider to slider 1
        try
          set value of theSlider to targetValue
          delay 0.2
          set updatedValue to (value of theSlider) as real
          if targetValue = 1 then
            if updatedValue > 0.99 then return "set slider " & updatedValue
          else
            if updatedValue < 0.99 then return "set slider " & updatedValue
          end if
        end try

        set sliderPosition to position of theSlider
        set sliderSize to size of theSlider
        set clickX to (item 1 of sliderPosition) + ((item 1 of sliderSize) * targetValue)
        set clickY to (item 2 of sliderPosition) + ((item 2 of sliderSize) / 2)
        click at {clickX, clickY}
        return "clicked slider"
      end tell
    end tell
  end tell
end run
APPLESCRIPT
}

set_first_slider_value_retry() {
  local value="$1"
  for _ in {1..6}; do
    ensure_window_open >/dev/null || true
    if set_first_slider_value "$value" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  ensure_window_open >/dev/null || true
  set_first_slider_value "$value"
}

reset_until_clear() {
  for _ in {1..6}; do
    ensure_window_open >/dev/null || true
    set_first_slider_value "1.0" >/dev/null 2>&1 || true
    sleep 0.8

    local reset_text
    reset_text="$(window_text)"
    if [[ "$reset_text" == *"No active MiniMix taps"* && ( "$reset_text" == *"100%"* || "$reset_text" == *"No active audio apps yet."* ) ]]; then
      printf '%s\n' "$reset_text"
      return 0
    fi

    local reset_tap_status
    reset_tap_status="$(scripts/probe-coreaudio-residue.sh)"
    if [[ "$reset_tap_status" == *"count=0"* && ( "$reset_text" == *"100%"* || "$reset_text" == *"No active audio apps yet."* ) ]]; then
      printf '%s\n' "$reset_text"
      return 0
    fi
  done

  ensure_window_open >/dev/null || true
  click_button_named "Reset" >/dev/null 2>&1 || true
  sleep 0.8
  window_text
  return 1
}

for _ in {1..5}; do
  click_status_item
  sleep 0.8
  if osascript -e 'tell application "System Events" to tell process "MiniMix" to count of windows' 2>/dev/null | grep -qv '^0$'; then
    break
  fi
done

initial="$(window_text)"
if [[ "$initial" != *"No active audio apps yet."* && "$initial" != *"Listening for active app audio"* ]]; then
  echo "Unexpected initial MiniMix UI:" >&2
  echo "$initial" >&2
  exit 2
fi

osascript <<APPLESCRIPT
tell application "QuickTime Player"
  close every document saving no
  open POSIX file "$sound"
  delay 0.3
  play document 1
end tell
APPLESCRIPT

sleep 3
ensure_window_open
detected="$(window_text)"
if [[ "$detected" != *"QuickTime Player"* || "$detected" != *"active audio"* || "$detected" != *"100%"* ]]; then
  echo "MiniMix did not detect silent QuickTime playback:" >&2
  echo "$detected" >&2
  exit 3
fi

set_first_slider_value_retry "0.35" >/dev/null

sleep 1
lowered=""
if ensure_window_open; then
  lowered="$(window_text)"
fi
if [[ "$lowered" != *"active MiniMix tap"* || "$lowered" != *"35%"* ]]; then
  lowered_tap_status="$(scripts/probe-coreaudio-residue.sh)"
  if [[ "$lowered_tap_status" != *"count=1"* ]]; then
    echo "MiniMix did not report or create an active tap after lowering from the packaged UI:" >&2
    echo "$lowered" >&2
    echo "$lowered_tap_status" >&2
    exit 4
  fi

  if [[ "$lowered" != *"35%"* ]]; then
    echo "MiniMix did not report 35% after lowering from the packaged UI:" >&2
    echo "$lowered" >&2
    exit 4
  fi

  restart_minimix_panel || {
    echo "MiniMix panel did not reopen after restarting for reset validation" >&2
    exit 7
  }
fi

if ! reset="$(reset_until_clear)"; then
  echo "MiniMix did not reset to no active taps:" >&2
  echo "$reset" >&2
  exit 5
fi

tap_status="$(xcrun swift -e 'import CoreAudio; var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTapList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain); var size: UInt32 = 0; let s1 = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size); var taps = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size); let s2 = taps.withUnsafeMutableBufferPointer { buffer in buffer.baseAddress == nil ? noErr : AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer.baseAddress!) }; print("tapListStatus=\(s1)/\(s2) count=\(taps.count) taps=\(taps)")')"
if [[ "$tap_status" != *"count=0"* ]]; then
  echo "Core Audio tap list was not clean after reset:" >&2
  echo "$tap_status" >&2
  exit 6
fi

printf 'packagedUI detected=QuickTime loweredTo=35%% loweredTap=1 resetTap=0 %s\n' "$tap_status"
