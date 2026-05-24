# MiniMix Roadmap

## Phase 0: Baseline and Design

- Document scope, non-goals, and benchmark protocol.
- Capture baseline measurements for SoundSource and FineTune.
- Confirm Core Audio process-tap permissions and teardown behavior on this Mac.

Exit criteria:
- Benchmark script produces repeatable local artifacts.
- We have measured SoundSource and FineTune under idle and active playback.

## Phase 1: Detection-Only Prototype

- Swift/AppKit menu bar app.
- Detect apps currently producing audio via Core Audio process state.
- Show app name, bundle identifier, process object ID, and running-output state.
- Auto-refresh the open menu at a low rate so newly active audio apps appear without pressing Refresh.
- No audio modification.

Exit criteria:
- MiniMix appears in menu bar.
- Active audio apps appear and disappear reliably.
- Running apps can be shown manually for pre-configuring rules.
- Idle overhead is measured below the current release target.

## Phase 2: Single-App Gain

- Create one Core Audio process tap for one selected app.
- Apply volume and mute.
- Tear down tap when volume returns to default.
- Persist one rule.
- Validate app filtering, All Apps mode, and persisted rule reload with `scripts/probe-app-state.sh`.
- Validate packaged app filtering, All Apps mode, and persisted rule reload with `scripts/probe-packaged-app-state-launchservices.sh`.
- Validate packaged app quit/relaunch recovery with `scripts/probe-packaged-app-relaunch-launchservices.sh`.
- Validate default-rule no-op behavior with `scripts/probe-app-engine-default-noop.sh`.
- Validate packaged default-rule no-op behavior with `scripts/probe-packaged-default-noop-launchservices.sh`.
- Validate with `scripts/probe-single-app-gain.sh`.
- Validate app-engine lifecycle with `scripts/probe-app-engine-gain.sh`.
- Validate app-engine mute lifecycle with `scripts/probe-app-engine-mute.sh`.
- Validate packaged mute/unmute teardown with `scripts/probe-packaged-mute-launchservices.sh`.
- Validate mixer-controller rule lifecycle with `scripts/probe-controller-gain.sh`.
- Validate packaged single-app gain/reset lifecycle with `scripts/probe-packaged-single-app-gain-launchservices.sh`.
- Validate multi-session engine lifecycle with `scripts/probe-multi-app-gain.sh`.
- Validate packaged multi-app gain/teardown lifecycle with `scripts/probe-packaged-multi-app-gain-launchservices.sh`.
- Validate packaged app UI lifecycle with `MINIMIX_RUN_UI_PROBES=1 scripts/probe-packaged-ui-gain.sh`.
- Restart active sessions on default output-device changes.
- Validate packaged output-device restart recovery with `scripts/probe-packaged-output-device-restart-launchservices.sh`.

Exit criteria:
- Chrome or Music can be lowered/muted without affecting system volume.
- Returning to 100% unmuted removes the tap.
- Menubar slider/reset path is validated with a visible active audio app.
- Sleep assertions remain clean.

Current local evidence:
- `scripts/validate-noninteractive-mvp.sh` passes the local noninteractive MVP gate.
- `scripts/probe-app-state.sh` proves active-only filtering, All Apps visibility, UserDefaults persistence by bundle ID, and reset removal.
- `scripts/probe-app-relaunch.sh` proves a saved rule is removed when an app disappears, reapplied to the relaunched process, and cleared on reset.
- `scripts/probe-output-device-restart.sh` proves active Core Audio sessions survive the engine's default-output-device restart path and tear down cleanly.
- `scripts/capture-minimix-active-benchmark.sh release 30 0.35` captures CPU/RSS while MiniMix actively manages a silent per-app audio session.
- QuickTime Player was detected while actively producing output.
- Lowering its slider in the packaged app created 1 active MiniMix tap.
- Reset returned the slider to 100% and removed the tap.
- Post-quit Core Audio tap list returned count 0.
- Silent probe scripts validate tap lifecycle without audible test playback.
- `scripts/probe-multi-app-gain.sh 0.35 0.55` validates two simultaneous managed Core Audio sessions and clean one-at-a-time teardown.
- `MINIMIX_RUN_UI_PROBES=1 scripts/probe-packaged-ui-gain.sh release` validates the real packaged UI path with silent QuickTime playback. It is opt-in because it opens and clicks the MiniMix panel.
- AppKit release smoke after 6s idle measured `0.0% CPU` and `45920 KB RSS`.

## Phase 3: Multi-App MVP

- Support multiple managed apps.
- Persist rules by bundle ID.
- Handle app quit/relaunch. Deterministic relaunch recovery harness is passing; broader daily-driver validation remains.
- Handle default output device changes. The engine restart path has deterministic coverage; real AirPods/Bluetooth switch validation remains in the local test matrix.
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

Current local gate also proves default 100% rules do not create processing, mute rules persist, and unmuting back to 100% removes the rule/session.

Exit criteria:
- Public release can be tested by other macOS users.
- Known limitations are documented.

## Phase 5: Voice Input Experiment

- Add a global push-to-talk path.
- Duck selected managed apps while recording.
- Capture microphone audio with `AVAudioEngine`.
- Keep `STTEngine` unloaded while recording, then transcribe through the swappable protocol after capture stops.
- Insert text into the focused app.
- Restore ducked app volumes immediately when capture ends.
- Register `Control-Option-Space` as the first hold-to-talk shortcut.
- Keep the menubar panel non-activating so opening MiniMix does not steal keyboard focus from the active app.
- Validate panel focus policy with `scripts/probe-panel-focus-policy.sh`.
- Validate real hotkey registration and release with `scripts/probe-hotkey-registration.sh`.
- Validate packaged hotkey registration and release with `scripts/probe-packaged-hotkey-registration-launchservices.sh`.
- Validate deterministic duck/transcribe/insert flow with `scripts/probe-voice-flow.sh`.
- Validate shutdown while recording restores ducking, stops the recorder, and avoids STT/paste with `scripts/probe-voice-shutdown.sh`.
- Validate shutdown during microphone startup resolves the in-flight recorder task and avoids STT/paste with `scripts/probe-voice-shutdown-during-start.sh`.
- Validate early push-to-talk release during mic startup with `scripts/probe-voice-early-release.sh`.
- Validate the actual hotkey callback path for early release during mic startup with `scripts/probe-voice-hotkey-early-release.sh`.
- Validate microphone startup failure cleanup with `scripts/probe-voice-recorder-failure.sh`.
- Validate real `MicrophoneRecorder` capture when mic permission is already granted with `scripts/probe-microphone-recorder.sh`.
- Validate STT failure cleanup with `scripts/probe-voice-stt-failure.sh`.
- Validate paste failure cleanup with `scripts/probe-voice-paste-failure.sh`.
- Validate Accessibility readiness for real text insertion without posting paste events with `scripts/probe-text-injector-readiness.sh`.
- Validate the deterministic voice duck/restore/insert path through the packaged app identity with `scripts/probe-packaged-voice-flow-launchservices.sh`.
- Validate packaged token-gated start cleanup when microphone permission is missing with `scripts/probe-packaged-automation-denied-start-launchservices.sh`.
- Validate packaged permission status without changing TCC grants with `scripts/probe-packaged-voice-permissions-launchservices.sh`.
- Validate packaged Mic, Speech, and Accessibility readiness individually with `scripts/probe-packaged-microphone-recorder-launchservices.sh`, `scripts/probe-packaged-apple-speech-baseline-launchservices.sh`, and `scripts/probe-packaged-text-injector-readiness-launchservices.sh`.
- Gate live voice testing with `scripts/probe-live-voice-readiness.sh`.

Exit criteria:
- Voice input can be used from another app without opening a MiniMix window.
- Ducking starts immediately on push-to-talk press and restores reliably, including early release during startup.
- Microphone startup failures leave audio restored, no text inserted, and STT unloaded.
- STT failures after capture stop leave audio restored, no text inserted, and STT unloaded.
- Paste failures leave audio restored, no text inserted, and STT unloaded.
- The STT engine is inactive when not recording/transcribing.
- Mixer-only idle overhead remains within the original target.
- Packaged app clearly reports mic, Speech, and Accessibility readiness before live voice testing.
- Live microphone/Speech/paste testing starts only after the packaged app reports `liveVoiceReady=true`.

## Voice Input Non-Goals for First Experiment

- Always-listening wake word.
- Meeting bot behavior.
- Long-term transcript library.
- Cloud STT by default.
- Agent workflows.
- Proprietary app cloning.

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

These remain mixer-v1 non-goals. Voice input is a later experiment only after the core mixer proves it can beat the reference apps on idle overhead and reliability.
