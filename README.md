# MiniMix

Ultra-lightweight macOS menu bar app for per-app volume and mute control, built in Swift with Core Audio process taps.

MiniMix is intentionally narrow. It is not trying to replace every SoundSource or FineTune feature. The goal is to provide the smallest reliable tool for independent app volume control with minimal idle overhead.

The current prototype also includes a first push-to-talk voice path because MiniMix can connect microphone capture and per-app ducking in one lightweight process. It registers `Control-Option-Space` as a hold-to-talk shortcut when available, ducks managed apps while recording, restores them on stop, and routes transcription through a swappable `STTEngine`.

The UI is an AppKit menu bar status item with a lightweight panel rather than SwiftUI. That keeps the release idle footprint below the current 50 MB target while preserving an accessibility-visible surface for local automation.

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

Local MVP work is underway. The packaged app can detect an active audio app, lower it through a Core Audio process tap, and reset it back to no active MiniMix tap. The deterministic voice harness proves ducking, restore, transcript insertion, STT unload after stop, and tap cleanup without requiring live privacy prompts.

Local audio probes use a generated silent CAF fixture by default so validation does not play audible test sounds.

See [ROADMAP.md](ROADMAP.md) and [docs/BENCHMARKING.md](docs/BENCHMARKING.md).

Voice input research is tracked in [docs/VOICE_INPUT_RESEARCH.md](docs/VOICE_INPUT_RESEARCH.md).
Core Audio engine notes are tracked in [docs/CORE_AUDIO_ENGINE.md](docs/CORE_AUDIO_ENGINE.md).

## Local Build

```sh
swift build
scripts/build-app-bundle.sh debug
open build/MiniMix.app
```

By default the local app bundle is ad-hoc signed. For more stable macOS privacy permission testing, set a persistent local signing identity:

```sh
security find-identity -v -p codesigning
scripts/setup-local-codesign-identity.sh
MINIMIX_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app-bundle.sh release
```

Ad-hoc signing is enough for mixer validation, but packaged Mic, Speech, and Accessibility grants are more repeatable with a stable Apple Development identity.
If no Apple Development identity is installed, `scripts/setup-local-codesign-identity.sh --install` can create a local self-signed development identity for this Mac. Run the script without `--install` first; install mode modifies the login keychain and may prompt for trust approval. Once `MiniMix Local Code Signing` exists, `scripts/build-app-bundle.sh` auto-selects it when `MINIMIX_CODESIGN_IDENTITY` is not set.

## Local Validation

Default MVP status audit:

```sh
scripts/report-mvp-acceptance.sh
scripts/audit-mvp-status.sh
scripts/audit-mvp-status.sh --configuration release
scripts/validate-single-app-gain-mvp.sh
scripts/validate-silent-core-mvp.sh
scripts/probe-coreaudio-residue.sh
```

Full silent end-to-end gate:

```sh
scripts/validate-noninteractive-mvp.sh
```

Individual probes:

```sh
scripts/probe-single-app-gain.sh 0.35
scripts/probe-app-state.sh
scripts/probe-packaged-app-state-launchservices.sh release
scripts/probe-panel-focus-policy.sh
scripts/probe-app-relaunch.sh
scripts/probe-packaged-app-relaunch-launchservices.sh release
scripts/probe-app-engine-default-noop.sh
scripts/probe-packaged-default-noop-launchservices.sh release
scripts/probe-app-engine-gain.sh 0.35
scripts/probe-app-engine-mute.sh
scripts/probe-packaged-mute-launchservices.sh release
scripts/probe-controller-gain.sh 0.35
scripts/validate-single-app-gain-mvp.sh 0.35
scripts/probe-packaged-single-app-gain-launchservices.sh release 0.35
scripts/probe-output-device-restart.sh 0.35
scripts/probe-packaged-output-device-restart-launchservices.sh release 0.35
scripts/probe-multi-app-gain.sh 0.35 0.55
scripts/probe-packaged-multi-app-gain-launchservices.sh release 0.35 0.55
scripts/probe-hotkey-registration.sh
scripts/probe-packaged-hotkey-registration-launchservices.sh release
scripts/probe-packaged-voice-hotkey-early-release-launchservices.sh release
scripts/probe-voice-flow.sh
scripts/probe-voice-shutdown.sh
scripts/probe-voice-shutdown-during-start.sh
scripts/probe-voice-early-release.sh
scripts/probe-voice-hotkey-early-release.sh
scripts/probe-voice-recorder-failure.sh
scripts/probe-voice-stt-failure.sh
scripts/probe-voice-paste-failure.sh
scripts/probe-microphone-recorder.sh
scripts/probe-packaged-microphone-recorder-launchservices.sh release
scripts/probe-packaged-voice-mic-denied-launchservices.sh release
scripts/probe-packaged-voice-speech-denied-launchservices.sh release
scripts/probe-packaged-voice-accessibility-denied-launchservices.sh release
scripts/probe-packaged-voice-flow-launchservices.sh release
scripts/probe-text-injector-readiness.sh
scripts/probe-packaged-text-injector-readiness-launchservices.sh release
scripts/probe-apple-speech-baseline.sh
scripts/probe-packaged-apple-speech-baseline-launchservices.sh release
scripts/probe-codesign-readiness.sh
scripts/probe-packaged-automation-status.sh release
scripts/probe-packaged-automation-denied-start-launchservices.sh release
scripts/probe-packaged-voice-permissions-launchservices.sh release
scripts/request-packaged-voice-permissions-launchservices.sh release --check-only
scripts/probe-audio-competitor-inventory.sh
MINIMIX_RUN_UI_PROBES=1 scripts/request-packaged-voice-permissions.sh release
MINIMIX_RUN_UI_PROBES=1 scripts/probe-packaged-voice-permissions.sh release
MINIMIX_RUN_UI_PROBES=1 scripts/probe-live-voice-readiness.sh release
scripts/verify-live-voice-mvp.sh release
scripts/probe-live-voice-paste.sh release
MINIMIX_LIVE_VOICE_TRIGGER=hotkey scripts/probe-live-voice-paste.sh release
MINIMIX_LIVE_VOICE_TRIGGER=ui scripts/probe-live-voice-paste.sh release
MINIMIX_RUN_UI_PROBES=1 scripts/probe-packaged-ui-gain.sh release
scripts/capture-minimix-active-benchmark.sh release 30 0.35
```

MiniMix's status panel is implemented as a non-activating panel that cannot become the key or main window, so opening it should not steal keyboard focus from the app you are working in. `scripts/probe-panel-focus-policy.sh` verifies that policy without showing the panel.

Packaged panel automation is opt-in because it opens MiniMix and clicks the UI. Default validation and `scripts/verify-live-voice-mvp.sh release` skip it so they do not steal keyboard or cursor focus while you work. Run `MINIMIX_RUN_UI_PROBES=1 scripts/validate-noninteractive-mvp.sh` only when the machine is idle enough for UI automation.

Headless direct-executable permission diagnostics are not authoritative for packaged app TCC state. macOS can report different mic, Speech, and Accessibility status when the same binary is launched directly versus through `MiniMix.app`. Use `scripts/probe-packaged-voice-permissions-launchservices.sh release` for a background LaunchServices-launched packaged status check that does not open the MiniMix panel; use the opt-in packaged panel probes only when you need to inspect or click UI controls.

Normal record/transcribe/paste runtime paths are passive about macOS privacy. They fail fast when Mic, Speech, or Accessibility is missing instead of requesting TCC prompts. Permission prompts are isolated to the explicit `Permissions` button and `scripts/request-packaged-voice-permissions-launchservices.sh`.

`probe-packaged-app-state-launchservices.sh` proves the packaged app's state rules through LaunchServices: active-only filtering, All Apps visibility, default no-op behavior, mute persistence/removal, persisted rule reload visibility, disappeared-app cleanup, and reset removal.
`probe-packaged-app-relaunch-launchservices.sh` proves the packaged app's rule recovery across app disappearance/relaunch: saved rule application, session removal on disappearance, reapplication to the relaunched process, and reset cleanup.
`probe-packaged-single-app-gain-launchservices.sh` proves the single-app gain/reset path through `MiniMix.app` launched by LaunchServices: active app detection, process tap creation, gain application, rule persistence, reset teardown, and no Core Audio residue.
`probe-live-voice-readiness.sh` is expected to fail until the packaged app has mic, Speech, and Accessibility permissions.
`probe-microphone-recorder.sh` is permission-safe: it checks mic authorization before touching `MicrophoneRecorder.start()`, so it records a short real microphone CAF only when permission is already authorized and otherwise exits pending without prompting.
`probe-packaged-microphone-recorder-launchservices.sh` runs the same microphone recorder proof through `MiniMix.app` launched by LaunchServices, so its mic authorization evidence belongs to the packaged app identity rather than the terminal-launched debug executable.
`probe-packaged-voice-mic-denied-launchservices.sh` proves the packaged app restores ducking and leaves no taps when the real MicrophoneRecorder fails because packaged Mic permission is missing. It exits pending once packaged Mic permission is already authorized.
`probe-packaged-voice-speech-denied-launchservices.sh` proves the packaged app restores ducking, removes the captured file, avoids paste, and leaves no taps when the real Apple Speech engine is denied. It exits pending once packaged Speech permission is already authorized.
`probe-packaged-voice-accessibility-denied-launchservices.sh` proves the packaged app restores ducking, unloads STT, removes the captured file, and leaves no taps when real paste insertion is denied by missing Accessibility trust. It exits pending once packaged Accessibility is already trusted.
`probe-voice-real-recorder-flow.sh` proves `VoiceInputController` can duck app audio, record through the real `MicrophoneRecorder`, hand the captured CAF to a fake STT engine, clean up the recording file, and restore audio without triggering Apple Speech or paste permissions.
`probe-packaged-hotkey-registration-launchservices.sh` proves `Control-Option-Space` can be registered and released by `MiniMix.app` launched through LaunchServices, without opening the panel or synthesizing the shortcut.
`probe-packaged-voice-hotkey-early-release-launchservices.sh` proves the packaged app's push-to-talk callback path ducks immediately, restores immediately on early release during recorder startup, settles idle, unloads STT, and avoids Core Audio residue without opening the panel or using live microphone permissions.
`probe-packaged-voice-flow-launchservices.sh` proves the deterministic voice duck/restore/insert pipeline through `MiniMix.app` launched by LaunchServices with a fake recorder/STT/paste target, so it exercises the packaged app path without mic, Speech, or Accessibility prompts.
`probe-text-injector-readiness.sh` checks Accessibility trust without prompting and without pasting into the focused app.
`probe-packaged-text-injector-readiness-launchservices.sh` runs the same Accessibility readiness check through `MiniMix.app` launched by LaunchServices, so its trust evidence belongs to the packaged app identity without prompting or pasting.
`probe-apple-speech-baseline.sh` is also permission-gated; it exits before requesting authorization until Speech is already authorized.
`probe-packaged-apple-speech-baseline-launchservices.sh` runs the same Apple Speech baseline through `MiniMix.app` launched by LaunchServices, so its Speech authorization evidence belongs to the packaged app identity rather than the terminal-launched debug executable.
`probe-packaged-automation-status.sh` launches the packaged app in the background with an ephemeral automation token, proves untokened automation URLs are ignored, asks it to write a one-line status snapshot through MiniMix automation URL events, and quits without opening the panel or recording.
`probe-packaged-automation-denied-start-launchservices.sh` proves the packaged token-gated start path fails fast and leaves no taps/devices when microphone permission is not granted, without prompting or recording. It exits pending once packaged microphone permission is already authorized.
`probe-packaged-voice-permissions-launchservices.sh` launches `MiniMix.app` in the background through LaunchServices, writes the packaged permission state from the app process, exits immediately, and does not open the MiniMix panel.
`request-packaged-voice-permissions-launchservices.sh` is the preferred opt-in permission request path: it asks the packaged app to request Mic, Speech, and Accessibility without opening the MiniMix panel. It refuses ad-hoc signed builds unless `--allow-adhoc` is passed.
When packaged voice permissions are missing, the MiniMix panel shows a `Permissions` button that requests mic, Speech, and Accessibility access from the app bundle identity.
You can trigger the no-panel request flow with `scripts/request-packaged-voice-permissions-launchservices.sh release`; it does not record, transcribe, paste, or play audio.
Use `scripts/request-packaged-voice-permissions-launchservices.sh release --wait` to request permissions and poll readiness while you approve the macOS prompts after a stable signing identity is configured.
After permissions are granted, `probe-live-voice-paste.sh` is the live packaged-app proof for recording, Apple Speech transcription, and paste into the focused app. It refuses ad-hoc signing unless `--allow-adhoc` is passed, does not play audio, and records only after packaged permissions are ready; speak a short phrase while the script records. The default trigger is `automation`, which launches MiniMix with an ephemeral token and starts/stops dictation through token-gated URL events without opening the panel or synthesizing the global hotkey. After that pipeline proof passes, run `MINIMIX_LIVE_VOICE_TRIGGER=hotkey scripts/probe-live-voice-paste.sh release` to prove the actual push-to-talk hotkey path. If you specifically need to test the panel path, run the same proof with `MINIMIX_LIVE_VOICE_TRIGGER=ui`.

`scripts/verify-live-voice-mvp.sh release` is the safe orchestrator for the final voice proof. Default mode is check-only, does not record, and uses no-panel LaunchServices checks for packaged signing, permissions, packaged Apple Speech readiness, and packaged Accessibility readiness. After stable signing and permissions are ready, run `scripts/verify-live-voice-mvp.sh release --run-live` for the lowest-focus live proof; that mode refuses ad-hoc signing unless `--allow-adhoc` is passed and validates the packaged microphone recorder before opening the live paste target.
`scripts/report-mvp-acceptance.sh` also runs that verifier in default mode and treats the current permission-gated result as pending evidence rather than a hard failure.

Benchmark snapshots can be summarized with:

```sh
scripts/summarize-audio-benchmark.sh benchmarks/20260523-021927-minimix-appkit-idle
```

Compare local MiniMix, SoundSource, FineTune, and superwhisper captures with:

```sh
scripts/compare-audio-benchmarks.sh
```
