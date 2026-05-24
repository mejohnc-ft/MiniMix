#!/usr/bin/env bash
set -euo pipefail

configuration="release"
request_permissions=false
wait_for_permissions=false
run_live=false
allow_adhoc=false
trigger="${MINIMIX_LIVE_VOICE_TRIGGER:-automation}"

usage() {
  cat <<'EOF'
Usage:
  scripts/verify-live-voice-mvp.sh [debug|release] [--request-permissions] [--wait] [--run-live] [--trigger automation|hotkey|ui] [--allow-adhoc]

Safe final live-voice MVP orchestrator.

Default mode is non-prompting and non-recording:
  - checks local code-signing identity status
  - checks packaged no-panel automation status through the minimix:// URL scheme
  - checks Apple Speech baseline readiness without requesting authorization
  - checks packaged voice permission state through LaunchServices without opening the MiniMix panel

--request-permissions asks the packaged app to request microphone, Speech, and
Accessibility permissions through LaunchServices without opening the MiniMix
panel. The script refuses ad-hoc signed builds unless --allow-adhoc is also
passed.

--run-live runs the live TextEdit paste proof after readiness is true. It opens
TextEdit and records from the microphone; speak a short phrase when prompted.

--trigger chooses the live proof trigger: automation, hotkey, or ui. Default
is automation, which uses MiniMix URL events and does not open the panel.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    debug|release)
      configuration="$1"
      shift
      ;;
    --request-permissions)
      request_permissions=true
      shift
      ;;
    --wait)
      wait_for_permissions=true
      shift
      ;;
    --run-live)
      run_live=true
      shift
      ;;
    --trigger)
      trigger="${2:-}"
      shift 2
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

if [[ "$trigger" == "notification" ]]; then
  trigger="automation"
fi

if [[ "$trigger" != "hotkey" && "$trigger" != "automation" && "$trigger" != "ui" ]]; then
  echo "trigger must be automation, hotkey, or ui" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "== MiniMix live voice MVP proof =="
echo "configuration=$configuration trigger=$trigger requestPermissions=$request_permissions runLive=$run_live"

echo
echo "== Code signing identity =="
scripts/setup-local-codesign-identity.sh

echo
echo "== Packaged automation status =="
automation_status=0
scripts/probe-packaged-automation-status.sh "$configuration" || automation_status=$?
if [[ "$automation_status" -ne 0 ]]; then
  echo "liveVoiceMVP=false reason=packaged automation status failed status=$automation_status" >&2
  exit "$automation_status"
fi

echo
echo "== Packaged voice permissions =="
permission_status=0
readiness_status=66

permission_args=("$configuration")
if [[ "$request_permissions" == true ]]; then
  [[ "$wait_for_permissions" == true ]] && permission_args+=(--wait)
  [[ "$allow_adhoc" == true ]] && permission_args+=(--allow-adhoc)
  scripts/request-packaged-voice-permissions-launchservices.sh "${permission_args[@]}" || permission_status=$?
else
  permission_args+=(--check-only)
  scripts/request-packaged-voice-permissions-launchservices.sh "${permission_args[@]}" || permission_status=$?
fi

if [[ "$permission_status" -ne 0 && "$permission_status" -ne 65 && "$permission_status" -ne 66 ]]; then
  echo "liveVoiceMVP=false reason=permission request/check failed status=$permission_status" >&2
  exit "$permission_status"
fi

echo
echo "== Apple Speech baseline =="
apple_speech_status=0
scripts/probe-apple-speech-baseline.sh || apple_speech_status=$?
if [[ "$apple_speech_status" -ne 0 && "$apple_speech_status" -ne 66 ]]; then
  echo "liveVoiceMVP=false reason=Apple Speech baseline failed status=$apple_speech_status" >&2
  exit "$apple_speech_status"
fi

echo
echo "== Live voice readiness =="
readiness_status=0
scripts/probe-live-voice-readiness.sh "$configuration" || readiness_status=$?
if [[ "$readiness_status" -ne 0 && "$readiness_status" -ne 66 ]]; then
  echo "liveVoiceMVP=false reason=live voice readiness check failed status=$readiness_status" >&2
  exit "$readiness_status"
fi

if [[ "$run_live" != true ]]; then
  if [[ "$readiness_status" -eq 0 && "$apple_speech_status" -eq 0 ]]; then
    echo "liveVoiceMVP=ready reason=run with --run-live to record and prove paste"
    exit 0
  fi

  echo "liveVoiceMVP=false reason=permission-gated; run signing setup and permission request before --run-live" >&2
  exit 66
fi

if [[ "$readiness_status" -ne 0 ]]; then
  echo "liveVoiceMVP=false reason=packaged voice permissions are not ready" >&2
  exit 66
fi

echo
echo "== Live paste proof =="
MINIMIX_LIVE_VOICE_TRIGGER="$trigger" scripts/probe-live-voice-paste.sh "$configuration"
echo "liveVoiceMVP=true"
