#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  set -- benchmarks/*
fi

for benchmark_dir in "$@"; do
  samples="$benchmark_dir/process-samples.csv"
  [[ -f "$samples" ]] || continue

  echo "== $benchmark_dir =="
  awk -F, '
    NR == 1 { next }
    {
      pid = $2
      cpu = $4 + 0
      rss = $6 + 0
      args = $7
      if (args ~ /capture-audio-benchmark|bash scripts|\/bin\/zsh -lc|rg -i/) next
      key = args

      # Collapse app bundles and common helpers into readable process families.
      if (args ~ /MiniMix\.app\/Contents\/MacOS\/MiniMix|\/\.build\/.*\/MiniMix/) key = "MiniMix"
      else if (args ~ /FineTune/) key = "FineTune"
      else if (args ~ /SoundSource/) key = "SoundSource"
      else if (args ~ /superwhisper/) key = "superwhisper"
      else if (args ~ /WhisperKit/) key = "WhisperKit"
      else if (args ~ /arkaudiod/) key = "ARK audio helper"
      else if (args ~ /coreaudiod/) key = "coreaudiod"
      else if (args ~ /AirPlayXPCHelper/) key = "AirPlayXPCHelper"
      else if (args ~ /Background Music|BGM/) key = "Background Music"

      count[key] += 1
      pid_seen[key SUBSEP pid] = 1
      cpu_sum[key] += cpu
      rss_sum[key] += rss
      if (cpu > cpu_max[key]) cpu_max[key] = cpu
      if (rss > rss_max[key]) rss_max[key] = rss
    }
    END {
      printf "%-22s %8s %8s %10s %10s %10s %9s\n", "process", "samples", "avg_cpu", "max_cpu", "avg_rss", "max_rss", "pids"
      for (key in count) {
        pids = 0
        for (pid_key in pid_seen) {
          split(pid_key, parts, SUBSEP)
          if (parts[1] == key) pids += 1
        }
        printf "%-22s %8d %8.2f %10.2f %9.1fM %9.1fM %9d\n",
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

  if [[ -f "$benchmark_dir/hal-drivers.txt" ]]; then
    minimix_hal="$(rg -i 'MiniMix' "$benchmark_dir/hal-drivers.txt" || true)"
    [[ -z "$minimix_hal" ]] && echo "MiniMix HAL drivers: none" || printf 'MiniMix HAL drivers:\n%s\n' "$minimix_hal"
  fi

  if [[ -f "$benchmark_dir/pmset-assertions-end.txt" ]]; then
    minimix_assertions="$(rg -i 'MiniMix' "$benchmark_dir/pmset-assertions-end.txt" || true)"
    [[ -z "$minimix_assertions" ]] && echo "MiniMix sleep assertions: none" || printf 'MiniMix sleep assertions:\n%s\n' "$minimix_assertions"
  fi
done
