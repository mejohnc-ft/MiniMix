#!/usr/bin/env bash
set -euo pipefail

limit="${MINIMIX_COREAUDIOD_CPU_LIMIT:-150}"

if [[ "${MINIMIX_ALLOW_HOT_COREAUDIOD:-0}" == "1" ]]; then
  exit 0
fi

line="$(ps -axo pid=,%cpu=,comm= | awk '$3 ~ /(^|\/)coreaudiod$/ { print $1, $2; exit }' || true)"
if [[ -z "$line" ]]; then
  exit 0
fi

pid="$(awk '{ print $1 }' <<<"$line")"
cpu="$(awk '{ print $2 }' <<<"$line")"

if awk -v cpu="$cpu" -v limit="$limit" 'BEGIN { exit !(cpu > limit) }'; then
  cat >&2 <<EOF
MiniMix audio validation refused because coreaudiod is already hot.
coreaudiod pid=$pid cpu=${cpu}% limit=${limit}%

Restart Core Audio before running MiniMix tap/voice probes:
  sudo launchctl kickstart -k system/com.apple.audio.coreaudiod

Override only when intentionally stress-testing:
  MINIMIX_ALLOW_HOT_COREAUDIOD=1 <command>
EOF
  exit 69
fi
