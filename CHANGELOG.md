## 0.1.2

- Verified the iOS implementation on physical hardware for the first time
  (iPhone 8, iOS 16.7.12, release build): cold launch detected, phases
  contiguous, `hostStartup` correctly absent on iOS, and no launch falsely
  excluded as prewarmed. Documentation updated accordingly.
- Documented that on-device iOS runs necessarily carry a debugger, because iOS
  terminates a developer-signed app when it detaches — so iOS magnitudes are an
  upper bound rather than a baseline. Android numbers are debugger-free.
- Added `example/run_ios_device.sh` for reproducing on-device runs.

No library code changes.

## 0.1.1

- Shorten the package description to pub.dev's 180-character limit, which was
  costing 10 pub points. No code changes.

## 0.1.0

Initial release.

- Cold-start measurement from OS process start to Flutter's first rasterized
  frame, using `FramePhase.rasterFinishWallTime` to bridge the engine's
  monotonic clock to wall time.
- Contiguous phase breakdown; phases sum exactly to the total.
- Android splits host startup at the first `Activity.onCreate` via a
  ContentProvider that needs no setup in the host app.
- Opt-in time to full display via `reportFullyDisplayed()`, with a 30-second
  deadline so an abandoned call resolves rather than hangs.
- Launches that cannot be measured honestly — prewarmed, background-started,
  implausibly long, or with an out-of-order timeline — are dropped with a
  reason rather than clamped.
