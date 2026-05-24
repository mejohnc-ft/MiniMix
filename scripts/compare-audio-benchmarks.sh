#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/compare-audio-benchmarks.sh [benchmark-dir ...]

With no arguments, compares the latest local benchmark captures for MiniMix,
SoundSource, FineTune, and superwhisper when those folders exist.

This script is read-only. It does not launch apps or play audio.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

latest_dir() {
  local pattern="$1"
  find benchmarks -maxdepth 1 -type d -name "$pattern" 2>/dev/null | sort | tail -n 1
}

latest_label() {
  local wanted_label="$1"
  local dir
  local label
  local latest=""

  while IFS= read -r dir; do
    label="$(sed -n 's/^label=//p' "$dir/metadata.txt" 2>/dev/null | head -n 1)"
    [[ "$label" == "$wanted_label" ]] && latest="$dir"
  done < <(find benchmarks -maxdepth 1 -type d 2>/dev/null | sort)

  printf '%s\n' "$latest"
}

add_default_dir() {
  local pattern="$1"
  local dir
  dir="$(latest_dir "$pattern")"
  [[ -n "$dir" ]] || return 0

  local existing
  for existing in "${benchmark_dirs[@]:-}"; do
    [[ "$existing" == "$dir" ]] && return 0
  done
  benchmark_dirs+=("$dir")
}

add_default_label() {
  local label="$1"
  local dir
  dir="$(latest_label "$label")"
  [[ -n "$dir" ]] || return 0

  local existing
  for existing in "${benchmark_dirs[@]:-}"; do
    [[ "$existing" == "$dir" ]] && return 0
  done
  benchmark_dirs+=("$dir")
}

benchmark_dirs=()
if [[ "$#" -gt 0 ]]; then
  benchmark_dirs=("$@")
else
  add_default_label "minimix-appkit-idle"
  add_default_label "minimix-appkit-active"
  add_default_label "soundsource-idle"
  add_default_label "soundsource-active-afplay"
  add_default_label "finetune-plus-soundsource-idle"
  add_default_label "finetune-plus-soundsource-active-afplay"
  add_default_label "superwhisper-reference-idle"
fi

if [[ "${#benchmark_dirs[@]}" -eq 0 ]]; then
  echo "No benchmark directories found." >&2
  usage >&2
  exit 1
fi

printf '%-42s %-20s %7s %8s %8s %9s %9s %5s\n' \
  "benchmark" "process" "samples" "avg_cpu" "max_cpu" "avg_rss" "max_rss" "pids"
printf '%-42s %-20s %7s %8s %8s %9s %9s %5s\n' \
  "---------" "-------" "-------" "-------" "-------" "-------" "-------" "----"

for benchmark_dir in "${benchmark_dirs[@]}"; do
  samples="$benchmark_dir/process-samples.csv"
  if [[ ! -f "$samples" ]]; then
    echo "Skipping $benchmark_dir: missing process-samples.csv" >&2
    continue
  fi

  label="$(sed -n 's/^label=//p' "$benchmark_dir/metadata.txt" 2>/dev/null | head -n 1)"
  [[ -n "$label" ]] || label="$(basename "$benchmark_dir")"

  awk -F, -v label="$label" '
    NR == 1 { next }
    {
      pid = $2
      cpu = $4 + 0
      rss = $6 + 0
      args = $7
      if (args ~ /capture-audio-benchmark|bash scripts|\/bin\/zsh -lc|rg -i|grep -Ei/) next

      key = ""
      if (args ~ /MiniMix\.app\/Contents\/MacOS\/MiniMix|\/\.build\/.*\/MiniMix/) key = "MiniMix"
      else if (args ~ /SoundSource/) key = "SoundSource"
      else if (args ~ /FineTune/) key = "FineTune"
      else if (args ~ /superwhisper/) key = "superwhisper"
      else if (args ~ /WhisperKit/) key = "WhisperKit"
      else if (args ~ /arkaudiod/) key = "ARK helper"
      else if (args ~ /Background Music|BGM/) key = "Background Music"
      else if (args ~ /coreaudiod/) key = "coreaudiod"
      else if (args ~ /AirPlayXPCHelper/) key = "AirPlayXPCHelper"
      if (key == "") next

      count[key] += 1
      pid_seen[key SUBSEP pid] = 1
      cpu_sum[key] += cpu
      rss_sum[key] += rss
      if (cpu > cpu_max[key]) cpu_max[key] = cpu
      if (rss > rss_max[key]) rss_max[key] = rss
    }
    END {
      order = "MiniMix|SoundSource|FineTune|superwhisper|WhisperKit|ARK helper|Background Music|coreaudiod|AirPlayXPCHelper"
      split(order, keys, "|")
      for (i = 1; i <= length(keys); i++) {
        key = keys[i]
        if (!(key in count)) continue

        pids = 0
        for (pid_key in pid_seen) {
          split(pid_key, parts, SUBSEP)
          if (parts[1] == key) pids += 1
        }

        printf "%-42s %-20s %7d %8.2f %8.2f %8.1fM %8.1fM %5d\n",
          label,
          key,
          count[key],
          cpu_sum[key] / count[key],
          cpu_max[key],
          (rss_sum[key] / count[key]) / 1024,
          rss_max[key] / 1024,
          pids
      }
    }
  ' "$samples"
done

echo
echo "Infrastructure checks:"
for benchmark_dir in "${benchmark_dirs[@]}"; do
  [[ -d "$benchmark_dir" ]] || continue
  label="$(sed -n 's/^label=//p' "$benchmark_dir/metadata.txt" 2>/dev/null | head -n 1)"
  [[ -n "$label" ]] || label="$(basename "$benchmark_dir")"

  minimix_hal="none"
  if [[ -f "$benchmark_dir/hal-drivers.txt" ]] &&
    grep -Eiq 'MiniMix' "$benchmark_dir/hal-drivers.txt"; then
    minimix_hal="present"
  fi

  minimix_sleep="none"
  if [[ -f "$benchmark_dir/pmset-assertions-end.txt" ]] &&
    grep -Eiq 'MiniMix' "$benchmark_dir/pmset-assertions-end.txt"; then
    minimix_sleep="present"
  fi

  observed_stack="none"
  if [[ -f "$benchmark_dir/hal-drivers.txt" ]]; then
    observed_stack="$(
      awk -F/ '
        index($0, "/Library/Audio/Plug-Ins/HAL/") == 1 && NF == 6 {
          driver = $NF
          if (driver !~ /^$/) seen[driver] = 1
        }
        END {
          out = ""
          for (driver in seen) out = out (out == "" ? "" : ", ") driver
          if (out == "") print "none"
          else print out
        }
      ' "$benchmark_dir/hal-drivers.txt"
    )"
  fi

  launch_matches="0"
  if [[ -f "$benchmark_dir/launchctl-gui.txt" ]]; then
    launch_matches="$(
      grep -Ei 'MiniMix|SoundSource|FineTune|superwhisper|arkaudiod|WhisperKit|Background Music|BGM' \
        "$benchmark_dir/launchctl-gui.txt" 2>/dev/null |
        awk 'END { print NR + 0 }'
    )"
  fi

  printf '%-42s MiniMix HAL=%s MiniMix sleep=%s observed HAL=%s launch matches=%s\n' \
    "$label" "$minimix_hal" "$minimix_sleep" "$observed_stack" "$launch_matches"
done

cat <<'EOF'

Notes:
- Older competitor captures can include other already-running audio apps. Compare the process rows, not only the benchmark label.
- MiniMix-specific HAL and sleep checks should remain "none"; existing third-party HAL drivers on the system are reported separately.
EOF
