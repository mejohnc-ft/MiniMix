# MiniMix

Ultra-lightweight macOS menu bar app for per-app volume and mute control, built in Swift with Core Audio process taps.

MiniMix is intentionally narrow. It is not trying to replace every SoundSource or FineTune feature. The goal is to provide the smallest reliable tool for independent app volume control with minimal idle overhead.

## Product Principles

- Menu bar only.
- Per-app volume and mute.
- Persist simple app rules by bundle identifier.
- Create Core Audio process taps only for apps with non-default rules.
- Tear down taps when an app returns to 100% volume and unmuted.
- No custom HAL driver.
- No helper daemon.
- No EQ, boost, output routing, meters, hotkeys, or HUD in v1.
- Clean uninstall: delete the app and its preferences.

## Success Targets

| Scenario | Target |
| --- | --- |
| Idle, no managed apps | ~0% CPU, less than 50 MB RSS |
| One active managed app | less than 1-2% CPU on Apple Silicon |
| Background services | none |
| Installed audio drivers | none |
| Sleep blockers | none |
| Uninstall footprint | app bundle + preferences only |

## Development Status

Repository initialized. See [ROADMAP.md](ROADMAP.md) and [docs/BENCHMARKING.md](docs/BENCHMARKING.md).
