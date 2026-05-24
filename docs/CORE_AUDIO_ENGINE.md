# Core Audio Engine

MiniMix uses Apple's process tap APIs instead of a custom HAL driver.

## Current Single-App Path

For a non-default app rule, MiniMix now has an engine path that can:

```text
bundle rule changes
 -> resolve app Core Audio process object
 -> create private CATapDescription process tap
 -> create private aggregate device with:
      - current default output device
      - the private process tap
 -> start an AudioDeviceIOProc
 -> copy tap input to output with gain applied
 -> stop IOProc, destroy aggregate device, destroy tap on reset/quit
```

The probe script validates the low-level path:

```sh
scripts/probe-single-app-gain.sh 0.35
```

The app-engine harness validates the same lifecycle through the MiniMix binary:

```sh
scripts/probe-app-engine-gain.sh 0.35
```

The controller harness validates the full mixer rule path through the MiniMix binary:

```sh
scripts/probe-controller-gain.sh 0.35
```

The menubar UI path was validated with QuickTime Player playing a local AIFF file:

```text
QuickTime Player shown as active audio app
slider AXDecrement -> 0%
footer -> 1 active MiniMix tap
reset button -> 100%
footer -> No active MiniMix taps
```

On this Mac it produced:

```text
processObjectID=178 tapID=180 aggregateID=181 callbacks=91 gain=0.35
gainHarness activeAfterApply=1 activeAfterRemove=0 tapCount=0 gain=0.35
controllerHarness detectedApps=1 activeAfterVolume=1 activeAfterReset=0 tapCount=0 gain=0.35
```

After the probe and after app smoke tests, `kAudioHardwarePropertyTapList` returned an empty tap list.

The engine registers a Core Audio listener for `kAudioHardwarePropertyDefaultOutputDevice`. When the default output device changes, active sessions are stopped and recreated against the new output device.

Current idle benchmark after engine wiring:

```text
MiniMix avg_cpu=0.06 max_cpu=0.30 avg_rss_mb=72.4 max_rss_mb=73.0 samples=5
```

## Design Rules

- Create taps only for non-default rules.
- Use private aggregate devices.
- Do not install a HAL driver.
- Do not run a helper daemon.
- Tear down the tap and aggregate device when the app returns to `100%` and unmuted.
- Shut down active sessions on app quit.
- Restart active sessions when the default output device changes.
- Surface the last Core Audio engine error in the menubar UI.

## Known MVP Risks

- Release RSS is currently around `75 MB` on this Mac, above the long-term `<50 MB` target.
- The controller path and menubar slider/reset path are verified. Subjective loudness should still be checked by ear during local use.
- The IOProc assumes Float sample buffers, which matched the local probe path but should be guarded by format inspection before public release.
