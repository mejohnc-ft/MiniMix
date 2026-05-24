#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="release"
run_full=false
skip_core=false

usage() {
  cat <<'EOF'
Usage:
  scripts/report-mvp-acceptance.sh [--configuration debug|release] [--full] [--skip-core]

Runs the safe MVP audit and silent core MVP gate, then prints an
acceptance-criteria report. By default it does not run the full packaged UI gain
probe. --full passes through to scripts/audit-mvp-status.sh --full, whose UI
path uses silent fixtures.
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
    --skip-core)
      skip_core=true
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

audit_file="$(mktemp -t minimix-audit.XXXXXX)"
debug_audit_file="$(mktemp -t minimix-debug-audit.XXXXXX)"
core_file="$(mktemp -t minimix-core.XXXXXX)"
packaged_state_file="$(mktemp -t minimix-packaged-state.XXXXXX)"
packaged_relaunch_file="$(mktemp -t minimix-packaged-relaunch.XXXXXX)"
packaged_default_noop_file="$(mktemp -t minimix-packaged-default-noop.XXXXXX)"
single_app_gain_file="$(mktemp -t minimix-single-app-gain.XXXXXX)"
packaged_single_app_gain_file="$(mktemp -t minimix-packaged-single-app-gain.XXXXXX)"
packaged_multi_app_gain_file="$(mktemp -t minimix-packaged-multi-app-gain.XXXXXX)"
packaged_mute_file="$(mktemp -t minimix-packaged-mute.XXXXXX)"
packaged_output_device_file="$(mktemp -t minimix-packaged-output-device.XXXXXX)"
apple_speech_file="$(mktemp -t minimix-apple-speech.XXXXXX)"
packaged_apple_speech_file="$(mktemp -t minimix-packaged-apple-speech.XXXXXX)"
microphone_file="$(mktemp -t minimix-microphone.XXXXXX)"
packaged_microphone_file="$(mktemp -t minimix-packaged-microphone.XXXXXX)"
voice_real_recorder_file="$(mktemp -t minimix-voice-real-recorder.XXXXXX)"
packaged_hotkey_file="$(mktemp -t minimix-packaged-hotkey.XXXXXX)"
packaged_voice_flow_file="$(mktemp -t minimix-packaged-voice-flow.XXXXXX)"
text_injector_file="$(mktemp -t minimix-text-injector.XXXXXX)"
packaged_text_injector_file="$(mktemp -t minimix-packaged-text-injector.XXXXXX)"
launchservices_permissions_file="$(mktemp -t minimix-ls-permissions.XXXXXX)"
automation_status_file="$(mktemp -t minimix-automation-status.XXXXXX)"
competitor_inventory_file="$(mktemp -t minimix-competitors.XXXXXX)"
trap 'rm -f "$audit_file" "$debug_audit_file" "$core_file" "$packaged_state_file" "$packaged_relaunch_file" "$packaged_default_noop_file" "$single_app_gain_file" "$packaged_single_app_gain_file" "$packaged_multi_app_gain_file" "$packaged_mute_file" "$packaged_output_device_file" "$apple_speech_file" "$packaged_apple_speech_file" "$microphone_file" "$packaged_microphone_file" "$voice_real_recorder_file" "$packaged_hotkey_file" "$packaged_voice_flow_file" "$text_injector_file" "$packaged_text_injector_file" "$launchservices_permissions_file" "$automation_status_file" "$competitor_inventory_file"; osascript -e "tell application \"MiniMix\" to quit" >/dev/null 2>&1 || pkill -x MiniMix >/dev/null 2>&1 || true; pkill -x afplay >/dev/null 2>&1 || true' EXIT

audit_args=(--configuration "$configuration")
if [[ "$run_full" == true ]]; then
  audit_args+=(--full)
fi

debug_audit_status=0
if [[ "$configuration" == "debug" ]]; then
  printf 'debug audit covered by primary audit\n' >"$debug_audit_file"
else
  scripts/audit-mvp-status.sh --configuration debug >"$debug_audit_file" 2>&1 || debug_audit_status=$?
fi

audit_status=0
scripts/audit-mvp-status.sh "${audit_args[@]}" >"$audit_file" 2>&1 || audit_status=$?

core_status=0
if [[ "$skip_core" == false ]]; then
  scripts/validate-silent-core-mvp.sh >"$core_file" 2>&1 || core_status=$?
else
  printf 'silentCoreMVP skipped\n' >"$core_file"
fi

packaged_state_status=0
scripts/probe-packaged-app-state-launchservices.sh "$configuration" >"$packaged_state_file" 2>&1 || packaged_state_status=$?

packaged_relaunch_status=0
scripts/probe-packaged-app-relaunch-launchservices.sh "$configuration" >"$packaged_relaunch_file" 2>&1 || packaged_relaunch_status=$?

packaged_default_noop_status=0
scripts/probe-packaged-default-noop-launchservices.sh "$configuration" >"$packaged_default_noop_file" 2>&1 || packaged_default_noop_status=$?

single_app_gain_status=0
scripts/validate-single-app-gain-mvp.sh >"$single_app_gain_file" 2>&1 || single_app_gain_status=$?

packaged_single_app_gain_status=0
scripts/probe-packaged-single-app-gain-launchservices.sh "$configuration" 0.35 >"$packaged_single_app_gain_file" 2>&1 || packaged_single_app_gain_status=$?

packaged_multi_app_gain_status=0
scripts/probe-packaged-multi-app-gain-launchservices.sh "$configuration" 0.35 0.55 >"$packaged_multi_app_gain_file" 2>&1 || packaged_multi_app_gain_status=$?

packaged_mute_status=0
scripts/probe-packaged-mute-launchservices.sh "$configuration" >"$packaged_mute_file" 2>&1 || packaged_mute_status=$?

packaged_output_device_status=0
scripts/probe-packaged-output-device-restart-launchservices.sh "$configuration" 0.35 >"$packaged_output_device_file" 2>&1 || packaged_output_device_status=$?

apple_speech_status=0
scripts/probe-apple-speech-baseline.sh >"$apple_speech_file" 2>&1 || apple_speech_status=$?

packaged_apple_speech_status=0
scripts/probe-packaged-apple-speech-baseline-launchservices.sh "$configuration" >"$packaged_apple_speech_file" 2>&1 || packaged_apple_speech_status=$?

microphone_status=0
scripts/probe-microphone-recorder.sh >"$microphone_file" 2>&1 || microphone_status=$?

packaged_microphone_status=0
scripts/probe-packaged-microphone-recorder-launchservices.sh "$configuration" >"$packaged_microphone_file" 2>&1 || packaged_microphone_status=$?

voice_real_recorder_status=0
scripts/probe-voice-real-recorder-flow.sh >"$voice_real_recorder_file" 2>&1 || voice_real_recorder_status=$?

packaged_hotkey_status=0
scripts/probe-packaged-hotkey-registration-launchservices.sh "$configuration" >"$packaged_hotkey_file" 2>&1 || packaged_hotkey_status=$?

packaged_voice_flow_status=0
scripts/probe-packaged-voice-flow-launchservices.sh "$configuration" >"$packaged_voice_flow_file" 2>&1 || packaged_voice_flow_status=$?

text_injector_status=0
scripts/probe-text-injector-readiness.sh >"$text_injector_file" 2>&1 || text_injector_status=$?

packaged_text_injector_status=0
scripts/probe-packaged-text-injector-readiness-launchservices.sh "$configuration" >"$packaged_text_injector_file" 2>&1 || packaged_text_injector_status=$?

launchservices_permissions_status=0
scripts/probe-packaged-voice-permissions-launchservices.sh "$configuration" >"$launchservices_permissions_file" 2>&1 || launchservices_permissions_status=$?

automation_status_status=0
scripts/probe-packaged-automation-status.sh "$configuration" >"$automation_status_file" 2>&1 || automation_status_status=$?

competitor_inventory_status=0
scripts/probe-audio-competitor-inventory.sh >"$competitor_inventory_file" 2>&1 || competitor_inventory_status=$?

has_pass() {
  grep -Eq "^PASS[[:space:]]+$1([[:space:]]|$)" "$audit_file"
}

debug_has_pass() {
  if [[ "$configuration" == "debug" ]]; then
    has_pass "$1"
  else
    grep -Eq "^PASS[[:space:]]+$1([[:space:]]|$)" "$debug_audit_file"
  fi
}

has_warn() {
  grep -Eq "^WARN[[:space:]]+$1([[:space:]]|$)" "$audit_file"
}

line_for() {
  grep -E "^(PASS|WARN|FAIL)[[:space:]]+$1([[:space:]]|$)" "$audit_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g'
}

core_line_for() {
  grep -E "$1" "$core_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g'
}

debug_line_for() {
  if [[ "$configuration" == "debug" ]]; then
    line_for "$1"
  else
    grep -E "^(PASS|WARN|FAIL)[[:space:]]+$1([[:space:]]|$)" "$debug_audit_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g'
  fi
}

criterion() {
  local status="$1"
  local label="$2"
  local evidence="$3"
  printf '%-12s %s\n' "$status" "$label"
  [[ -z "$evidence" ]] || printf '             %s\n' "$evidence"
}

echo "MiniMix MVP acceptance report"
echo "configuration=$configuration full=$run_full skipCore=$skip_core"
echo

if [[ "$audit_status" -eq 0 ]]; then
  criterion "PROVEN" "audit command completed" "scripts/audit-mvp-status.sh ${audit_args[*]}"
else
  criterion "FAILED" "audit command completed" "exit=$audit_status"
fi

if [[ "$debug_audit_status" -eq 0 ]]; then
  criterion "PROVEN" "debug audit command completed" "$([[ "$configuration" == "debug" ]] && printf 'covered by primary audit' || printf 'scripts/audit-mvp-status.sh --configuration debug')"
else
  criterion "FAILED" "debug audit command completed" "exit=$debug_audit_status"
fi

if [[ "$core_status" -eq 0 && "$skip_core" == false ]]; then
  criterion "PROVEN" "silent core MVP gate completed" "$(grep 'silentCoreMVP ok' "$core_file" | tail -n 1)"
elif [[ "$skip_core" == true ]]; then
  criterion "PARTIAL" "silent core MVP gate completed" "skipped by --skip-core"
else
  criterion "FAILED" "silent core MVP gate completed" "exit=$core_status"
fi

has_pass "swift build" &&
  criterion "PROVEN" "swift build succeeds" "$(line_for "swift build")" ||
  criterion "MISSING" "swift build succeeds" "$(line_for "swift build")"

has_pass "build app bundle" && has_pass "packaged executable" &&
  criterion "PROVEN" "$configuration app bundle is runnable" "$(line_for "packaged executable")" ||
  criterion "MISSING" "$configuration app bundle is runnable" "$(line_for "packaged executable")"

debug_has_pass "build app bundle" && debug_has_pass "packaged executable" &&
  criterion "PROVEN" "debug app bundle is runnable" "$(debug_line_for "packaged executable")" ||
  criterion "MISSING" "debug app bundle is runnable" "$(debug_line_for "packaged executable")"

has_pass "code signature" &&
  criterion "PROVEN" "packaged app is code signed" "$(line_for "code signature")" ||
  criterion "MISSING" "packaged app is code signed" "$(line_for "code signature")"

if has_pass "privacy-stable code signature"; then
  criterion "PROVEN" "packaged voice permission identity is stable" "$(line_for "privacy-stable code signature")"
elif has_warn "privacy-stable code signature"; then
  criterion "PENDING" "packaged voice permission identity is stable" "$(line_for "privacy-stable code signature")"
else
  criterion "MISSING" "packaged voice permission identity is stable" "$(line_for "privacy-stable code signature")"
fi

if has_pass "local signing readiness"; then
  criterion "PROVEN" "local MiniMix signing identity is available for auto-selection" "$(line_for "local signing readiness")"
elif has_warn "local signing readiness"; then
  criterion "PENDING" "local MiniMix signing identity is available for auto-selection" "$(line_for "local signing readiness")"
else
  criterion "MISSING" "local MiniMix signing identity is available for auto-selection" "$(line_for "local signing readiness")"
fi

has_pass "passive voice runtime permissions" &&
  criterion "PROVEN" "runtime voice paths do not request permissions" "$(line_for "passive voice runtime permissions")" ||
  criterion "MISSING" "runtime voice paths do not request permissions" "$(line_for "passive voice runtime permissions")"

has_pass "menubar-only plist" &&
  criterion "PROVEN" "menubar-only packaged app" "$(line_for "menubar-only plist")" ||
  criterion "MISSING" "menubar-only packaged app" "$(line_for "menubar-only plist")"

if has_pass "app name metadata" &&
  has_pass "bundle executable" &&
  has_pass "bundle identifier" &&
  has_pass "bundle package type" &&
  has_pass "automation URL scheme" &&
  has_pass "audio capture usage string" &&
  has_pass "mic usage string" &&
  has_pass "speech usage string" &&
  has_pass "accessibility usage string" &&
  has_pass "apple events usage string"; then
  criterion "PROVEN" "packaged app identity and privacy metadata" "$(line_for "app name metadata"); $(line_for "bundle executable"); $(line_for "bundle identifier"); $(line_for "bundle package type"); $(line_for "automation URL scheme"); $(line_for "audio capture usage string"); $(line_for "mic usage string"); $(line_for "speech usage string"); $(line_for "accessibility usage string"); $(line_for "apple events usage string")"
else
  criterion "MISSING" "packaged app identity and privacy metadata" "$(line_for "app name metadata"); $(line_for "bundle executable"); $(line_for "bundle identifier"); $(line_for "bundle package type"); $(line_for "automation URL scheme"); $(line_for "audio capture usage string"); $(line_for "mic usage string"); $(line_for "speech usage string"); $(line_for "accessibility usage string"); $(line_for "apple events usage string")"
fi

has_pass "idle footprint" &&
  criterion "PROVEN" "$configuration idle CPU/RSS target" "$(line_for "idle footprint")" ||
  criterion "MISSING" "$configuration idle CPU/RSS target" "$(line_for "idle footprint")"

debug_has_pass "idle footprint" &&
  criterion "PROVEN" "debug idle CPU/RSS target" "$(debug_line_for "idle footprint")" ||
  criterion "MISSING" "debug idle CPU/RSS target" "$(debug_line_for "idle footprint")"

packaged_state_summary="$(grep -E 'packagedStateHarness' "$packaged_state_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_state_status" -eq 0 &&
      "$packaged_state_summary" == *"ready=true"* &&
      "$packaged_state_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_state_summary" == *"initialVisible=1"* &&
      "$packaged_state_summary" == *"allAppsVisible=2"* &&
      "$packaged_state_summary" == *"defaultRuleNoop=true"* &&
      "$packaged_state_summary" == *"mutePersisted=true"* &&
      "$packaged_state_summary" == *"unmuteRemovedRule=true"* &&
      "$packaged_state_summary" == *"persistedVolume=0.42"* &&
      "$packaged_state_summary" == *"disappearedRemovedSession=true"* &&
      "$packaged_state_summary" == *"reloadedRuleVisible=true"* &&
      "$packaged_state_summary" == *"resetRemovedRule=true"* ]]; then
  criterion "PROVEN" "packaged state, All Apps, and rule persistence via LaunchServices" "$packaged_state_summary"
else
  criterion "FAILED" "packaged state, All Apps, and rule persistence via LaunchServices" "${packaged_state_summary:-exit=$packaged_state_status}"
fi

packaged_relaunch_summary="$(grep -E 'packagedRelaunchHarness' "$packaged_relaunch_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_relaunch_status" -eq 0 &&
      "$packaged_relaunch_summary" == *"ready=true"* &&
      "$packaged_relaunch_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_relaunch_summary" == *"oldSessionApplied=true"* &&
      "$packaged_relaunch_summary" == *"disappearedRemovedSession=true"* &&
      "$packaged_relaunch_summary" == *"relaunchedRuleVisible=true"* &&
      "$packaged_relaunch_summary" == *"relaunchedSessionApplied=true"* &&
      "$packaged_relaunch_summary" == *"resetRemovedSession=true"* &&
      "$packaged_relaunch_summary" == *"resetRemovedRule=true"* ]]; then
  criterion "PROVEN" "packaged app quit/relaunch rule recovery via LaunchServices" "$packaged_relaunch_summary"
else
  criterion "FAILED" "packaged app quit/relaunch rule recovery via LaunchServices" "${packaged_relaunch_summary:-exit=$packaged_relaunch_status}"
fi

packaged_default_noop_summary="$(grep -E 'packagedDefaultNoopHarness' "$packaged_default_noop_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
packaged_default_noop_taps_before="$(sed -E 's/.*tapCountBefore=([0-9]+).*/\1/' <<<"$packaged_default_noop_summary")"
packaged_default_noop_taps_after="$(sed -E 's/.*tapCountAfterDefault=([0-9]+).*/\1/' <<<"$packaged_default_noop_summary")"
if [[ "$packaged_default_noop_status" -eq 0 &&
      "$packaged_default_noop_summary" == *"ready=true"* &&
      "$packaged_default_noop_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_default_noop_summary" == *"activeAfterDefault=0"* &&
      "$packaged_default_noop_summary" == *"tapCountBefore="* &&
      "$packaged_default_noop_summary" == *"tapCountAfterDefault="* &&
      "$packaged_default_noop_taps_before" == "$packaged_default_noop_taps_after" ]]; then
  criterion "PROVEN" "packaged default-rule no-op via LaunchServices" "$packaged_default_noop_summary"
else
  criterion "FAILED" "packaged default-rule no-op via LaunchServices" "${packaged_default_noop_summary:-exit=$packaged_default_noop_status}"
fi

single_app_gain_summary="$(grep -E 'processInspectorHarness|controllerHarness|singleAppGainMVP' "$single_app_gain_file" | awk '{ out = out (out == "" ? "" : "; ") $0 } END { print out }')"
if [[ "$single_app_gain_status" -eq 0 ]] &&
  [[ "$single_app_gain_summary" == *"processInspectorHarness"* ]] &&
  [[ "$single_app_gain_summary" == *"runningOutput=true"* ]] &&
  [[ "$single_app_gain_summary" == *"controllerHarness"* ]] &&
  [[ "$single_app_gain_summary" == *"detectedApps=1"* ]] &&
  [[ "$single_app_gain_summary" == *"activeAfterVolume=1"* ]] &&
  [[ "$single_app_gain_summary" == *"activeTapID="* ]] &&
  [[ "$single_app_gain_summary" == *"activeAggregateDeviceID="* ]] &&
  [[ "$single_app_gain_summary" == *"activeGain=0.35"* ]] &&
  [[ "$single_app_gain_summary" == *"savedRuleVolume=0.35"* ]] &&
  [[ "$single_app_gain_summary" == *"activeAfterReset=0"* ]] &&
  [[ "$single_app_gain_summary" == *"ruleAfterReset=nil"* ]] &&
  [[ "$single_app_gain_summary" == *"sessionsAfterReset=0"* ]] &&
  [[ "$single_app_gain_summary" == *"tapCount=0"* ]] &&
  [[ "$single_app_gain_summary" == *"singleAppGainMVP ready=true"* ]]; then
  criterion "PROVEN" "single-app gain MVP milestone" "$single_app_gain_summary"
else
  criterion "FAILED" "single-app gain MVP milestone" "${single_app_gain_summary:-exit=$single_app_gain_status}"
fi

packaged_single_app_gain_summary="$(grep -E 'packagedSingleAppGainHarness' "$packaged_single_app_gain_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_single_app_gain_status" -eq 0 &&
      "$packaged_single_app_gain_summary" == *"ready=true"* &&
      "$packaged_single_app_gain_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_single_app_gain_summary" == *"detectedApps=1"* &&
      "$packaged_single_app_gain_summary" == *"activeAfterVolume=1"* &&
      "$packaged_single_app_gain_summary" == *"activeAfterReset=0"* &&
      "$packaged_single_app_gain_summary" == *"tapCount=0"* &&
      "$packaged_single_app_gain_summary" == *"gain=0.35"* &&
      "$packaged_single_app_gain_summary" == *"activeTapID="* &&
      "$packaged_single_app_gain_summary" == *"activeAggregateDeviceID="* &&
      "$packaged_single_app_gain_summary" == *"activeGain=0.35"* &&
      "$packaged_single_app_gain_summary" == *"activeMuted=false"* &&
      "$packaged_single_app_gain_summary" == *"savedRuleVolume=0.35"* &&
      "$packaged_single_app_gain_summary" == *"ruleAfterReset=nil"* &&
      "$packaged_single_app_gain_summary" == *"sessionsAfterReset=0"* ]]; then
  criterion "PROVEN" "packaged single-app gain/reset via LaunchServices" "$packaged_single_app_gain_summary"
else
  criterion "FAILED" "packaged single-app gain/reset via LaunchServices" "${packaged_single_app_gain_summary:-exit=$packaged_single_app_gain_status}"
fi

packaged_multi_app_gain_summary="$(grep -E 'packagedMultiAppGainHarness' "$packaged_multi_app_gain_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_multi_app_gain_status" -eq 0 &&
      "$packaged_multi_app_gain_summary" == *"ready=true"* &&
      "$packaged_multi_app_gain_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_multi_app_gain_summary" == *"activeAfterApply=2"* &&
      "$packaged_multi_app_gain_summary" == *"activeAfterFirstRemove=1"* &&
      "$packaged_multi_app_gain_summary" == *"activeAfterSecondRemove=0"* &&
      "$packaged_multi_app_gain_summary" == *"tapCount=0"* &&
      "$packaged_multi_app_gain_summary" == *"gains=0.35,0.55"* &&
      "$packaged_multi_app_gain_summary" == *"firstTapID="* &&
      "$packaged_multi_app_gain_summary" == *"firstAggregateDeviceID="* &&
      "$packaged_multi_app_gain_summary" == *"firstActiveGain=0.35"* &&
      "$packaged_multi_app_gain_summary" == *"secondTapID="* &&
      "$packaged_multi_app_gain_summary" == *"secondAggregateDeviceID="* &&
      "$packaged_multi_app_gain_summary" == *"secondActiveGain=0.55"* &&
      "$packaged_multi_app_gain_summary" == *"sessionsAfterFirstRemove=1"* &&
      "$packaged_multi_app_gain_summary" == *"sessionsAfterSecondRemove=0"* ]]; then
  criterion "PROVEN" "packaged multi-app gain/teardown via LaunchServices" "$packaged_multi_app_gain_summary"
else
  criterion "FAILED" "packaged multi-app gain/teardown via LaunchServices" "${packaged_multi_app_gain_summary:-exit=$packaged_multi_app_gain_status}"
fi

packaged_mute_summary="$(grep -E 'packagedMuteHarness' "$packaged_mute_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_mute_status" -eq 0 &&
      "$packaged_mute_summary" == *"ready=true"* &&
      "$packaged_mute_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_mute_summary" == *"activeAfterMute=1"* &&
      "$packaged_mute_summary" == *"muted=true"* &&
      "$packaged_mute_summary" == *"gain=0.0"* &&
      "$packaged_mute_summary" == *"activeAfterUnmute=0"* &&
      "$packaged_mute_summary" == *"tapCount=0"* &&
      "$packaged_mute_summary" == *"activeTapID="* &&
      "$packaged_mute_summary" == *"activeAggregateDeviceID="* &&
      "$packaged_mute_summary" == *"sessionsAfterUnmute=0"* ]]; then
  criterion "PROVEN" "packaged mute/unmute teardown via LaunchServices" "$packaged_mute_summary"
else
  criterion "FAILED" "packaged mute/unmute teardown via LaunchServices" "${packaged_mute_summary:-exit=$packaged_mute_status}"
fi

packaged_output_device_summary="$(grep -E 'packagedOutputDeviceHarness' "$packaged_output_device_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_output_device_status" -eq 0 &&
      "$packaged_output_device_summary" == *"ready=true"* &&
      "$packaged_output_device_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_output_device_summary" == *"activeBeforeRestart=1"* &&
      "$packaged_output_device_summary" == *"activeAfterRestart=1"* &&
      "$packaged_output_device_summary" == *"restartCountBefore=0"* &&
      "$packaged_output_device_summary" == *"restartCountAfter=1"* &&
      "$packaged_output_device_summary" == *"activeAfterRemove=0"* &&
      "$packaged_output_device_summary" == *"tapCount=0"* &&
      "$packaged_output_device_summary" == *"gain=0.35"* &&
      "$packaged_output_device_summary" == *"tapBeforeRestart="* &&
      "$packaged_output_device_summary" == *"aggregateBeforeRestart="* &&
      "$packaged_output_device_summary" == *"tapAfterRestart="* &&
      "$packaged_output_device_summary" == *"aggregateAfterRestart="* &&
      "$packaged_output_device_summary" == *"gainAfterRestart=0.35"* &&
      "$packaged_output_device_summary" == *"sessionsAfterRemove=0"* ]]; then
  criterion "PROVEN" "packaged output-device restart recovery via LaunchServices" "$packaged_output_device_summary"
else
  criterion "FAILED" "packaged output-device restart recovery via LaunchServices" "${packaged_output_device_summary:-exit=$packaged_output_device_status}"
fi

if [[ "$core_status" -eq 0 && "$skip_core" == false ]]; then
  core_summary="$(grep -E 'stateHarness|processInspectorHarness|panelFocusHarness|relaunchHarness|defaultNoopHarness|gainHarness|muteHarness|controllerHarness|outputDeviceHarness|multiHarness|hotkeyHarness|voiceHarness|voiceShutdownHarness|voiceShutdownDuringStartHarness|voiceEarlyReleaseHarness|voiceRecorderFailureHarness|voiceSTTFailureHarness|voicePasteFailureHarness|silentCoreMVP ok' "$core_file" | awk '{ out = out (out == "" ? "" : "; ") $0 } END { print out }')"
  criterion "PROVEN" "active Core Audio process detection, non-stealing panel focus policy, relaunch/output-device recovery, default-rule no-op, single-app gain/mute, multi-app gain, reset teardown, deterministic voice duck/insert/shutdown-cancel/startup-cancel/early-release/failure cleanup" "$core_summary"
elif [[ "$run_full" == true ]]; then
  if has_pass "full silent MVP gate"; then
    criterion "PROVEN" "active app detection, single/multi-app gain, reset teardown, packaged UI gain" "$(line_for "full silent MVP gate")"
  else
    criterion "MISSING" "active app detection, single/multi-app gain, reset teardown, packaged UI gain" "$(line_for "full silent MVP gate")"
  fi
else
  criterion "PARTIAL" "active app detection, single/multi-app gain, reset teardown, packaged UI gain" "Full silent gate not run by this report; use --full for current proof."
fi

apple_speech_summary="$(grep -E 'appleSpeechHarness' "$apple_speech_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$apple_speech_status" -eq 0 && "$apple_speech_summary" == *"ready=true"* ]]; then
  criterion "PROVEN" "Apple Speech STTEngine baseline" "$apple_speech_summary"
elif [[ "$apple_speech_status" -eq 66 ]]; then
  criterion "PENDING" "Apple Speech STTEngine baseline" "${apple_speech_summary:-Speech authorization is not ready}"
else
  criterion "FAILED" "Apple Speech STTEngine baseline" "${apple_speech_summary:-exit=$apple_speech_status}"
fi

packaged_apple_speech_summary="$(grep -E 'packagedAppleSpeechHarness' "$packaged_apple_speech_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_apple_speech_status" -eq 0 && "$packaged_apple_speech_summary" == *"ready=true"* && "$packaged_apple_speech_summary" == *"authoritativeForPackagedApp=true"* ]]; then
  criterion "PROVEN" "packaged Apple Speech STTEngine baseline via LaunchServices" "$packaged_apple_speech_summary"
elif [[ "$packaged_apple_speech_status" -eq 66 ]]; then
  criterion "PENDING" "packaged Apple Speech STTEngine baseline via LaunchServices" "${packaged_apple_speech_summary:-packaged Speech authorization is not ready}"
else
  criterion "FAILED" "packaged Apple Speech STTEngine baseline via LaunchServices" "${packaged_apple_speech_summary:-exit=$packaged_apple_speech_status}"
fi

microphone_summary="$(grep -E 'microphoneRecorderHarness' "$microphone_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$microphone_status" -eq 0 && "$microphone_summary" == *"ready=true"* ]]; then
  criterion "PROVEN" "real MicrophoneRecorder capture" "$microphone_summary"
elif [[ "$microphone_status" -eq 66 ]]; then
  criterion "PENDING" "real MicrophoneRecorder capture" "${microphone_summary:-Microphone authorization is not ready}"
else
  criterion "FAILED" "real MicrophoneRecorder capture" "${microphone_summary:-exit=$microphone_status}"
fi

packaged_microphone_summary="$(grep -E 'packagedMicrophoneRecorderHarness' "$packaged_microphone_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_microphone_status" -eq 0 && "$packaged_microphone_summary" == *"ready=true"* && "$packaged_microphone_summary" == *"authoritativeForPackagedApp=true"* ]]; then
  criterion "PROVEN" "packaged MicrophoneRecorder capture via LaunchServices" "$packaged_microphone_summary"
elif [[ "$packaged_microphone_status" -eq 66 ]]; then
  criterion "PENDING" "packaged MicrophoneRecorder capture via LaunchServices" "${packaged_microphone_summary:-packaged Microphone authorization is not ready}"
else
  criterion "FAILED" "packaged MicrophoneRecorder capture via LaunchServices" "${packaged_microphone_summary:-exit=$packaged_microphone_status}"
fi

voice_real_recorder_summary="$(grep -E 'voiceRealRecorderHarness' "$voice_real_recorder_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$voice_real_recorder_status" -eq 0 && "$voice_real_recorder_summary" == *"ready=true"* ]]; then
  criterion "PROVEN" "VoiceInputController real MicrophoneRecorder flow with fake STT/paste" "$voice_real_recorder_summary"
elif [[ "$voice_real_recorder_status" -eq 66 ]]; then
  criterion "PENDING" "VoiceInputController real MicrophoneRecorder flow with fake STT/paste" "${voice_real_recorder_summary:-Microphone authorization is not ready}"
else
  criterion "FAILED" "VoiceInputController real MicrophoneRecorder flow with fake STT/paste" "${voice_real_recorder_summary:-exit=$voice_real_recorder_status}"
fi

packaged_hotkey_summary="$(grep -E 'packagedHotkeyHarness' "$packaged_hotkey_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_hotkey_status" -eq 0 &&
      "$packaged_hotkey_summary" == *"ready=true"* &&
      "$packaged_hotkey_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_hotkey_summary" == *"registered=true"* &&
      "$packaged_hotkey_summary" == *"reusableAfterStop=true"* ]]; then
  criterion "PROVEN" "packaged push-to-talk hotkey registration via LaunchServices" "$packaged_hotkey_summary"
else
  criterion "FAILED" "packaged push-to-talk hotkey registration via LaunchServices" "${packaged_hotkey_summary:-exit=$packaged_hotkey_status}"
fi

packaged_voice_flow_summary="$(grep -E 'packagedVoiceHarness' "$packaged_voice_flow_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_voice_flow_status" -eq 0 &&
      "$packaged_voice_flow_summary" == *"ready=true"* &&
      "$packaged_voice_flow_summary" == *"authoritativeForPackagedApp=true"* &&
      "$packaged_voice_flow_summary" == *"immediateActiveAfterPress=1"* &&
      "$packaged_voice_flow_summary" == *"immediateDuckedVolume=0.35"* &&
      "$packaged_voice_flow_summary" == *"activeAfterStop=0"* &&
      "$packaged_voice_flow_summary" == *"restoredVolume=1.0"* &&
      "$packaged_voice_flow_summary" == *"tapCount=0"* ]]; then
  criterion "PROVEN" "packaged deterministic voice duck/restore/insert flow via LaunchServices" "$packaged_voice_flow_summary"
else
  criterion "FAILED" "packaged deterministic voice duck/restore/insert flow via LaunchServices" "${packaged_voice_flow_summary:-exit=$packaged_voice_flow_status}"
fi

text_injector_summary="$(grep -E 'textInjectorHarness' "$text_injector_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$text_injector_status" -eq 0 && "$text_injector_summary" == *"ready=true"* ]]; then
  criterion "PROVEN" "PasteboardTextInjector Accessibility readiness" "$text_injector_summary"
elif [[ "$text_injector_status" -eq 66 ]]; then
  criterion "PENDING" "PasteboardTextInjector Accessibility readiness" "${text_injector_summary:-Accessibility trust is not ready}"
else
  criterion "FAILED" "PasteboardTextInjector Accessibility readiness" "${text_injector_summary:-exit=$text_injector_status}"
fi

packaged_text_injector_summary="$(grep -E 'packagedTextInjectorHarness' "$packaged_text_injector_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$packaged_text_injector_status" -eq 0 && "$packaged_text_injector_summary" == *"ready=true"* && "$packaged_text_injector_summary" == *"authoritativeForPackagedApp=true"* ]]; then
  criterion "PROVEN" "packaged PasteboardTextInjector Accessibility readiness via LaunchServices" "$packaged_text_injector_summary"
elif [[ "$packaged_text_injector_status" -eq 66 ]]; then
  criterion "PENDING" "packaged PasteboardTextInjector Accessibility readiness via LaunchServices" "${packaged_text_injector_summary:-packaged Accessibility trust is not ready}"
else
  criterion "FAILED" "packaged PasteboardTextInjector Accessibility readiness via LaunchServices" "${packaged_text_injector_summary:-exit=$packaged_text_injector_status}"
fi

launchservices_permissions_summary="$(grep -E 'processVoicePermissionsLaunchServices' "$launchservices_permissions_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$launchservices_permissions_status" -eq 0 && "$launchservices_permissions_summary" == *"ready=true"* ]]; then
  criterion "READY" "packaged voice permissions via LaunchServices without panel UI" "$launchservices_permissions_summary"
elif [[ "$launchservices_permissions_status" -eq 66 ]]; then
  criterion "PENDING" "packaged voice permissions via LaunchServices without panel UI" "${launchservices_permissions_summary:-packaged voice permissions are not ready}"
else
  criterion "FAILED" "packaged voice permissions via LaunchServices without panel UI" "${launchservices_permissions_summary:-exit=$launchservices_permissions_status}"
fi

automation_status_summary="$(grep -E 'packagedAutomationStatus' "$automation_status_file" | tail -n 1 | sed 's/[[:space:]][[:space:]]*/ /g')"
if [[ "$automation_status_status" -eq 0 ]] &&
  [[ "$automation_status_summary" == *"ready=true"* ]] &&
  [[ "$automation_status_summary" == *"unauthorizedIgnored=true"* ]] &&
  [[ "$automation_status_summary" == *"tokenRequired=true"* ]]; then
  criterion "PROVEN" "packaged no-panel automation status channel" "$automation_status_summary"
else
  criterion "FAILED" "packaged no-panel automation status channel" "${automation_status_summary:-exit=$automation_status_status}"
fi

has_pass "current tap cleanup" && has_pass "current aggregate cleanup" &&
  criterion "PROVEN" "no stuck taps or aggregate devices" "$(line_for "current tap cleanup"); $(line_for "current aggregate cleanup")" ||
  criterion "MISSING" "no stuck taps or aggregate devices" "$(line_for "current tap cleanup"); $(line_for "current aggregate cleanup")"

has_pass "no MiniMix HAL driver" && has_pass "no MiniMix launch agents" && has_pass "single MiniMix process" && has_pass "no MiniMix helper process" &&
  criterion "PROVEN" "no custom driver, helper daemon, launch agent" "$(line_for "no MiniMix HAL driver"); $(line_for "no MiniMix launch agents"); $(line_for "single MiniMix process"); $(line_for "no MiniMix helper process")" ||
  criterion "MISSING" "no custom driver, helper daemon, launch agent" "$(line_for "no MiniMix HAL driver"); $(line_for "no MiniMix launch agents"); $(line_for "single MiniMix process"); $(line_for "no MiniMix helper process")"

has_pass "no MiniMix sleep assertion" &&
  criterion "PROVEN" "no sleep blocker" "$(line_for "no MiniMix sleep assertion")" ||
  criterion "MISSING" "no sleep blocker" "$(line_for "no MiniMix sleep assertion")"

has_pass "benchmark comparison" &&
  criterion "PROVEN" "benchmark comparison tooling" "$(line_for "benchmark comparison")" ||
  criterion "MISSING" "benchmark comparison tooling" "$(line_for "benchmark comparison")"

benchmark_rows="$(awk '/minimix-appkit-(idle|active)[[:space:]]+MiniMix/ { sub(/^[[:space:]]+/, ""); out = out (out == "" ? "" : "; ") $0 } END { print out }' "$audit_file")"
if [[ "$benchmark_rows" == *"minimix-appkit-idle"* && "$benchmark_rows" == *"minimix-appkit-active"* ]]; then
  criterion "PROVEN" "idle and active MiniMix benchmark rows" "$benchmark_rows"
else
  criterion "MISSING" "idle and active MiniMix benchmark rows" "${benchmark_rows:-no MiniMix benchmark rows in audit output}"
fi

competitor_inventory_summary="$(grep -E '^audioCompetitor app=' "$competitor_inventory_file" | awk '{ out = out (out == "" ? "" : "; ") $0 } END { print out }')"
if [[ "$competitor_inventory_status" -eq 0 ]] &&
  [[ "$competitor_inventory_summary" == *"app=SoundSource"* ]] &&
  [[ "$competitor_inventory_summary" == *"app=FineTune"* ]] &&
  [[ "$competitor_inventory_summary" == *"app=superwhisper"* ]]; then
  criterion "PROVEN" "current SoundSource, FineTune, and superwhisper inventory" "$competitor_inventory_summary"
else
  criterion "MISSING" "current SoundSource, FineTune, and superwhisper inventory" "${competitor_inventory_summary:-exit=$competitor_inventory_status}"
fi

if has_pass "live voice readiness"; then
  criterion "READY" "live packaged voice permission state" "$(line_for "live voice readiness")"
  criterion "MISSING" "live packaged record/transcribe/paste proof" "Run scripts/probe-live-voice-paste.sh $configuration while speaking a short phrase."
  criterion "MISSING" "live push-to-talk hotkey proof" "After the automation-triggered live proof passes, run MINIMIX_LIVE_VOICE_TRIGGER=hotkey scripts/probe-live-voice-paste.sh $configuration."
else
  criterion "PENDING" "live packaged record/transcribe/paste proof" "$(line_for "live voice readiness")"
  criterion "PENDING" "live push-to-talk hotkey proof" "Packaged voice permissions must be ready before the hotkey path can record."
fi

echo
if [[ "$audit_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=audit failed"
  exit "$audit_status"
fi

if [[ "$debug_audit_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=debug audit failed"
  exit "$debug_audit_status"
fi

if [[ "$core_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=silent core MVP gate failed"
  exit "$core_status"
fi

if [[ "$single_app_gain_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=single-app gain MVP milestone failed"
  exit "$single_app_gain_status"
fi

if [[ "$packaged_state_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged state/rule persistence proof failed"
  exit "$packaged_state_status"
fi

if [[ "$packaged_relaunch_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged app relaunch proof failed"
  exit "$packaged_relaunch_status"
fi

if [[ "$packaged_default_noop_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged default-rule no-op proof failed"
  exit "$packaged_default_noop_status"
fi

if [[ "$packaged_single_app_gain_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged single-app gain proof failed"
  exit "$packaged_single_app_gain_status"
fi

if [[ "$packaged_multi_app_gain_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged multi-app gain proof failed"
  exit "$packaged_multi_app_gain_status"
fi

if [[ "$packaged_mute_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged mute proof failed"
  exit "$packaged_mute_status"
fi

if [[ "$packaged_output_device_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged output-device recovery proof failed"
  exit "$packaged_output_device_status"
fi

if [[ "$apple_speech_status" -ne 0 && "$apple_speech_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=Apple Speech baseline failed"
  exit "$apple_speech_status"
fi

if [[ "$packaged_apple_speech_status" -ne 0 && "$packaged_apple_speech_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=packaged Apple Speech baseline failed"
  exit "$packaged_apple_speech_status"
fi

if [[ "$microphone_status" -ne 0 && "$microphone_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=MicrophoneRecorder proof failed"
  exit "$microphone_status"
fi

if [[ "$packaged_microphone_status" -ne 0 && "$packaged_microphone_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=packaged MicrophoneRecorder proof failed"
  exit "$packaged_microphone_status"
fi

if [[ "$voice_real_recorder_status" -ne 0 && "$voice_real_recorder_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=VoiceInputController real recorder proof failed"
  exit "$voice_real_recorder_status"
fi

if [[ "$packaged_voice_flow_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged deterministic voice flow failed"
  exit "$packaged_voice_flow_status"
fi

if [[ "$packaged_hotkey_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged hotkey registration failed"
  exit "$packaged_hotkey_status"
fi

if [[ "$text_injector_status" -ne 0 && "$text_injector_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=Text injector readiness proof failed"
  exit "$text_injector_status"
fi

if [[ "$packaged_text_injector_status" -ne 0 && "$packaged_text_injector_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=packaged Text injector readiness proof failed"
  exit "$packaged_text_injector_status"
fi

if [[ "$launchservices_permissions_status" -ne 0 && "$launchservices_permissions_status" -ne 66 ]]; then
  echo "mvpComplete=false reason=LaunchServices packaged voice permission probe failed"
  exit "$launchservices_permissions_status"
fi

if [[ "$automation_status_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=packaged automation status probe failed"
  exit "$automation_status_status"
fi

if [[ "$competitor_inventory_status" -ne 0 ]]; then
  echo "mvpComplete=false reason=competitor inventory failed"
  exit "$competitor_inventory_status"
fi

if [[ "$apple_speech_status" -eq 66 || "$packaged_apple_speech_status" -eq 66 || "$microphone_status" -eq 66 || "$packaged_microphone_status" -eq 66 || "$voice_real_recorder_status" -eq 66 || "$text_injector_status" -eq 66 || "$packaged_text_injector_status" -eq 66 ]]; then
  echo "mvpComplete=false reason=permission-gated Apple Speech/live voice proof remains"
elif has_pass "live voice readiness" && [[ "$run_full" == true ]]; then
  echo "mvpComplete=false reason=live paste proof still must be run and captured"
else
  echo "mvpComplete=false reason=permission-gated live voice proof remains"
fi
