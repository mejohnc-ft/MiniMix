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

Summarize one or more benchmark snapshots:

```sh
scripts/summarize-audio-benchmark.sh benchmarks/20260523-021927-minimix-appkit-idle
```

Compare the latest local MiniMix, SoundSource, FineTune, and superwhisper captures:

```sh
scripts/compare-audio-benchmarks.sh
```

Compare a specific set of captures:

```sh
scripts/compare-audio-benchmarks.sh \
  benchmarks/20260523-021927-minimix-appkit-idle \
  benchmarks/20260522-231734-soundsource-idle \
  benchmarks/20260522-232753-finetune-plus-soundsource-idle \
  benchmarks/20260522-234026-superwhisper-reference-idle
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

Build and smoke MiniMix locally:

```sh
swift build
scripts/build-app-bundle.sh debug
open build/MiniMix.app
```

The bundle is ad-hoc signed by default. For repeatable packaged-app permission testing, use a stable local signing identity:

```sh
security find-identity -v -p codesigning
scripts/setup-local-codesign-identity.sh
MINIMIX_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app-bundle.sh release
```

The audit reports the current code-signing metadata and warns when the app is ad-hoc signed, because packaged Mic, Speech, and Accessibility grants are more repeatable with a stable Apple Development identity.
If this Mac has no Apple Development identity, run `scripts/setup-local-codesign-identity.sh` in read-only mode first. Its `--install` mode creates a local self-signed Code Signing identity for this Mac and may prompt for keychain or trust approval. Once `MiniMix Local Code Signing` exists, `scripts/build-app-bundle.sh` auto-selects it when `MINIMIX_CODESIGN_IDENTITY` is not set.

Run the default MVP status audit. This does not launch QuickTime or play audio:

```sh
scripts/report-mvp-acceptance.sh
scripts/audit-mvp-status.sh
scripts/audit-mvp-status.sh --configuration release
scripts/validate-single-app-gain-mvp.sh
scripts/validate-silent-core-mvp.sh
scripts/probe-panel-focus-policy.sh
```

Capture MiniMix while it is actively managing a silent per-app audio session:

```sh
scripts/capture-minimix-active-benchmark.sh release 30 0.35
```

This runs the packaged MiniMix executable with an active Core Audio benchmark harness, captures CPU/RSS with the standard benchmark sampler, stores the harness log in the benchmark directory, and verifies tap/device cleanup afterward.

The release audit launches MiniMix briefly and verifies idle CPU/RSS against the current less-than-50 MB target.
`report-mvp-acceptance.sh` maps the audit output back to the MVP acceptance criteria and keeps the final result incomplete until live packaged voice paste is proven.
`validate-silent-core-mvp.sh` proves the core mixer path without QuickTime: state/rule persistence, non-stealing panel focus policy, app quit/relaunch recovery with saved rules, default-rule no-op behavior, simulated output-device restart recovery, single-app gain and mute, controller reset teardown, multi-app sessions, hotkey registration, deterministic voice duck/insert, shutdown cancel including in-flight startup, STT unload after stop, and Core Audio residue cleanup.

Run the full noninteractive MVP gate. This uses silent fixtures and skips packaged panel/QuickTime UI automation unless `MINIMIX_RUN_UI_PROBES=1` is set:

```sh
scripts/validate-noninteractive-mvp.sh
```

Probe the single-app Core Audio gain path with a silent audio fixture:

```sh
scripts/probe-app-state.sh
scripts/probe-packaged-app-state-launchservices.sh release
scripts/probe-panel-focus-policy.sh
scripts/probe-app-relaunch.sh
scripts/probe-packaged-app-relaunch-launchservices.sh release
scripts/probe-app-engine-default-noop.sh
scripts/probe-packaged-default-noop-launchservices.sh release
scripts/probe-single-app-gain.sh 0.35
scripts/probe-app-engine-mute.sh
scripts/probe-packaged-mute-launchservices.sh release
```

`probe-packaged-app-state-launchservices.sh` proves active-only filtering, All Apps visibility, default-rule no-op behavior, persisted rule reload visibility, disappeared-app cleanup, and reset removal through `MiniMix.app` launched by LaunchServices.
`probe-packaged-app-relaunch-launchservices.sh` proves saved rule application, disappeared-process cleanup, relaunched-process rule reapplication, and reset cleanup through `MiniMix.app` launched by LaunchServices.
`probe-packaged-default-noop-launchservices.sh` proves a packaged 100% unmuted default rule creates no active session and no extra Core Audio tap.

Probe the app engine lifecycle through the MiniMix binary with the same silent fixture:

```sh
scripts/probe-app-engine-gain.sh 0.35
```

Probe the full mixer-controller rule path through the MiniMix binary:

```sh
scripts/probe-controller-gain.sh 0.35
scripts/validate-single-app-gain-mvp.sh 0.35
scripts/probe-packaged-single-app-gain-launchservices.sh release 0.35
```

`validate-single-app-gain-mvp.sh` is the focused replacement-candidate milestone: it proves an active Core Audio process is detected, the controller creates a real process tap and aggregate device for a non-default rule, applies gain, persists the rule, resets to default, destroys the tap, and leaves no MiniMix Core Audio residue.
`probe-packaged-single-app-gain-launchservices.sh` runs the same controller gain/reset proof through `MiniMix.app` launched by LaunchServices, so the packaged app bundle path proves the core replacement-candidate milestone without panel UI.
`probe-packaged-mute-launchservices.sh` proves the packaged app can create a muted zero-gain process tap and remove it when unmuted back to 100%, without panel UI.

Probe the Core Audio output-device restart path with a silent fixture:

```sh
scripts/probe-output-device-restart.sh 0.35
scripts/probe-packaged-output-device-restart-launchservices.sh release 0.35
```

`probe-packaged-output-device-restart-launchservices.sh` proves the packaged app can recreate its process tap and aggregate device after the engine's output-device restart path, preserve gain, then remove the session cleanly.

Probe two simultaneous managed Core Audio sessions:

```sh
scripts/probe-multi-app-gain.sh 0.35 0.55
scripts/probe-packaged-multi-app-gain-launchservices.sh release 0.35 0.55
```

`probe-packaged-multi-app-gain-launchservices.sh` proves two simultaneous independent process taps/gains and one-at-a-time teardown through `MiniMix.app` launched by LaunchServices, without panel UI.

Probe the voice duck/transcribe/insert flow through the MiniMix binary:

```sh
scripts/probe-hotkey-registration.sh
scripts/probe-packaged-hotkey-registration-launchservices.sh release
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
```

`probe-microphone-recorder.sh` checks mic authorization before touching `MicrophoneRecorder.start()`, so it does not prompt for microphone access. It records a short real microphone CAF only when permission is already authorized; otherwise it exits `66` with a pending status.
`probe-packaged-microphone-recorder-launchservices.sh` checks the microphone recorder path from the packaged app identity through LaunchServices, which is the authoritative microphone TCC context for the final app.
`probe-packaged-voice-mic-denied-launchservices.sh` proves the packaged app restores ducked audio, avoids STT/paste, and leaves no taps when the real microphone recorder is denied by packaged Mic permission. It exits pending once packaged Mic permission is already authorized.
`probe-packaged-voice-speech-denied-launchservices.sh` proves the packaged app restores ducked audio, removes the captured file, avoids paste, and leaves no taps when the real Apple Speech engine is denied. It exits pending once packaged Speech permission is already authorized.
`probe-packaged-voice-accessibility-denied-launchservices.sh` proves the packaged app restores ducked audio, unloads STT, removes the captured file, and leaves no taps when the real paste injector is denied by packaged Accessibility trust. It exits pending once packaged Accessibility is already trusted.
`probe-voice-real-recorder-flow.sh` proves the `VoiceInputController` path around the real microphone recorder while keeping STT and paste mocked, so it does not prompt for Apple Speech or Accessibility and does not paste into the focused app.
`probe-packaged-hotkey-registration-launchservices.sh` proves `Control-Option-Space` registration and release from the packaged app identity through LaunchServices without synthesizing the shortcut.
`probe-packaged-voice-flow-launchservices.sh` proves the deterministic voice duck/restore/insert path from the packaged app identity through LaunchServices while keeping recorder, STT, and paste mocked.
`probe-text-injector-readiness.sh` checks Accessibility trust without prompting and without posting a paste event into the currently focused app.
`probe-packaged-text-injector-readiness-launchservices.sh` checks the same Accessibility readiness from the packaged app identity through LaunchServices, without prompting and without posting a paste event.
`probe-packaged-apple-speech-baseline-launchservices.sh` checks the Apple Speech baseline from the packaged app identity through LaunchServices, which is the authoritative Speech TCC context for the final app.
`probe-packaged-automation-status.sh` proves the packaged no-panel automation status channel used by the lowest-focus live voice trigger, including that untokened automation URLs are ignored.
`probe-packaged-automation-denied-start-launchservices.sh` proves token-gated start dictation fails fast and cleans up with packaged microphone permission missing, without prompting or recording. It exits pending after packaged microphone permission is granted.
`probe-packaged-voice-permissions-launchservices.sh` launches `MiniMix.app` in the background through LaunchServices and captures packaged permission state without opening the MiniMix panel.
`request-packaged-voice-permissions-launchservices.sh` is the preferred opt-in request path because it asks the packaged app to request Mic, Speech, and Accessibility without opening the MiniMix panel.
Normal MiniMix runtime voice paths do not request TCC prompts. Microphone capture, Apple Speech transcription, and text insertion fail fast when permission is missing; only the explicit permission requester path prompts.
`probe-audio-competitor-inventory.sh` is read-only and reports whether SoundSource, FineTune, and superwhisper are installed/running, plus matching launch items, HAL plugins, and sleep assertions.

Request packaged app voice permissions without starting dictation:

```sh
scripts/request-packaged-voice-permissions-launchservices.sh release
scripts/request-packaged-voice-permissions-launchservices.sh release --wait
```

The request script refuses ad-hoc signed builds unless `--allow-adhoc` is passed. Configure a stable identity first for repeatable packaged TCC grants.

Probe the packaged app UI path end to end with silent QuickTime playback:

```sh
MINIMIX_RUN_UI_PROBES=1 scripts/probe-packaged-voice-permissions.sh release
MINIMIX_RUN_UI_PROBES=1 scripts/probe-live-voice-readiness.sh release
MINIMIX_RUN_UI_PROBES=1 scripts/probe-packaged-ui-gain.sh release
```

Packaged panel automation is opt-in because it opens the menubar panel, launches silent QuickTime playback, and clicks/sets UI controls. Default `scripts/validate-noninteractive-mvp.sh`, `scripts/report-mvp-acceptance.sh --full`, and `scripts/verify-live-voice-mvp.sh release` skip those panel probes unless `MINIMIX_RUN_UI_PROBES=1` is set.

Do not use direct-executable headless TCC checks as packaged app readiness evidence. They can reflect Terminal/process grants instead of LaunchServices `MiniMix.app` grants. Prefer `scripts/probe-packaged-voice-permissions-launchservices.sh release` for a no-panel packaged status check; `scripts/probe-live-voice-readiness.sh release` uses that no-panel packaged check by default and switches to panel automation only when `MINIMIX_RUN_UI_PROBES=1` is set.

After packaged app permissions are granted, prove the real push-to-talk voice path with TextEdit focused:

```sh
scripts/verify-live-voice-mvp.sh release
scripts/verify-live-voice-mvp.sh release --run-live
scripts/verify-live-voice-mvp.sh release --run-live --trigger hotkey
scripts/probe-live-voice-paste.sh release
```

`probe-live-voice-paste.sh` does not play audio. It opens a blank TextEdit document, records for `MINIMIX_LIVE_VOICE_SECONDS` seconds, and verifies that Apple Speech output was pasted into TextEdit. Speak a short phrase while the script is recording. The default `automation` trigger is the lowest-focus path; it launches MiniMix with an ephemeral token and starts/stops dictation through token-gated URL events without opening the panel or synthesizing the global hotkey. After that pipeline proof passes, run `MINIMIX_LIVE_VOICE_TRIGGER=hotkey scripts/probe-live-voice-paste.sh release` to prove the actual push-to-talk hotkey path.
`verify-live-voice-mvp.sh` is the preferred final orchestrator: default mode checks signing, packaged permission state, packaged Apple Speech, and packaged Accessibility without opening the MiniMix panel or recording. `--run-live` records and proves paste only after readiness is true, and it validates the packaged microphone recorder immediately before the live paste run.
`report-mvp-acceptance.sh` includes the same default verifier preflight, so the acceptance report covers the final live proof command while keeping the permission-gated state pending.

Use the UI-trigger fallback only when you specifically need to prove the same packaged record/transcribe/paste pipeline through MiniMix's Start/Stop buttons:

```sh
scripts/verify-live-voice-mvp.sh release --run-live --trigger ui
MINIMIX_LIVE_VOICE_TRIGGER=ui scripts/probe-live-voice-paste.sh release
```

The probe scripts generate `/tmp/minimix-silent-fixture.caf` by default through `scripts/ensure-silent-audio-fixture.sh`. Pass a sound path as the second argument only when audible validation is intentionally needed.

Latest local proof:

```text
stateHarness initialVisible=1 allAppsVisible=2 defaultRuleNoop=true mutePersisted=true unmuteRemovedRule=true persistedVolume=0.42 disappearedRemovedSession=true reloadedRuleVisible=true resetRemovedRule=true
panelFocusHarness nonactivating=true cannotBecomeKey=true cannotBecomeMain=true hidesOnDeactivate=false becomesKeyOnlyIfNeeded=true
processObjectID=191 tapID=193 aggregateID=194 callbacks=89 gain=0.35
defaultNoopHarness activeAfterDefault=0 tapCountBefore=0 tapCountAfterDefault=0
gainHarness activeAfterApply=1 activeAfterRemove=0 tapCount=0 gain=0.35
muteHarness activeAfterMute=1 muted=true gain=0.0 activeAfterUnmute=0 tapCount=0
controllerHarness detectedApps=1 activeAfterVolume=1 activeAfterReset=0 tapCount=0 gain=0.35
multiHarness activeAfterApply=2 activeAfterFirstRemove=1 activeAfterSecondRemove=0 tapCount=0 gains=0.35,0.55
hotkeyHarness registered=true reusableAfterStop=true pressCount=0 releaseCount=0
voiceHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0 insertedText=MiniMix voice harness sttLoadedAfterStop=false tapCount=0
voiceShutdownHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeWhileRecording=1 duckedVolume=0.35 activeAfterShutdown=0 restoredVolume=1.0 status=idle recorderStarted=true recorderStopped=true sttLoadedAfterShutdown=false insertedText=nil recordingFileExists=false
voiceShutdownDuringStartHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 immediateStatus=idle activeAfterShutdown=0 restoredVolume=1.0 status=idle recorderStarted=true recorderStopped=true sttLoadedAfterShutdown=false insertedText=nil recordingFileExists=false
voiceEarlyReleaseHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeAfterEarlyRelease=0 volumeAfterEarlyRelease=1.0 activeAfterSettled=0 restoredVolume=1.0 status=idle insertedText=MiniMix early release harness sttLoadedAfterStop=false
voiceRecorderFailureHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeAfterFailure=0 restoredVolume=1.0 status=idle insertedText=nil sttLoadedAfterFailure=false error=Harness recorder start failed.
voiceSTTFailureHarness activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0 status=idle insertedText=nil sttLoadedAfterStop=false error=Harness STT load failed.
voicePasteFailureHarness activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0 status=idle attemptedText=MiniMix paste failure harness insertedText=nil sttLoadedAfterStop=false error=Harness paste failed.
microphoneRecorderHarness ready=false status=notDetermined
textInjectorHarness ready=false accessibility=notTrusted action=readinessOnly
appleSpeechHarness ready=false status=notDetermined
packagedVoicePermissions MiniMix, Listening for active app audio, App Audio, All Apps, No active audio apps yet., Voice Input, Idle, Hold Control-Option-Space, Needs: Mic, Speech, Accessibility, Mic Not requested · Speech Not requested · Accessibility Not trusted, No active MiniMix taps
liveVoiceReady=false reason=packaged app still needs mic, Speech, or Accessibility permission
packagedUI detected=QuickTime loweredTo=35% loweredTap=1 resetTap=0 tapListStatus=0/0 count=0 taps=[]
noninteractiveMVP ok
```

Latest menubar UI validation:

```text
Packaged MiniMix.app launched from build/MiniMix.app
Menu opened before playback: No active audio apps yet.
QuickTime Player started silent CAF playback while the menu remained open
MiniMix auto-refresh detected QuickTime Player without pressing Refresh
QuickTime Player row included com.apple.QuickTimePlayerX and active audio
slider decremented below 100%
MiniMix footer reported 1 active tap
reset returned slider to 100%
MiniMix footer reported No active MiniMix taps
post-test tap list count=0
```

Latest packaged app permission state:

```text
Needs: Mic, Speech, Accessibility
```

That is expected until the signed app bundle itself is granted privacy permissions. Terminal-level permission checks are not enough for the packaged app.
When permissions are missing, the packaged MiniMix panel exposes a `Permissions` button that requests microphone, Speech recognition, and Accessibility access for the app bundle without starting dictation.
The same flow can be launched from the terminal with `scripts/request-packaged-voice-permissions.sh release`; add `--wait` to poll readiness while you approve the macOS prompts. Configure a stable signing identity first, or pass `--allow-adhoc` only when intentionally testing the current ad-hoc build.
The remaining live proof is `probe-live-voice-paste.sh release`, which is expected to exit early until those permissions are ready.

Inspect Core Audio process taps:

```sh
scripts/probe-coreaudio-residue.sh
xcrun swift -e 'import CoreAudio; var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTapList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain); var size: UInt32 = 0; let s1 = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size); var taps = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size); let s2 = taps.withUnsafeMutableBufferPointer { buffer in buffer.baseAddress == nil ? noErr : AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer.baseAddress!) }; print("tapListStatus=\\(s1)/\\(s2) count=\\(taps.count) taps=\\(taps)")'
```

`probe-coreaudio-residue.sh` reports both active process taps and MiniMix-named/UID audio devices, so it catches leaked private aggregate devices as well as leaked taps.

Latest local idle benchmark after engine wiring:

```text
SwiftUI menubar release smoke after 6s idle: %CPU=0.0 RSS=72512 KB
AppKit status-panel release smoke after 6s idle: %CPU=0.0 RSS=45920 KB
AppKit status-panel full-gate release idle check: %CPU=0.0 RSS=45840 KB
Latest full-gate release idle check: %CPU=0.0 RSS=45824 KB, MiniMix process count=1
Latest full-gate release idle check after benchmark tooling: %CPU=0.0 RSS=45936 KB, MiniMix process count=1
Latest full-gate release idle check after lifecycle harness: %CPU=0.0 RSS=45856 KB, MiniMix process count=1
Latest full-gate release idle check after Apple Speech harness: %CPU=0.0 RSS=46112 KB, MiniMix process count=1
Latest full-gate release idle check after hotkey harness: %CPU=0.0 RSS=45936 KB, MiniMix process count=1
```

The AppKit status-panel build currently meets the release RSS target of less than 50 MB while keeping the menu UI accessible to System Events for automated validation.

Latest captured AppKit idle benchmark summary:

```text
== benchmarks/20260523-021927-minimix-appkit-idle ==
MiniMix samples=5 avg_cpu=0.06 max_cpu=0.30 avg_rss=43.2M max_rss=44.8M pids=1
MiniMix HAL drivers: none
MiniMix sleep assertions: none
```

Latest comparison report:

```text
minimix-appkit-idle                        MiniMix                    5     0.06     0.30     43.2M     44.8M     1
soundsource-idle                           SoundSource               12     3.92    20.40    159.2M    159.9M     1
soundsource-active-afplay                  SoundSource                6     6.55     9.00    173.6M    174.3M     1
finetune-plus-soundsource-idle             FineTune                  12     0.03     0.20    103.6M    128.9M     1
finetune-plus-soundsource-active-afplay    FineTune                   6    17.60    23.60    134.7M    135.0M     1
superwhisper-reference-idle                superwhisper               5     2.04     4.80    117.3M    117.5M     1
```

The latest MiniMix capture was not a clean-room run: SoundSource, ARK, Background Music, and superwhisper processes were also resident. Use the MiniMix process row for MiniMix CPU/RSS, and recapture after quitting other comparison apps when clean baseline numbers are required.

## Notes

FineTune is GPLv3. Do not copy code from it into MiniMix unless MiniMix is intentionally relicensed as GPLv3. SonicFlow is MIT licensed and can be used as a reference or upstream contribution target, but copied code still needs attribution and review.
