# MiniMix Roadmap

## Phase 0: Baseline and Design

- Document scope, non-goals, and benchmark protocol.
- Capture baseline measurements for SoundSource and FineTune.
- Confirm Core Audio process-tap permissions and teardown behavior on this Mac.

Exit criteria:
- Benchmark script produces repeatable local artifacts.
- We have measured SoundSource and FineTune under idle and active playback.

## Phase 1: Detection-Only Prototype

- Swift menu bar app.
- Detect apps currently producing audio.
- Show app name, bundle identifier, process object ID, and running-output state.
- No audio modification.

Exit criteria:
- MiniMix appears in menu bar.
- Active audio apps appear and disappear reliably.
- Idle overhead is measured.

## Phase 2: Single-App Gain

- Create one Core Audio process tap for one selected app.
- Apply volume and mute.
- Tear down tap when volume returns to default.
- Persist one rule.

Exit criteria:
- Chrome or Music can be lowered/muted without affecting system volume.
- Returning to 100% unmuted removes the tap.
- Sleep assertions remain clean.

## Phase 3: Multi-App MVP

- Support multiple managed apps.
- Persist rules by bundle ID.
- Handle app quit/relaunch.
- Handle default output device changes.
- Add a basic diagnostics panel.

Exit criteria:
- Daily-driver usable for Chrome, Teams, Music/Spotify, and Discord.
- Benchmark results beat or match FineTune for idle overhead.
- No helper daemon or HAL driver is installed.

## Phase 4: Public Alpha

- Harden permission flow.
- Add crash-safe cleanup for orphaned taps and aggregate devices.
- Add signed release artifacts.
- Add concise docs and troubleshooting.

Exit criteria:
- Public release can be tested by other macOS users.
- Known limitations are documented.

## Explicit Non-Goals for v1

- EQ.
- Volume boost above unity.
- Per-app output routing.
- Audio meters.
- Global hotkeys.
- On-screen HUD.
- Bluetooth device management.
- DDC monitor volume.
- Driver-based audio capture.
