#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repo_root"

probe_status=0
if [[ "${MINIMIX_RUN_UI_PROBES:-0}" == "1" ]]; then
  status="$(scripts/probe-packaged-voice-permissions.sh "$configuration")" || probe_status=$?
else
  status="$(scripts/probe-packaged-voice-permissions-launchservices.sh "$configuration")" || probe_status=$?
fi

echo "$status"

if [[ "$probe_status" -ne 0 && "$probe_status" -ne 66 ]]; then
  echo "liveVoiceReady=false reason=packaged permission probe failed status=$probe_status" >&2
  exit "$probe_status"
fi

if [[ "$status" != *"Voice permissions ready"* && "$status" != *"ready=true"* ]]; then
  echo "liveVoiceReady=false reason=packaged app still needs mic, Speech, or Accessibility permission" >&2
  exit 66
fi

echo "liveVoiceReady=true"
