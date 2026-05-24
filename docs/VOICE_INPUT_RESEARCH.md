# MiniMix Voice Input Research

## Purpose

MiniMix started as a narrow per-app mixer. Voice input is worth evaluating because mixer state and microphone state are naturally related: when the user is speaking, MiniMix can immediately duck selected app audio, record, transcribe, insert text, and restore audio without a second app guessing what happened.

This document is for product and architecture research. MiniMix should not copy proprietary code, assets, prompts, model files, or UI from commercial apps. The goal is to rebuild the useful workflow from first principles with a smaller, native implementation.

## Local Reference: superwhisper

Observed on this Mac:

- App bundle: `/Applications/superwhisper.app`
- Bundle identifier: `com.superduper.superwhisper`
- Version: `2.13.2`
- App size: about `132 MB`
- User data/model footprint: about `1.4 GB`
- Entitlements:
  - microphone/audio input
  - Apple Events automation
- Usage strings:
  - microphone recording
  - Accessibility/Apple Events for pasting into focused fields
- URL schemes:
  - `superwhisper://`
  - `superwhisper-debug://`
- Bundled inference/runtime signals:
  - `libllama`
  - `libggml`
  - `libggml-metal`
  - `libonnxruntime`
  - `ArgmaxSDK`
  - chat template resources for several local/open model families
- Local user models observed:
  - `ggml-small.en.bin`, about `465 MB`
  - `vad-v1.onnx`, about `2.2 MB`
  - `seg-v1.onnx`, about `5.6 MB`
  - `emb-v1.onnx`, about `25 MB`

Inferred pipeline:

```text
hotkey / UI trigger
 -> microphone capture
 -> VAD / segmentation
 -> local or cloud speech-to-text
 -> optional LLM rewrite / formatting mode
 -> insertion into focused app via Accessibility / Apple Events / pasteboard
 -> history and model management
```

What is worth copying conceptually:

- Press/hold or toggle voice capture from anywhere.
- Fast start and stop sounds/visual status.
- Local-first transcription with optional cloud or bring-your-own-key later.
- Mode-based cleanup: raw transcript, clean note, email, terminal-safe text, etc.
- Text insertion into the active app.

What MiniMix can do better:

- Own ducking and voice capture in one process.
- Duck only selected apps, not the entire system.
- Restore audio immediately when capture ends.
- Avoid always-on helper daemons and audio drivers.
- Keep idle voice overhead near zero by loading STT only when needed.

## OSS Reference Space

The open-source macOS dictation space is active. Relevant projects and patterns to study:

- WhisperKit-based native Swift apps for local transcription.
- whisper.cpp/ggml based apps for broad model compatibility.
- Apps using Apple Speech as a low-footprint built-in engine option.
- BYOK cloud engines for users who prefer speed or accuracy over local-only privacy.

Promising implementation ingredients:

- `AVAudioEngine` for microphone capture.
- `KeyboardShortcuts` or Carbon event hotkeys for global push-to-talk.
- `WhisperKit` for a native Swift local engine.
- `whisper.cpp` only if model compatibility or smaller integration risk beats Swift-native ergonomics.
- `Accessibility` APIs or pasteboard plus synthetic paste for insertion.
- A local `STTEngine` protocol so engines can be swapped without touching mixer code.

## Local Model Options

MiniMix should start with a swappable engine interface and avoid hard-wiring the first model choice into the product. The practical local options are:

| Engine | Fit for MiniMix | Strengths | Costs / Risks |
| --- | --- | --- | --- |
| Apple Speech / SpeechAnalyzer | Best low-footprint first experiment if quality is acceptable | Native framework, smallest app footprint, no bundled model management | OS-version constraints, less control over model behavior, Apple API limits |
| WhisperKit / Argmax OSS | Best Swift-native Whisper path | Core ML integration, good Apple Silicon fit, established macOS/iOS usage | Model downloads/cache, memory bursts, accuracy/speed depends heavily on model size |
| FluidAudio / Parakeet Core ML | Best candidate for fast modern local ASR | Swift/Core ML focused, Parakeet ASR, VAD/diarization ecosystem | Younger dependency, model compatibility changes, licensing/model attribution needs review |
| whisper.cpp / ggml | Best portability and mature model ecosystem | Battle-tested, broad model support, no Apple-only lock-in | C/C++ integration, binary/runtime complexity, less native than Core ML paths |
| ONNX Runtime | Useful for VAD/segmentation, not ideal as the first full ASR path | Good for small helper models like VAD | Extra runtime footprint, not as clean as native Swift/Core ML for MiniMix |

Recommended sequence:

1. Build `STTEngine` around recorded audio and transcript output only.
2. Prototype Apple Speech/SpeechAnalyzer for the smallest possible proof.
3. Prototype WhisperKit and FluidAudio behind the same interface.
4. Benchmark cold start, warm start, transcription speed, RSS, CPU, and battery impact.
5. Pick one default local engine and keep others experimental.

For the MiniMix product, the engine should be inactive unless the user is recording or within a short warm-cache window. The mixer should never pay STT model cost while idle.

## Current Prototype Choice

The first MiniMix voice proof uses Apple Speech through the `STTEngine` protocol. This is intentionally not the final model decision. It gives us a lowest-footprint baseline before pulling in WhisperKit, FluidAudio, Parakeet, or whisper.cpp.

Why this comes first:

- no bundled model files
- no third-party runtime
- easiest cold-start and idle benchmark
- native permission model
- useful baseline for deciding whether local model downloads are worth it

Known limitations:

- quality and language behavior are controlled by Apple
- on-device availability depends on OS support and locale
- file-based transcription is simpler than streaming but adds a stop-then-transcribe step
- insertion still needs Accessibility trust for automatic paste

The next model experiment should compare Apple Speech against WhisperKit and FluidAudio using the same `STTEngine` interface.

## Mixer Integration Status

MiniMix now has enough mixer state to support the voice workflow shape:

- active output detection uses Core Audio process state
- saved rules survive app refreshes
- ducking snapshots previous app volume/mute state
- push-to-talk press ducks managed apps before async mic/STT startup
- microphone capture starts before the STT engine is loaded
- recording stop restores ducked audio immediately before transcription finishes
- early push-to-talk release during mic startup restores immediately and settles idle
- microphone startup failure restores audio, inserts no text, and never loads STT
- STT failure after capture stop restores audio, inserts no text, and unloads STT
- paste failure after transcription restores audio, reports an error, and unloads STT
- global push-to-talk is registered as `Control-Option-Space`
- the voice harnesses verify immediate ducking, early-release restore, transcript insertion, STT-failure cleanup, STT unload, and tap cleanup

The deterministic voice proof runs without live microphone/Speech/Accessibility prompts:

```sh
scripts/probe-hotkey-registration.sh
scripts/probe-voice-flow.sh
scripts/probe-voice-shutdown.sh
scripts/probe-voice-shutdown-during-start.sh
scripts/probe-voice-early-release.sh
scripts/probe-voice-recorder-failure.sh
scripts/probe-voice-stt-failure.sh
scripts/probe-voice-paste-failure.sh
```

The harness now uses the generated silent CAF fixture by default, so it still exercises Core Audio ducking without playing an audible test sound.

The packaged app voice permission panel can be checked without requesting or granting permissions:

```sh
scripts/probe-apple-speech-baseline.sh
scripts/probe-microphone-recorder.sh
scripts/probe-text-injector-readiness.sh
MINIMIX_RUN_UI_PROBES=1 scripts/probe-packaged-voice-permissions.sh release
MINIMIX_RUN_UI_PROBES=1 scripts/probe-live-voice-readiness.sh release
```

Directly launching `MiniMix.app/Contents/MacOS/MiniMix` for a headless permission diagnostic is intentionally treated as non-authoritative because macOS TCC can attach different grants to the process launch context than to the packaged app identity.

Current local proof:

```text
appleSpeechHarness ready=false status=notDetermined
microphoneRecorderHarness ready=false status=notDetermined
textInjectorHarness ready=false accessibility=notTrusted action=readinessOnly
packagedVoicePermissions ... Needs: Mic, Speech, Accessibility, Mic Not requested · Speech Not requested · Accessibility Not trusted ...
liveVoiceReady=false reason=packaged app still needs mic, Speech, or Accessibility permission
```

`scripts/probe-apple-speech-baseline.sh` refuses to call `requestAuthorization()` until Speech is already authorized. After Speech permission is granted, it generates a short `say` audio fixture and transcribes it through the real `AppleSpeechSTTEngine`.

After mic, Speech, and Accessibility permissions are granted to `build/MiniMix.app`, `MINIMIX_RUN_UI_PROBES=1 scripts/probe-live-voice-readiness.sh release` should print `liveVoiceReady=true`. Only then is it meaningful to run a real push-to-talk pass with the physical microphone and focused-app paste target.

Latest local proof:

```text
hotkeyHarness registered=true reusableAfterStop=true pressCount=0 releaseCount=0
voiceHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0 insertedText=MiniMix voice harness sttLoadedAfterStop=false tapCount=0
voiceShutdownHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeWhileRecording=1 duckedVolume=0.35 activeAfterShutdown=0 restoredVolume=1.0 status=idle recorderStarted=true recorderStopped=true sttLoadedAfterShutdown=false insertedText=nil recordingFileExists=false
voiceShutdownDuringStartHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 immediateStatus=idle activeAfterShutdown=0 restoredVolume=1.0 status=idle recorderStarted=true recorderStopped=true sttLoadedAfterShutdown=false insertedText=nil recordingFileExists=false
voiceEarlyReleaseHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeAfterEarlyRelease=0 volumeAfterEarlyRelease=1.0 activeAfterSettled=0 restoredVolume=1.0 status=idle insertedText=MiniMix early release harness sttLoadedAfterStop=false
voiceRecorderFailureHarness immediateActiveAfterPress=1 immediateDuckedVolume=0.35 activeAfterFailure=0 restoredVolume=1.0 status=idle insertedText=nil sttLoadedAfterFailure=false error=Harness recorder start failed.
voiceSTTFailureHarness activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0 status=idle insertedText=nil sttLoadedAfterStop=false error=Harness STT load failed.
voicePasteFailureHarness activeWhileRecording=1 duckedVolume=0.35 sttLoadedWhileRecording=false activeAfterStop=0 restoredVolume=1.0 status=idle attemptedText=MiniMix paste failure harness insertedText=nil sttLoadedAfterStop=false error=Harness paste failed.
```

The packaged app now surfaces its own permission state in the menu. Current local state:

```text
Needs: Mic, Speech, Accessibility
```

The remaining voice validation is a live permission pass: grant mic, Speech, and Accessibility permissions to `build/MiniMix.app`, then record real microphone audio through Apple Speech and paste into a focused app. Do not treat terminal-level mic/Speech/Accessibility checks as proof for the signed app bundle.

## Product Positioning

MiniMix should not become a general assistant. The differentiated product is:

> A lightweight Mac audio mixer with voice input that knows when you are speaking.

That means the first voice version should be intentionally small:

- global push-to-talk
- automatic selected-app ducking while recording
- local transcription
- paste into focused app
- no agent features
- no meeting bot
- no full transcript library unless needed later

## Proposed Architecture

```text
MiniMixApp
 -> MenuBarController
 -> MixerController
 -> DuckingController
 -> VoiceInputController
     -> HotkeyController
     -> MicrophoneCapture
     -> VoiceActivityDetector
     -> STTEngine
     -> TextInjector
```

Core contracts:

```swift
protocol STTEngine {
    var isLoaded: Bool { get }
    func load() async throws
    func transcribe(_ audio: RecordedAudio) async throws -> Transcript
    func unloadIfIdle() async
}

protocol DuckingController {
    func beginVoiceDucking(reason: DuckingReason)
    func endVoiceDucking(reason: DuckingReason)
}
```

Voice capture flow:

```text
hotkey down
 -> beginVoiceDucking
 -> start mic capture
 -> optional VAD trims leading/trailing silence
hotkey up
 -> stop mic capture
 -> transcribe
 -> insert text
 -> endVoiceDucking
 -> unload model after idle timeout
```

## Performance Targets

Mixer-only targets remain unchanged:

- idle: about `0%` CPU and less than `50 MB` RSS
- no helper daemon
- no custom HAL driver

Voice expansion targets:

- idle voice subsystem: no active model inference
- recording with no transcription yet: less than `1%` CPU typical
- transcription: bounded burst, then return to idle
- model memory: loaded only during active use or held for a configurable warm window
- no background network unless the user enables a cloud engine

## Open Questions

- Is WhisperKit good enough for the first local engine, or should MiniMix start with Apple Speech for minimal footprint and add WhisperKit later?
- Should the first transcription mode be push-to-talk only, avoiding always-on VAD?
- Does app-specific ducking need a profile system before voice launch, or can the first version duck all currently managed apps?
- Should cloud STT be excluded entirely until the local version is stable?
