#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app_roots=("/Applications" "$HOME/Applications")
hal_root="/Library/Audio/Plug-Ins/HAL"
launchctl_file="$(mktemp -t minimix-competitor-launchctl.XXXXXX)"
pmset_file="$(mktemp -t minimix-competitor-pmset.XXXXXX)"
ps_file="$(mktemp -t minimix-competitor-ps.XXXXXX)"
trap 'rm -f "$launchctl_file" "$pmset_file" "$ps_file"' EXIT

launchctl print "gui/$(id -u)" >"$launchctl_file" 2>/dev/null || true
pmset -g assertions >"$pmset_file" 2>/dev/null || true
ps -axo pid=,ppid=,%cpu=,rss=,args= >"$ps_file"

find_app_paths() {
  local app_name="$1"
  local root
  for root in "${app_roots[@]}"; do
    [[ -d "$root" ]] || continue
    find "$root" -maxdepth 3 -type d -iname "$app_name.app" -print 2>/dev/null || true
  done
}

line_count_for_regex() {
  local file="$1"
  local regex="$2"
  grep -Eic "$regex" "$file" 2>/dev/null || true
}

hal_matches_for_regex() {
  local regex="$1"
  [[ -d "$hal_root" ]] || return 0
  find "$hal_root" -maxdepth 3 -type d -print 2>/dev/null | grep -Ei "$regex" || true
}

process_summary_for_regex() {
  local regex="$1"
  awk -v regex="$regex" '
    BEGIN { IGNORECASE = 1 }
    $0 ~ regex && $0 !~ /probe-audio-competitor-inventory|awk -v regex|\/bin\/zsh -lc|bash scripts\// {
      pid = $1
      cpu = $3 + 0
      rss = $4 + 0
      pids = pids (pids == "" ? "" : "|") pid
      count += 1
      cpu_sum += cpu
      rss_sum += rss
      if (cpu > max_cpu) max_cpu = cpu
      if (rss > max_rss) max_rss = rss
    }
    END {
      if (count == 0) {
        print "running=false pids=none processCount=0 avgCPU=0.00 maxCPU=0.00 avgRSSKB=0 maxRSSKB=0"
      } else {
        printf "running=true pids=%s processCount=%d avgCPU=%.2f maxCPU=%.2f avgRSSKB=%.0f maxRSSKB=%.0f\n",
          pids,
          count,
          cpu_sum / count,
          max_cpu,
          rss_sum / count,
          max_rss
      }
    }
  ' "$ps_file"
}

report_product() {
  local name="$1"
  local app_name="$2"
  local regex="$3"
  local app_paths
  local app_path_text
  local installed
  local hal_matches
  local hal_count
  local launch_matches
  local sleep_matches
  local process_summary

  app_paths="$(find_app_paths "$app_name" | sort | paste -sd'|' -)"
  if [[ -n "$app_paths" ]]; then
    installed=true
    app_path_text="$app_paths"
  else
    installed=false
    app_path_text=none
  fi

  hal_matches="$(hal_matches_for_regex "$regex" | sort | paste -sd'|' -)"
  if [[ -n "$hal_matches" ]]; then
    hal_count="$(tr '|' '\n' <<< "$hal_matches" | grep -c .)"
  else
    hal_count=0
    hal_matches=none
  fi

  launch_matches="$(line_count_for_regex "$launchctl_file" "$regex")"
  sleep_matches="$(line_count_for_regex "$pmset_file" "$regex")"
  process_summary="$(process_summary_for_regex "$regex")"

  printf 'audioCompetitor app=%s installed=%s appPaths=%s %s launchMatches=%s halMatches=%s halPaths=%s sleepAssertions=%s\n' \
    "$name" \
    "$installed" \
    "$app_path_text" \
    "$process_summary" \
    "$launch_matches" \
    "$hal_count" \
    "$hal_matches" \
    "$sleep_matches"
}

report_product "SoundSource" "SoundSource" "SoundSource|Rogue Amoeba|ACE\\.driver|com\\.rogueamoeba"
report_product "FineTune" "FineTune" "FineTune"
report_product "superwhisper" "superwhisper" "superwhisper|WhisperKit"
