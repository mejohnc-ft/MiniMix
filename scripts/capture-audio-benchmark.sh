#!/usr/bin/env bash
set -euo pipefail

label="${1:-snapshot}"
duration="${2:-60}"
interval="${MINIMIX_BENCH_INTERVAL:-5}"
stamp="$(date +%Y%m%d-%H%M%S)"
out_dir="benchmarks/${stamp}-${label}"

mkdir -p "$out_dir"

echo "label=$label" > "$out_dir/metadata.txt"
echo "duration=$duration" >> "$out_dir/metadata.txt"
echo "interval=$interval" >> "$out_dir/metadata.txt"
date >> "$out_dir/metadata.txt"
sw_vers >> "$out_dir/metadata.txt"
uname -a >> "$out_dir/metadata.txt"

pmset -g assertions > "$out_dir/pmset-assertions-start.txt" 2>&1 || true
pmset -g custom > "$out_dir/pmset-custom.txt" 2>&1 || true
system_profiler SPAudioDataType > "$out_dir/audio-devices.txt" 2>&1 || true
find /Library/Audio/Plug-Ins/HAL -maxdepth 2 -type d -print > "$out_dir/hal-drivers.txt" 2>&1 || true
launchctl print gui/"$(id -u)" > "$out_dir/launchctl-gui.txt" 2>&1 || true

samples=$(( duration / interval ))
if [ "$samples" -lt 1 ]; then
  samples=1
fi

{
  echo "timestamp,pid,ppid,cpu,mem,rss_kb,args"
  for _ in $(seq 1 "$samples"); do
    ts="$(date -Iseconds)"
    ps -axo pid=,ppid=,%cpu=,%mem=,rss=,args= |
      rg -i 'MiniMix|FineTune|SoundSource|arkaudiod|coreaudiod|AirPlayXPCHelper|Background Music|BGM' |
      awk -v ts="$ts" '{pid=$1; ppid=$2; cpu=$3; mem=$4; rss=$5; args=""; for (i=6; i<=NF; i++) args=args (i==6 ? "" : " ") $i; gsub(",", " ", args); print ts "," pid "," ppid "," cpu "," mem "," rss "," args}'
    sleep "$interval"
  done
} > "$out_dir/process-samples.csv"

pmset -g assertions > "$out_dir/pmset-assertions-end.txt" 2>&1 || true
sysctl vm.swapusage > "$out_dir/swapusage.txt" 2>&1 || true
uptime > "$out_dir/uptime.txt" 2>&1 || true

echo "Wrote $out_dir"
