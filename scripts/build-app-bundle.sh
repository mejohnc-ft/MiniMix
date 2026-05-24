#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-debug}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codesign_identity="${MINIMIX_CODESIGN_IDENTITY:--}"
local_codesign_identity="${MINIMIX_LOCAL_CODESIGN_IDENTITY:-MiniMix Local Code Signing}"
codesign_options="${MINIMIX_CODESIGN_OPTIONS:-}"

if [[ "$codesign_identity" == "-" ]]; then
  default_keychain="$(security default-keychain 2>/dev/null | tr -d '"' | xargs || true)"
  if [[ -n "$default_keychain" ]] &&
    security find-identity -v -p codesigning "$default_keychain" 2>/dev/null |
      grep -F "\"$local_codesign_identity\"" >/dev/null; then
    codesign_identity="$local_codesign_identity"
  fi
fi

cd "$repo_root"

swift build -c "$configuration"

binary="$repo_root/.build/$configuration/MiniMix"
app="$repo_root/build/MiniMix.app"
contents="$app/Contents"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"

cp "$binary" "$contents/MacOS/MiniMix"
cp "$repo_root/Sources/MiniMix/Resources/MiniMix-Info.plist" "$contents/Info.plist"
printf "APPL????" > "$contents/PkgInfo"

codesign_command=(codesign --force --sign "$codesign_identity")
if [[ -n "$codesign_options" ]]; then
  # shellcheck disable=SC2206
  extra_options=($codesign_options)
  codesign_command+=("${extra_options[@]}")
fi
codesign_command+=("$app")
"${codesign_command[@]}" >/dev/null

echo "$app"
