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
