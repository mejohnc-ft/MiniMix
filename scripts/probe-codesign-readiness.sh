#!/usr/bin/env bash
set -euo pipefail

identity_name="${MINIMIX_LOCAL_CODESIGN_IDENTITY:-MiniMix Local Code Signing}"
keychain="${MINIMIX_CODESIGN_KEYCHAIN:-}"

if [[ -z "$keychain" ]]; then
  keychain="$(security default-keychain 2>/dev/null | tr -d '"' | xargs || true)"
fi

if [[ -z "$keychain" ]]; then
  echo "codeSignReadiness ready=false identity=\"$identity_name\" keychain=unknown validIdentityCount=0 autoSelectable=false"
  exit 66
fi

identities="$(security find-identity -v -p codesigning "$keychain" 2>/dev/null || true)"
valid_count="$(printf '%s\n' "$identities" | awk '/valid identities found/ { print $1 }' | tail -n 1)"
valid_count="${valid_count:-0}"

if printf '%s\n' "$identities" | grep -F "\"$identity_name\"" >/dev/null; then
  echo "codeSignReadiness ready=true identity=\"$identity_name\" keychain=\"$keychain\" validIdentityCount=$valid_count autoSelectable=true"
  exit 0
fi

echo "codeSignReadiness ready=false identity=\"$identity_name\" keychain=\"$keychain\" validIdentityCount=$valid_count autoSelectable=false"
exit 66
