#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gain="${1:-0.35}"
sound="${2:-}"

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
  echo "singleAppGainMVP ready=false reason=missing silent fixture path=$sound" >&2
  exit 2
fi

cleanup

process_output="$(scripts/probe-process-inspector.sh "$sound" 2>&1)"
printf '%s\n' "$process_output"

if [[ "$process_output" != *"processInspectorHarness"* || "$process_output" != *"runningOutput=true"* || "$process_output" != *"audioObjectID="* ]]; then
  echo "singleAppGainMVP ready=false reason=active audio process detection failed" >&2
  exit 10
fi

controller_output="$(scripts/probe-controller-gain.sh "$gain" "$sound" 2>&1)"
printf '%s\n' "$controller_output"

required=(
  "controllerHarness"
  "detectedApps=1"
  "activeAfterVolume=1"
  "activeAfterReset=0"
  "tapCount=0"
  "gain=$gain"
  "activeTapID="
  "activeAggregateDeviceID="
  "activeGain=$gain"
  "activeMuted=false"
  "savedRuleVolume=$gain"
  "ruleAfterReset=nil"
  "sessionsAfterReset=0"
)

for expected in "${required[@]}"; do
  if [[ "$controller_output" != *"$expected"* ]]; then
    echo "singleAppGainMVP ready=false reason=controller proof missing expected='$expected'" >&2
    exit 11
  fi
done

residue="$(scripts/probe-coreaudio-residue.sh 2>&1)"
printf '%s\n' "$residue"
if [[ "$residue" != *"count=0"* || "$residue" != *"minimixDeviceCount=0"* ]]; then
  echo "singleAppGainMVP ready=false reason=Core Audio residue remains" >&2
  exit 12
fi

cleanup
echo "singleAppGainMVP ready=true gain=$gain activeAudioDetected=true tapCreated=true gainApplied=true rulePersisted=true resetRemovedRule=true tapDestroyed=true residueClean=true"
