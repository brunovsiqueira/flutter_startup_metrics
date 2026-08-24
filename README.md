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
  Flutter is not when Flutter drew. Reimplementing one major vendor's iOS anchor
  from their source, it preceded Flutter's first frame in 10 simulator launches
  out of 10 — often before Dart `main()` had even run.

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

Then, wherever you report metrics. The common case is one line of ceremony —
`initialDisplay` is a sealed type, so this narrows it with no null checks:

```dart
if (await FlutterStartupMetrics.initialDisplay
    case StartupMeasurement(:final timeToInitialDisplay, :final phases)) {
  send('app.startup.ttid', timeToInitialDisplay);
  send('app.startup.engine_boot', phases.engineBoot);
}
```

Phases are addressable by name, as above. To forward the whole breakdown at
once, `toMap()` gives you name-to-duration pairs in launch order:

```dart
send('app.startup', phases.toMap());
```

Use a full `switch` only when you want to know *why* a launch was not measured:

```dart
switch (await FlutterStartupMetrics.initialDisplay) {
  case StartupMeasurement(:final timeToInitialDisplay):
    send('app.startup.ttid', timeToInitialDisplay);
  case StartupExcluded(:final reason):
    // 'prewarmed', 'backgroundLaunch', 'implausiblyLong', ...
    log('startup not measured: ${reason.name}');
}
```

There is deliberately no `Duration?` shortcut that skips this. Reporting a
prewarmed or background-started launch as if it were real is the failure mode
the package exists to prevent, so ignoring an exclusion is something you have to
choose rather than something you get by default.

### Time to full display

Only your app knows when its first screen holds real content rather than a
skeleton, so you have to say so. The call site is wherever that state lands —
after the data arrives, not on a timer, not in `build()`, and not in `main()`,
where nothing is displayed yet and the metric would collapse into TTID:

```dart
Future<void> _loadDashboard() async {
  final data = await repository.fetchDashboard();
  if (!mounted) return;
  setState(() => _data = data);

  FlutterStartupMetrics.reportFullyDisplayed();
}
```

If your first screen is conditional — an auth check, onboarding, a deep link —
every branch that can be a first screen needs the call. Launches that land on a
branch you missed report no TTFD at all. The example app shows this shape.

Then read it wherever you report:

```dart
final report = await FlutterStartupMetrics.fullDisplay;
```

`fullDisplay` is a second future rather than being folded into `initialDisplay`
on purpose: time-to-initial-display is available within a second of launch and
should not be held back by a call that may take seconds or never arrive. If it
never arrives, the future still resolves after 30 seconds with a null
`timeToFullDisplay`, so awaiting it is always safe.

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
