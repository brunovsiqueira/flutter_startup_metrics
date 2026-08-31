## 0.1.3

- Drop a README caveat that described a limitation of our iOS test rig as if it
  were a property of the package. Apps in the field launch without a debugger
  and are unaffected; the constraint is documented in CONTRIBUTING, where it is
  relevant to anyone reproducing the measurements.

## 0.1.2

- Verified the iOS implementation on physical hardware for the first time
  (iPhone 8, iOS 16.7.12, release build): cold launch detected, phases
  contiguous, `hostStartup` correctly absent on iOS, and no launch falsely
  excluded as prewarmed. The README no longer says the iOS path is unverified.
- Added `example/run_ios_device.sh` for reproducing on-device runs, and
  documented in CONTRIBUTING why such runs cannot produce a trustworthy
  magnitude: iOS kills a developer-signed app when the debugger detaches, so the
  launch has to be measured with one attached. That is a test-rig constraint and
  does not affect apps in the field.

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
