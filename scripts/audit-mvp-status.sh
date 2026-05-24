#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="debug"
run_full=false

usage() {
  cat <<'EOF'
Usage:
  scripts/audit-mvp-status.sh [--configuration debug|release] [--full]

Default mode is non-audible and conservative: it builds MiniMix, packages the
app, verifies static app/package properties, inspects current cleanup state, and
reports benchmark/voice-readiness evidence.

--full also runs scripts/validate-noninteractive-mvp.sh. Packaged panel UI
automation is skipped unless MINIMIX_RUN_UI_PROBES=1 is set.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    --full)
      run_full=true
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

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  echo "configuration must be debug or release" >&2
  exit 2
fi

cd "$repo_root"

if [[ "$run_full" == true ]]; then
  scripts/guard-coreaudio-load.sh
fi

cleanup() {
  "$repo_root/scripts/quit-minimix.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

passes=0
warnings=0
failures=0

pass() {
  printf 'PASS %-34s %s\n' "$1" "${2:-}"
  passes=$((passes + 1))
}

warn() {
  printf 'WARN %-34s %s\n' "$1" "${2:-}"
  warnings=$((warnings + 1))
}

fail() {
  printf 'FAIL %-34s %s\n' "$1" "${2:-}"
  failures=$((failures + 1))
}

check_command() {
  local label="$1"
  shift

  local output
  if output="$("$@" 2>&1)"; then
    pass "$label"
    [[ -z "$output" ]] || printf '%s\n' "$output" | sed 's/^/  /'
  else
    fail "$label"
    [[ -z "$output" ]] || printf '%s\n' "$output" | sed 's/^/  /'
  fi
}

echo "MiniMix MVP audit"
echo "configuration=$configuration full=$run_full"
echo

check_command "swift build" swift build
check_command "build app bundle" scripts/build-app-bundle.sh "$configuration"

app="build/MiniMix.app"
executable="$app/Contents/MacOS/MiniMix"
info_plist="$app/Contents/Info.plist"

if [[ -x "$executable" ]]; then
  pass "packaged executable" "$executable"
else
  fail "packaged executable" "$executable missing or not executable"
fi

signature="$(codesign -dv "$app" 2>&1 || true)"
if [[ "$signature" == *"Signature="* || "$signature" == *"Authority="* ]]; then
  signature_summary="$(printf '%s\n' "$signature" | grep -E 'Signature=|Authority=|TeamIdentifier=|CodeDirectory' | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/ $//')"
  pass "code signature" "$signature_summary"
  if [[ "$signature" == *"Signature=adhoc"* || "$signature" == *"TeamIdentifier=not set"* ]]; then
    warn "privacy-stable code signature" "ad-hoc signature; set MINIMIX_CODESIGN_IDENTITY to a stable Apple Development identity before granting packaged voice permissions"
  else
    pass "privacy-stable code signature" "$signature_summary"
  fi
else
  fail "code signature" "codesign metadata unavailable"
fi

if [[ -f "$info_plist" ]]; then
  bundle_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_plist" 2>/dev/null || true)"
  display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist" 2>/dev/null || true)"
  bundle_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist" 2>/dev/null || true)"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
  package_type="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$info_plist" 2>/dev/null || true)"
  lsui="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$info_plist" 2>/dev/null || true)"
  url_scheme="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$info_plist" 2>/dev/null || true)"
  audio_usage="$(/usr/libexec/PlistBuddy -c 'Print :NSAudioCaptureUsageDescription' "$info_plist" 2>/dev/null || true)"
  mic_usage="$(/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$info_plist" 2>/dev/null || true)"
  speech_usage="$(/usr/libexec/PlistBuddy -c 'Print :NSSpeechRecognitionUsageDescription' "$info_plist" 2>/dev/null || true)"
  accessibility_usage="$(/usr/libexec/PlistBuddy -c 'Print :NSAccessibilityUsageDescription' "$info_plist" 2>/dev/null || true)"
  apple_events_usage="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$info_plist" 2>/dev/null || true)"

  [[ "$bundle_name" == "MiniMix" && "$display_name" == "MiniMix" ]] && pass "app name metadata" "CFBundleName=$bundle_name CFBundleDisplayName=$display_name" || fail "app name metadata" "CFBundleName=${bundle_name:-missing} CFBundleDisplayName=${display_name:-missing}"
  [[ "$bundle_executable" == "MiniMix" ]] && pass "bundle executable" "$bundle_executable" || fail "bundle executable" "${bundle_executable:-missing}"
  [[ "$bundle_id" == "com.mejohncft.MiniMix" ]] && pass "bundle identifier" "$bundle_id" || fail "bundle identifier" "${bundle_id:-missing}"
  [[ "$package_type" == "APPL" ]] && pass "bundle package type" "$package_type" || fail "bundle package type" "${package_type:-missing}"
  [[ "$lsui" == "true" || "$lsui" == "1" ]] && pass "menubar-only plist" "LSUIElement=$lsui" || fail "menubar-only plist" "LSUIElement=${lsui:-missing}"
  [[ "$url_scheme" == "minimix" ]] && pass "automation URL scheme" "$url_scheme" || fail "automation URL scheme" "${url_scheme:-missing}"
  [[ -n "$audio_usage" ]] && pass "audio capture usage string" || fail "audio capture usage string" "missing"
  [[ -n "$mic_usage" ]] && pass "mic usage string" || fail "mic usage string" "missing"
  [[ -n "$speech_usage" ]] && pass "speech usage string" || fail "speech usage string" "missing"
  [[ -n "$accessibility_usage" ]] && pass "accessibility usage string" || fail "accessibility usage string" "missing"
  [[ -n "$apple_events_usage" ]] && pass "apple events usage string" || fail "apple events usage string" "missing"
else
  fail "info plist" "$info_plist missing"
fi

codesign_readiness_status=0
codesign_readiness="$(scripts/probe-codesign-readiness.sh 2>&1)" || codesign_readiness_status=$?
if [[ "$codesign_readiness_status" -eq 0 ]]; then
  pass "local signing readiness" "$codesign_readiness"
elif [[ "$codesign_readiness_status" -eq 66 ]]; then
  warn "local signing readiness" "$codesign_readiness"
else
  fail "local signing readiness" "$codesign_readiness"
fi

runtime_permission_requests="$(
  rg -n 'requestAccess|requestAuthorization|AXTrustedCheckOptionPrompt": true' \
    Sources/MiniMix/Voice/AppleSpeechSTTEngine.swift \
    Sources/MiniMix/Voice/MicrophoneRecorder.swift \
    Sources/MiniMix/Voice/TextInjector.swift || true
)"
if [[ -z "$runtime_permission_requests" ]]; then
  pass "passive voice runtime permissions" "runtime record/transcribe/paste paths do not request TCC prompts"
else
  fail "passive voice runtime permissions" "$(printf '%s' "$runtime_permission_requests" | tr '\n' '; ' | sed 's/[[:space:]][[:space:]]*/ /g; s/[;[:space:]]*$//')"
fi

if find /Library/Audio/Plug-Ins/HAL -maxdepth 3 -iname '*MiniMix*' -print 2>/dev/null | grep -q .; then
  fail "no MiniMix HAL driver" "MiniMix driver found"
else
  pass "no MiniMix HAL driver"
fi

if find "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons -maxdepth 1 -iname '*MiniMix*' -print 2>/dev/null | grep -q .; then
  fail "no MiniMix launch agents" "MiniMix launch item found"
else
  pass "no MiniMix launch agents"
fi

residue="$(scripts/probe-coreaudio-residue.sh || true)"
tap_line="$(printf '%s\n' "$residue" | grep '^tapListStatus=' || true)"
device_line="$(printf '%s\n' "$residue" | grep '^audioDeviceStatus=' || true)"

if [[ "$tap_line" == *"count=0"* ]]; then
  pass "current tap cleanup" "$tap_line"
else
  fail "current tap cleanup" "${tap_line:-missing tap status}"
fi

if [[ "$device_line" == *"minimixDeviceCount=0"* ]]; then
  pass "current aggregate cleanup" "$device_line"
else
  fail "current aggregate cleanup" "${device_line:-missing audio device status}"
fi

if pmset -g assertions | grep -Eiq 'MiniMix'; then
  fail "no MiniMix sleep assertion" "MiniMix assertion present"
else
  pass "no MiniMix sleep assertion"
fi

cleanup

launch_app_for_check() {
  open -g "$app" >/dev/null 2>&1 || (
    "$executable" >/tmp/minimix-audit-idle.log 2>&1 &
  )
}

launch_app_for_check
pid=""
for _ in {1..30}; do
  pid="$(pgrep -x MiniMix | head -n 1 || true)"
  [[ -n "$pid" ]] && break
  sleep 0.2
done

if [[ -z "$pid" ]]; then
  fail "idle footprint" "MiniMix did not launch"
else
  footprint=""
  cpu=""
  rss_kb=""
  stat=""
  sleep 2
  for _ in {1..24}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      pid="$(pgrep -x MiniMix | head -n 1 || true)"
      [[ -n "$pid" ]] || break
    fi

    footprint="$(ps -o stat=,%cpu=,rss= -p "$pid" 2>/dev/null | awk 'NF >= 3 && $1 !~ /Z/ { print $1, $2, $3; exit }' || true)"
    stat="$(awk '{print $1}' <<< "$footprint")"
    cpu="$(awk '{print $2}' <<< "$footprint")"
    rss_kb="$(awk '{print $3}' <<< "$footprint")"
    if [[ -n "$cpu" && -n "$rss_kb" && "$rss_kb" -gt 1024 ]] && awk "BEGIN { exit !($cpu <= 1.0) }"; then
      break
    fi
    sleep 0.5
  done

  limit_kb=92160
  if [[ "$configuration" == "release" ]]; then
    limit_kb=51200
  fi

  if [[ -z "$cpu" || -z "$rss_kb" || "$rss_kb" -le 1024 ]]; then
    fail "idle footprint" "could not read stable process footprint pid=${pid:-missing} stat=${stat:-missing} cpu=${cpu:-missing} rss=${rss_kb:-missing}KB"
elif awk "BEGIN { exit !($cpu <= 1.0) }" && [[ "$rss_kb" -le "$limit_kb" ]]; then
    pass "idle footprint" "cpu=${cpu}% rss=${rss_kb}KB limit=${limit_kb}KB"
  else
    fail "idle footprint" "cpu=${cpu:-unknown}% rss=${rss_kb:-unknown}KB limit=${limit_kb}KB"
  fi
fi

minimix_processes="$(pgrep -x MiniMix || true)"
minimix_process_count="$(printf '%s\n' "$minimix_processes" | grep -Ec '^[0-9]+$' || true)"
if [[ "$minimix_process_count" -eq 1 ]]; then
  pass "single MiniMix process" "pids=$(printf '%s' "$minimix_processes" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
else
  fail "single MiniMix process" "expected=1 actual=$minimix_process_count pids=$(printf '%s' "$minimix_processes" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
fi

helper_matches="$(
  ps -axo pid=,comm=,args= |
    grep -Ei 'MiniMix.*(Helper|Daemon|Agent)|MiniMix Helper|MiniMixDaemon|MiniMixAgent' |
    grep -Ev 'grep -Ei|audit-mvp-status|report-mvp-acceptance|validate-noninteractive-mvp' || true
)"
if [[ -z "$helper_matches" ]]; then
  pass "no MiniMix helper process"
else
  fail "no MiniMix helper process" "$(printf '%s' "$helper_matches" | tr '\n' '; ' | sed 's/[[:space:]][[:space:]]*/ /g; s/[;[:space:]]*$//')"
fi
cleanup

if scripts/compare-audio-benchmarks.sh >/tmp/minimix-audit-benchmarks.txt 2>&1; then
  pass "benchmark comparison" "scripts/compare-audio-benchmarks.sh"
  awk '/minimix-appkit-(idle|active)[[:space:]]+MiniMix/ { print "  " $0 }' /tmp/minimix-audit-benchmarks.txt
else
  warn "benchmark comparison" "comparison report could not be produced"
  sed 's/^/  /' /tmp/minimix-audit-benchmarks.txt
fi

if scripts/probe-audio-competitor-inventory.sh >/tmp/minimix-audit-competitors.txt 2>&1; then
  pass "competitor inventory" "scripts/probe-audio-competitor-inventory.sh"
  sed 's/^/  /' /tmp/minimix-audit-competitors.txt
else
  warn "competitor inventory" "competitor inventory could not be produced"
  sed 's/^/  /' /tmp/minimix-audit-competitors.txt
fi

if [[ "$run_full" == true ]]; then
  check_command "full silent MVP gate" scripts/validate-noninteractive-mvp.sh
else
  warn "full silent MVP gate" "skipped; run scripts/audit-mvp-status.sh --full"
fi

if scripts/probe-live-voice-readiness.sh "$configuration" >/tmp/minimix-audit-voice.txt 2>&1; then
  pass "live voice readiness"
  sed 's/^/  /' /tmp/minimix-audit-voice.txt
else
  warn "live voice readiness" "packaged app permissions are not fully granted yet"
  sed 's/^/  /' /tmp/minimix-audit-voice.txt
fi

echo
printf 'Summary: %d pass, %d warn, %d fail\n' "$passes" "$warnings" "$failures"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
