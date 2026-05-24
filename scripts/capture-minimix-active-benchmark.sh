#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
duration="${2:-30}"
gain="${3:-0.35}"

usage() {
  cat <<'EOF'
Usage:
  scripts/capture-minimix-active-benchmark.sh [debug|release] [duration-seconds] [gain]

Builds the packaged MiniMix app, runs its active Core Audio benchmark harness
against a generated silent CAF fixture, captures process/driver/sleep metrics,
and summarizes the resulting benchmark directory.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  echo "configuration must be debug or release" >&2
  usage >&2
  exit 2
fi

if ! [[ "$duration" =~ ^[0-9]+$ ]] || [[ "$duration" -lt 1 ]]; then
  echo "duration must be a positive integer number of seconds" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

harness_pid=""
harness_log="$(mktemp -t minimix-active-harness.XXXXXX)"
fixture="/tmp/minimix-active-benchmark-${duration}s.caf"

cleanup() {
  if [[ -n "$harness_pid" ]] && kill -0 "$harness_pid" >/dev/null 2>&1; then
    pkill -P "$harness_pid" >/dev/null 2>&1 || true
    kill "$harness_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

rm -f "$fixture"
MINIMIX_SILENT_SECONDS=$((duration + 8)) scripts/ensure-silent-audio-fixture.sh "$fixture" >/dev/null
scripts/build-app-bundle.sh "$configuration" >/dev/null

executable="build/MiniMix.app/Contents/MacOS/MiniMix"
"$executable" \
  --active-benchmark-harness "$gain" \
  --duration "$((duration + 2))" \
  --sound "$fixture" >"$harness_log" 2>&1 &
harness_pid="$!"

for _ in {1..80}; do
  if grep -q 'activeBenchmarkHarness ready=true' "$harness_log"; then
    break
  fi
  if ! kill -0 "$harness_pid" >/dev/null 2>&1; then
    echo "MiniMix active benchmark harness exited before becoming ready" >&2
    cat "$harness_log" >&2
    exit 3
  fi
  sleep 0.1
done

if ! grep -q 'activeBenchmarkHarness ready=true' "$harness_log"; then
  echo "MiniMix active benchmark harness did not become ready" >&2
  cat "$harness_log" >&2
  exit 4
fi

benchmark_output="$(MINIMIX_BENCH_INTERVAL="${MINIMIX_BENCH_INTERVAL:-2}" scripts/capture-audio-benchmark.sh minimix-appkit-active "$duration")"
printf '%s\n' "$benchmark_output"
out_dir="$(awk '/^Wrote / { print $2 }' <<< "$benchmark_output" | tail -n 1)"

if [[ -n "$out_dir" && -d "$out_dir" && -f "$out_dir/pmset-assertions-end.txt" ]]; then
  cp "$out_dir/pmset-assertions-end.txt" "$out_dir/pmset-assertions-active.txt"
fi

harness_status=0
wait "$harness_pid" || harness_status=$?
harness_pid=""

if [[ -n "$out_dir" && -d "$out_dir" ]]; then
  cp "$harness_log" "$out_dir/harness.log"
  pmset -g assertions > "$out_dir/pmset-assertions-end.txt" 2>&1 || true
  scripts/summarize-audio-benchmark.sh "$out_dir"
fi

if [[ "$harness_status" -ne 0 ]]; then
  echo "MiniMix active benchmark harness failed with status $harness_status" >&2
  cat "$harness_log" >&2
  exit "$harness_status"
fi

residue="$(scripts/probe-coreaudio-residue.sh)"
printf '%s\n' "$residue"
if [[ "$residue" != *"count=0"* || "$residue" != *"minimixDeviceCount=0"* ]]; then
  echo "Active benchmark left Core Audio residue" >&2
  exit 5
fi
