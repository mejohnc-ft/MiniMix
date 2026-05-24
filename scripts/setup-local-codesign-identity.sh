#!/usr/bin/env bash
set -euo pipefail

identity_name="${MINIMIX_LOCAL_CODESIGN_IDENTITY:-MiniMix Local Code Signing}"
install=false
trust=true
keychain="${MINIMIX_CODESIGN_KEYCHAIN:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/setup-local-codesign-identity.sh [--install] [--no-trust] [identity-name]

Default mode is read-only. It prints current code-signing identities and the
MINIMIX_CODESIGN_IDENTITY value to use when one is available.

--install creates a local self-signed Code Signing certificate, imports it into
the default keychain, and trusts it for code signing. This may prompt for
keychain or trust approval. It is intended for local development only.

Environment:
  MINIMIX_LOCAL_CODESIGN_IDENTITY   Identity common name to create/check.
  MINIMIX_CODESIGN_KEYCHAIN         Keychain path; default is current default keychain.
  MINIMIX_LOCAL_CODESIGN_P12_PASSWORD  Temporary PKCS#12 export password.
  MINIMIX_KEYCHAIN_PASSWORD         Optional keychain password for partition-list setup.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --install)
      install=true
      shift
      ;;
    --no-trust)
      trust=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      identity_name="$1"
      shift
      ;;
  esac
done

if [[ -z "$keychain" ]]; then
  keychain="$(security default-keychain | tr -d '"' | xargs)"
fi

find_identities() {
  security find-identity -v -p codesigning "$keychain" 2>/dev/null || true
}

identities="$(find_identities)"
matching_identity="$(printf '%s\n' "$identities" | grep -F "\"$identity_name\"" | head -n 1 || true)"
valid_count="$(printf '%s\n' "$identities" | awk '/valid identities found/ { print $1 }' | tail -n 1)"
valid_count="${valid_count:-0}"

printf 'codeSignKeychain=%s\n' "$keychain"
printf '%s\n' "$identities"

if [[ -n "$matching_identity" ]]; then
  printf 'localCodeSignIdentity=present name="%s"\n' "$identity_name"
  printf 'export MINIMIX_CODESIGN_IDENTITY=%q\n' "$identity_name"
  printf 'MINIMIX_CODESIGN_IDENTITY=%q scripts/build-app-bundle.sh release\n' "$identity_name"
  exit 0
fi

if [[ "$install" != true ]]; then
  printf 'localCodeSignIdentity=missing name="%s" validIdentityCount=%s\n' "$identity_name" "$valid_count"
  printf 'To create one for local packaged voice permission testing, run:\n'
  printf '  scripts/setup-local-codesign-identity.sh --install %q\n' "$identity_name"
  exit 0
fi

tmp_dir="$(mktemp -d -t minimix-codesign.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

key_file="$tmp_dir/minimix-codesign.key.pem"
cert_file="$tmp_dir/minimix-codesign.cert.pem"
p12_file="$tmp_dir/minimix-codesign.p12"
p12_password="${MINIMIX_LOCAL_CODESIGN_P12_PASSWORD:-minimix-local}"

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -sha256 \
  -days 3650 \
  -subj "/CN=$identity_name/" \
  -addext "basicConstraints=critical,CA:true" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$key_file" \
  -out "$cert_file" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -name "$identity_name" \
  -inkey "$key_file" \
  -in "$cert_file" \
  -out "$p12_file" \
  -passout "pass:$p12_password" >/dev/null 2>&1

security import "$p12_file" \
  -k "$keychain" \
  -f pkcs12 \
  -P "$p12_password" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

if [[ "$trust" == true ]]; then
  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$keychain" \
    "$cert_file" >/dev/null
fi

if [[ -n "${MINIMIX_KEYCHAIN_PASSWORD:-}" ]]; then
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$MINIMIX_KEYCHAIN_PASSWORD" \
    "$keychain" >/dev/null 2>&1 || true
fi

identities="$(find_identities)"
matching_identity="$(printf '%s\n' "$identities" | grep -F "\"$identity_name\"" | head -n 1 || true)"
printf '%s\n' "$identities"

if [[ -z "$matching_identity" ]]; then
  echo "localCodeSignIdentity=false reason=created identity was not valid for code signing" >&2
  exit 1
fi

printf 'localCodeSignIdentity=installed name="%s"\n' "$identity_name"
printf 'export MINIMIX_CODESIGN_IDENTITY=%q\n' "$identity_name"
printf 'MINIMIX_CODESIGN_IDENTITY=%q scripts/build-app-bundle.sh release\n' "$identity_name"
