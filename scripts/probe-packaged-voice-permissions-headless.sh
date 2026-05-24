#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
executable="$app/Contents/MacOS/MiniMix"

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  echo "configuration must be debug or release" >&2
  exit 2
fi

cd "$repo_root"
scripts/build-app-bundle.sh "$configuration" >/dev/null

if [[ ! -x "$executable" ]]; then
  echo "processVoicePermissionsHeadless ready=false authoritativeForPackagedApp=false reason=missing packaged executable" >&2
  exit 3
fi

status="$("$executable" --voice-permission-harness || true)"
printf '%s\n' "$status" | sed 's/^/headlessDiagnostic /'
echo "headlessDiagnostic authoritative=false reason=direct executable launch can differ from LaunchServices packaged-app TCC grants"
exit 66
