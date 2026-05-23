# Benchmarking MiniMix

MiniMix should be judged against SoundSource and FineTune with repeatable measurements, not subjective speed alone.

## Competitors

- SoundSource: commercial full-featured audio control app using Rogue Amoeba ARK.
- FineTune: open-source full-featured Swift app with per-app volume, routing, EQ, AutoEQ, hotkeys, HUD, and device controls.
- SonicFlow: open-source small Swift/Core Audio process-tap app useful as an architectural reference.

## What We Measure

| Metric | Why It Matters |
| --- | --- |
| Process count | Shows whether the app needs helpers or daemons. |
| Resident memory | Captures idle footprint. |
| CPU while idle | Should be approximately zero when no rules are active. |
| CPU while managing audio | Captures realtime processing cost. |
| Sleep assertions | Detects apps preventing idle sleep. |
| Installed HAL drivers | Tracks audio-stack complexity. |
| Launch agents/daemons | Tracks always-on system footprint. |
| Audio reliability | Device changes, sleep/wake, app relaunch, Bluetooth. |

## Local Test Matrix

Run each app in the same scenarios:

1. Fresh boot, app not launched.
2. App launched, no audio playing.
3. Chrome playing audio, no per-app rule.
4. Chrome playing audio at 50%.
5. Chrome plus Teams or Discord active.
6. Sleep/wake after an active managed app.
7. Bluetooth or AirPods output switch.
8. App quit and relaunch with saved rules.

## Target Results

| Scenario | MiniMix Target |
| --- | --- |
| Not launched | zero footprint |
| Launched idle | less than 50 MB RSS, ~0% CPU |
| No managed apps | no process taps, no aggregate device |
| One managed app | less than 1-2% CPU |
| Rule removed | process tap destroyed |
| Sleep/wake | no stuck sleep assertions |
| Uninstall | no driver/helper cleanup required |

## Commands

Capture a benchmark snapshot:

```sh
scripts/capture-audio-benchmark.sh minimix-idle 60
scripts/capture-audio-benchmark.sh soundsource-idle 60
scripts/capture-audio-benchmark.sh finetune-idle 60
```

Inspect audio drivers:

```sh
system_profiler SPAudioDataType
find /Library/Audio/Plug-Ins/HAL -maxdepth 2 -type d -print
```

Inspect sleep blockers:

```sh
pmset -g assertions
pmset -g log | rg -i 'PreventUserIdle|DarkWake|Wake from|Entering Sleep|audio'
```

Inspect process footprint:

```sh
ps -axo pid,ppid,%cpu,%mem,rss,comm,args | rg -i 'MiniMix|FineTune|SoundSource|arkaudiod|coreaudiod'
```

## Notes

FineTune is GPLv3. Do not copy code from it into MiniMix unless MiniMix is intentionally relicensed as GPLv3. SonicFlow is MIT licensed and can be used as a reference or upstream contribution target, but copied code still needs attribution and review.
