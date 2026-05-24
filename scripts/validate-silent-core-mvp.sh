#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gain="${1:-0.35}"
second_gain="${2:-0.55}"
sound="${MINIMIX_SILENT_FIXTURE:-}"

cleanup() {
  pkill -x afplay >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$repo_root"
scripts/guard-coreaudio-load.sh

if [[ -z "$sound" ]]; then
  sound="$(scripts/ensure-silent-audio-fixture.sh)"
fi

if [[ ! -f "$sound" ]]; then
  echo "Missing silent fixture: $sound" >&2
  exit 2
fi

run_and_require() {
  local label="$1"
  local expected="$2"
  shift 2

  local output
  if ! output="$("$@" 2>&1)"; then
    echo "silentCoreMVP=false failed=$label" >&2
    printf '%s\n' "$output" >&2
    exit 10
  fi

  printf '%s\n' "$output"
  if [[ "$output" != *"$expected"* ]]; then
    echo "silentCoreMVP=false failed=$label missing='$expected'" >&2
    exit 11
  fi
}

cleanup

echo "== Silent core MVP probes =="
echo "silentFixture=$sound"

run_and_require "state" "defaultRuleNoop=true mutePersisted=true unmuteRemovedRule=true" scripts/probe-app-state.sh
run_and_require "process inspector" "processInspectorHarness" scripts/probe-process-inspector.sh "$sound"
run_and_require "panel focus" "panelFocusHarness nonactivating=true cannotBecomeKey=true cannotBecomeMain=true" scripts/probe-panel-focus-policy.sh
run_and_require "relaunch" "relaunchHarness oldSessionApplied=true disappearedRemovedSession=true relaunchedRuleVisible=true relaunchedSessionApplied=true resetRemovedSession=true resetRemovedRule=true" scripts/probe-app-relaunch.sh
run_and_require "default noop" "defaultNoopHarness activeAfterDefault=0" scripts/probe-app-engine-default-noop.sh "$sound"
run_and_require "single gain" "gainHarness activeAfterApply=1 activeAfterRemove=0 tapCount=0" scripts/probe-app-engine-gain.sh "$gain" "$sound"
run_and_require "single mute" "muteHarness activeAfterMute=1 muted=true gain=0.0 activeAfterUnmute=0 tapCount=0" scripts/probe-app-engine-mute.sh "$sound"
run_and_require "controller gain" "controllerHarness detectedApps=1 activeAfterVolume=1 activeAfterReset=0 tapCount=0" scripts/probe-controller-gain.sh "$gain" "$sound"
run_and_require "output device restart" "outputDeviceHarness activeBeforeRestart=1 activeAfterRestart=1 restartCountBefore=0 restartCountAfter=1 activeAfterRemove=0 tapCount=0" scripts/probe-output-device-restart.sh "$gain" "$sound"
run_and_require "multi gain" "multiHarness activeAfterApply=2 activeAfterFirstRemove=1 activeAfterSecondRemove=0 tapCount=0" scripts/probe-multi-app-gain.sh "$gain" "$second_gain" "$sound"
run_and_require "hotkey" "hotkeyHarness registered=true reusableAfterStop=true" scripts/probe-hotkey-registration.sh
run_and_require "voice flow" "sttLoadedWhileRecording=false" scripts/probe-voice-flow.sh "$sound"
run_and_require "voice shutdown" "voiceShutdownHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeWhileRecording=1" scripts/probe-voice-shutdown.sh "$sound"
run_and_require "voice shutdown during start" "voiceShutdownDuringStartHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 immediateStatus=idle activeAfterShutdown=0" scripts/probe-voice-shutdown-during-start.sh "$sound"
run_and_require "voice early release" "voiceEarlyReleaseHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeAfterEarlyRelease=0" scripts/probe-voice-early-release.sh
run_and_require "voice hotkey early release" "voiceHotkeyEarlyReleaseHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeAfterEarlyRelease=0" scripts/probe-voice-hotkey-early-release.sh
run_and_require "voice recorder failure" "voiceRecorderFailureHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeAfterFailure=0 restoredVolume=1.0" scripts/probe-voice-recorder-failure.sh
run_and_require "voice STT failure" "voiceSTTFailureHarness activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0" scripts/probe-voice-stt-failure.sh
run_and_require "voice paste failure" "voicePasteFailureHarness activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0" scripts/probe-voice-paste-failure.sh

residue="$(scripts/probe-coreaudio-residue.sh)"
printf '%s\n' "$residue"
if [[ "$residue" != *"count=0"* || "$residue" != *"minimixDeviceCount=0"* ]]; then
  echo "silentCoreMVP=false failed=coreaudio residue" >&2
  exit 12
fi

cleanup
echo "silentCoreMVP ok"
