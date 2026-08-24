# flutter_startup_metrics

Measures Flutter cold start from **OS process start** to the **first frame
Flutter actually rasterizes**, and breaks the gap into phases you can act on.

It is not a `Stopwatch` wrapper. It reads the process start time from the
platform, anchors the endpoint on `FramePhase.rasterFinishWallTime`, and reports
the phases in between. It sends nothing anywhere — forward the report to whatever
you already run.

## Why

Flutter has no process-start API. Its own earliest timestamp is recorded at Dart
VM init, long after the OS began the launch, so any honest cold-start number has
to come from native code on one side and Flutter on the other.

Getting the endpoint wrong is the common failure. Two anchors that look right and
are not:

- **`addPostFrameCallback`** fires when the first frame is *built*, not
  displayed. Measured on a Galaxy S25 it reported 141.6 ms against a true
  180.1 ms — 21% short. On an emulator the same error was 2.4×.
- **Native display callbacks** fire when the *platform* draws, which under
  Flutter is not when Flutter drew. One major vendor's iOS anchor preceded
  Flutter's first frame in 10 measured launches out of 10.

This package uses the one bridge Flutter sanctions for exactly this problem:
`FrameTiming` stamps raster-end on both the engine's monotonic clock and the wall
clock, so the offset between them converts every frame phase into epoch time. The
API exists because the Flutter team added it for this use case
([flutter/flutter#85139](https://github.com/flutter/flutter/issues/85139)).

## Usage

```dart
import 'package:flutter_startup_metrics/flutter_startup_metrics.dart';

void main() {
  FlutterStartupMetrics.start(); // first statement
  runApp(const MyApp());
}
```

Then, wherever you report metrics:

```dart
final report = await FlutterStartupMetrics.report;
if (report.isReportable) {
  send('app.startup.ttid', report.timeToInitialDisplay!);
  for (final phase in report.phases) {
    send('app.startup.${phase.name}', phase.duration);
  }
} else {
  // 'prewarmed', 'backgroundLaunch', 'implausiblyLong', ...
  log('startup not reportable: ${report.exclusion!.name}');
}
```

### Time to full display

Only your app knows when its first screen holds real content rather than a
skeleton, so you have to say so:

```dart
FlutterStartupMetrics.reportFullyDisplayed();

final full = await FlutterStartupMetrics.fullDisplayReport;
```

`fullDisplayReport` is separate from `report` on purpose: time-to-initial-display
is available in milliseconds and should not wait on a call your app might never
make. If it never comes, the future resolves with a null `timeToFullDisplay`
after 30 seconds rather than hanging.

## What you get

A contiguous partition — the phases sum exactly to the total, so nothing hides
between them. Real numbers from a Galaxy S25, profile build:

| Phase | Covers | Median |
|---|---|---|
| `processInit` | process start → this library loads | 65 ms |
| `hostStartup` | → first `Activity.onCreate` (Android only) | 14 ms |
| `engineBoot` | → Dart `main()` | 67 ms |
| `dartBootstrap` | → first frame begins | 7 ms |
| `frameScheduling` | vsync → build starts | 27 ms |
| `frameBuild` | widget tree | 0.6 ms |
| `rasterHandoff` | build → raster thread | 0.04 ms |
| `frameRaster` | rasterizing | 8 ms |

The phase you would have guessed is rarely the phase that costs. Build and raster
together were under 5% of that launch.

## Launches it refuses to measure

A wrong number is worse than no number, so these are dropped rather than clamped
and the reason is reported:

| Reason | Why |
|---|---|
| `prewarmed` | iOS started the process before the user acted, so process start means nothing |
| `backgroundLaunch` | a push, job or provider access started the process |
| `implausiblyLong` | over 60 s — a clamped ceiling is indistinguishable from a real value |
| `incoherentTimeline` | an anchor arrived out of order, so a clock moved |
| `nativeDataUnavailable` | the platform returned nothing |

## Caveats worth knowing

- **The origin is platform-specific; the endpoint is not.** Android's process
  start is the zygote fork, iOS's is the exec. The endpoint — Flutter's first
  rasterized frame — means the same thing on both. Compare totals across
  platforms with that in mind.
- **Cold starts only.** Warm starts reuse the process and are not measurable from
  process start; those report `LaunchType.unknown` rather than a guess.
- **iOS folds pre-`main()` into the first phase.** Capturing dyld time needs an
  Objective-C `+load` or a C constructor, which is machinery out of proportion to
  this package. `processInit` on iOS ends at plugin registration.
- **Android needs API 24+** for `Process.getStartUptimeMillis()`. Below that it
  falls back to this library's own ContentProvider, which is later than the true
  process start — so it under-reports rather than inventing time.

## License

MIT
