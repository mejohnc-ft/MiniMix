#!/usr/bin/env bash
set -euo pipefail

configuration="release"
check_only=false
wait_for_ready=false
allow_adhoc=false
wait_seconds="${MINIMIX_PERMISSION_WAIT_SECONDS:-120}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/build/MiniMix.app"
output_file="$(mktemp -t minimix-ls-permission-request.XXXXXX)"
build_log="$(mktemp -t minimix-ls-permission-build.XXXXXX)"

usage() {
  cat <<'EOF'
Usage:
  scripts/request-packaged-voice-permissions-launchservices.sh [debug|release] [--check-only] [--wait] [--allow-adhoc]

Builds MiniMix.app and, unless --check-only is supplied, launches the packaged
app through LaunchServices in the background to request microphone, Speech, and
Accessibility permissions without opening the MiniMix panel.

This is opt-in because macOS may show privacy prompts. It does not record,
transcribe, paste, or play audio.

By default, requesting permissions is blocked for ad-hoc signed builds because
packaged macOS privacy grants are more repeatable with a stable signing
identity. Use --allow-adhoc only when intentionally granting permissions to the
current ad-hoc build.
EOF
}

cleanup() {
  rm -f "$output_file" "$build_log"
  osascript -e 'tell application "MiniMix" to quit' >/dev/null 2>&1 || pkill -x MiniMix >/dev/null 2>&1 || true
}
trap cleanup EXIT

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

cd "$repo_root"

if [[ "$check_only" == true ]]; then
  scripts/probe-packaged-voice-permissions-launchservices.sh "$configuration"
  exit $?
fi

if ! scripts/build-app-bundle.sh "$configuration" >"$build_log" 2>&1; then
  cat "$build_log" >&2
  exit 4
fi

signature="$(codesign -dv "$app" 2>&1 || true)"
signature_summary="$(printf '%s\n' "$signature" | grep -E 'Signature=|Authority=|TeamIdentifier=|CodeDirectory' | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/ $//')"
is_adhoc=false
if [[ "$signature" == *"Signature=adhoc"* || "$signature" == *"TeamIdentifier=not set"* ]]; then
  is_adhoc=true
fi

if [[ "$is_adhoc" == true && "$allow_adhoc" != true ]]; then
  echo "voicePermissionRequest=false reason=ad-hoc signature would make packaged voice permissions unstable" >&2
  echo "codeSignature ${signature_summary:-unavailable}" >&2
  echo "Create/select a stable identity first:" >&2
  echo "  scripts/setup-local-codesign-identity.sh" >&2
  echo "  scripts/setup-local-codesign-identity.sh --install MiniMix\\ Local\\ Code\\ Signing" >&2
  echo "After install, scripts/build-app-bundle.sh auto-selects that identity." >&2
  echo "Override only if intentional:" >&2
  echo "  scripts/request-packaged-voice-permissions-launchservices.sh $configuration --allow-adhoc" >&2
  exit 65
fi

open -g -W -n "$app" --args \
  --voice-permission-request-harness \
  --launchservices-packaged \
  --harness-output "$output_file" >/dev/null 2>&1 &
open_pid=$!

deadline=$((SECONDS + wait_seconds))
while [[ "$SECONDS" -lt "$deadline" ]]; do
  if [[ -s "$output_file" ]]; then
    break
  fi
  if ! kill -0 "$open_pid" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [[ ! -s "$output_file" ]]; then
  echo "voicePermissionRequest=false reason=no permission request result before timeout seconds=$wait_seconds" >&2
  kill "$open_pid" >/dev/null 2>&1 || true
  exit 66
fi

wait "$open_pid" >/dev/null 2>&1 || true

status="$(cat "$output_file")"
printf '%s\n' "$status"

if [[ "$wait_for_ready" == true ]]; then
  deadline=$((SECONDS + wait_seconds))
  while [[ "$SECONDS" -lt "$deadline" ]]; do
    if scripts/probe-packaged-voice-permissions-launchservices.sh "$configuration" >/tmp/minimix-ls-permission-wait.txt 2>&1; then
      cat /tmp/minimix-ls-permission-wait.txt
      echo "voicePermissionRequest=ready"
      exit 0
    fi
    sleep 2
  done

  cat /tmp/minimix-ls-permission-wait.txt 2>/dev/null || true
  echo "voicePermissionRequest=notReadyAfterWait seconds=$wait_seconds" >&2
  exit 66
fi

if [[ "$status" == *"ready=true"* ]]; then
  exit 0
fi

exit 66
