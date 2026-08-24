import 'package:meta/meta.dart';

/// How the process came to be running.
///
/// There is no public API on either platform that reports this directly, so both
/// values are inferred. [unknown] is returned rather than guessed when the
/// signals are unavailable — a wrong classification is worse than an absent one,
/// because it silently mixes populations in an aggregate.
enum LaunchType {
  /// The process was created for this launch.
  cold,

  /// Could not be determined.
  ///
  /// Warm starts land here. This library only ever loads into a process it was
  /// created with, so a launch it can observe at all is a cold one — a warm
  /// start reuses the process and is not measurable from process start.
  unknown,
}

/// Why a launch produced no reportable measurement.
enum ExclusionReason {
  /// iOS prewarmed the process ahead of the user, so process start predates any
  /// user intent. Detected via the `ActivePrewarm` environment variable.
  prewarmed,

  /// The process was started by the system rather than the user — a silent push,
  /// a background job, a content provider access.
  backgroundLaunch,

  /// The measured window exceeds [StartupReport.maxPlausibleLaunch]. Dropped
  /// rather than clamped: a clamped ceiling value is indistinguishable from a
  /// real one and quietly corrupts percentiles.
  implausiblyLong,

  /// An anchor arrived out of order, which means a clock moved mid-launch.
  incoherentTimeline,

  /// The platform did not return launch information.
  nativeDataUnavailable,

  /// Flutter never rasterized a frame before the full-display deadline — a
  /// headless or killed launch. Only ever reported by `fullDisplay`.
  noFrameRendered,
}

/// One named segment of the launch.
@immutable
class StartupPhase {
  const StartupPhase({required this.name, required this.duration});

  /// Stable identifier, safe to use as a metric name.
  final String name;
  final Duration duration;

  @override
  String toString() => '$name: ${duration.inMicroseconds / 1000}ms';
}

/// The launch broken into segments, addressable by name.
///
/// Two phases are nullable, and for different reasons. [hostStartup] exists only
/// where the platform exposes a UI-creation boundary — Android's first
/// `Activity.onCreate`; iOS has no comparable anchor. [frameScheduling]
/// disappears when the frame's vsync arrived before Dart `main()` ran, which is
/// legitimate and common: the engine's frame pipeline ticks independently of
/// when Dart starts. In that case its time is absorbed into [dartBootstrap].
///
/// The named getters are for the common case of forwarding a fixed set of
/// metrics. Use [all] when you want to forward whatever the platform gave you
/// without enumerating it.
@immutable
class StartupPhases {
  const StartupPhases({
    required this.processInit,
    required this.hostStartup,
    required this.engineBoot,
    required this.dartBootstrap,
    required this.frameScheduling,
    required this.frameBuild,
    required this.rasterHandoff,
    required this.frameRaster,
  });

  /// Process start until this library first ran — the OS, the runtime, and on
  /// Android the zygote fork and class loading.
  final Duration processInit;

  /// Until the host created its UI container. Android only; null on iOS.
  final Duration? hostStartup;

  /// Until Dart `main()` was entered. The Flutter engine and Dart VM starting up.
  final Duration engineBoot;

  /// Your own work before the first frame began — everything above `runApp`.
  final Duration dartBootstrap;

  /// Vsync until the UI thread began building. Null when folded into
  /// [dartBootstrap]; see the class doc.
  final Duration? frameScheduling;

  /// Building the first widget tree.
  final Duration frameBuild;

  /// Handing the built frame to the raster thread.
  final Duration rasterHandoff;

  /// Rasterizing — shader compilation, surface setup, GPU work.
  final Duration frameRaster;

  /// Every phase present on this platform, keyed by name.
  ///
  /// The usual way to forward the whole breakdown, since most metrics backends
  /// accept a map. Contiguous: the values sum exactly to
  /// [StartupMeasurement.timeToInitialDisplay].
  ///
  /// ```dart
  /// send('app.startup', phases.toMap());
  /// ```
  Map<String, Duration> toMap() => {
    for (final phase in all) phase.name: phase.duration,
  };

  /// Every phase present on this platform, in launch order.
  ///
  /// Use when order matters or when your backend takes one metric at a time;
  /// otherwise prefer [toMap].
  List<StartupPhase> get all => [
    StartupPhase(name: 'processInit', duration: processInit),
    if (hostStartup case final d?)
      StartupPhase(name: 'hostStartup', duration: d),
    StartupPhase(name: 'engineBoot', duration: engineBoot),
    StartupPhase(name: 'dartBootstrap', duration: dartBootstrap),
    if (frameScheduling case final d?)
      StartupPhase(name: 'frameScheduling', duration: d),
    StartupPhase(name: 'frameBuild', duration: frameBuild),
    StartupPhase(name: 'rasterHandoff', duration: rasterHandoff),
    StartupPhase(name: 'frameRaster', duration: frameRaster),
  ];

  @override
  String toString() => all.join(', ');
}

/// The result of measuring one app launch.
///
/// Sealed, so the two outcomes are distinguishable by the type system rather
/// than by a boolean plus force-unwraps. Switch on it:
///
/// ```dart
/// switch (await FlutterStartupMetrics.initialDisplay) {
///   case StartupMeasurement(:final timeToInitialDisplay, :final phases):
///     send('app.startup.ttid', timeToInitialDisplay);
///     send('app.startup.engine_boot', phases.engineBoot);
///   case StartupExcluded(:final reason):
///     log('startup not measured: ${reason.name}');
/// }
/// ```
sealed class StartupReport {
  const StartupReport();

  /// Launches longer than this are dropped. Datadog and Sentry converged on 60s
  /// independently, which is reasonable evidence it is the right magnitude.
  static const Duration maxPlausibleLaunch = Duration(seconds: 60);
}

/// A launch that was measured successfully. Every timing is non-null.
final class StartupMeasurement extends StartupReport {
  @internal
  const StartupMeasurement({
    required this.launchType,
    required this.processStart,
    required this.firstFrameRasterized,
    required this.phases,
    this.timeToFullDisplay,
  });

  final LaunchType launchType;

  /// OS process start: `Process.getStartUptimeMillis()` on Android,
  /// `sysctl(KERN_PROC_PID)` on iOS.
  ///
  /// These are not the same event — Android's is the zygote fork, iOS's the
  /// exec. The endpoint is equivalent across platforms; the origin is not, so
  /// treat cross-platform comparisons of the total with care.
  final DateTime processStart;

  /// When Flutter finished rasterizing its first frame, from
  /// `FramePhase.rasterFinishWallTime`. The endpoint that means the same thing
  /// on every platform.
  final DateTime firstFrameRasterized;

  final StartupPhases phases;

  /// Process start until the app called `reportFullyDisplayed()`.
  ///
  /// Null on the report returned by `initialDisplay`, which resolves before any
  /// such call can be meaningful, and null on `fullDisplay` when the app never
  /// made the call.
  final Duration? timeToFullDisplay;

  /// Process start to first rasterized frame. The headline number.
  Duration get timeToInitialDisplay =>
      firstFrameRasterized.difference(processStart);

  @internal
  StartupMeasurement withFullDisplay(Duration? ttfd) => StartupMeasurement(
    launchType: launchType,
    processStart: processStart,
    firstFrameRasterized: firstFrameRasterized,
    phases: phases,
    timeToFullDisplay: ttfd,
  );

  @override
  String toString() {
    final ttfd = timeToFullDisplay;
    final buf =
        StringBuffer()..writeln(
          'StartupMeasurement(${launchType.name}, '
          'TTID ${timeToInitialDisplay.inMilliseconds}ms'
          '${ttfd != null ? ', TTFD ${ttfd.inMilliseconds}ms' : ''})',
        );
    for (final p in phases.all) {
      buf.writeln('  $p');
    }
    return buf.toString();
  }
}

/// A launch that could not be measured honestly, and why.
final class StartupExcluded extends StartupReport {
  @internal
  const StartupExcluded(this.reason);

  final ExclusionReason reason;

  @override
  String toString() => 'StartupExcluded(${reason.name})';
}
