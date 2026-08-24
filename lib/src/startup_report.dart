import 'package:meta/meta.dart';

/// How the process came to be running.
///
/// There is no public API on either platform that reports this directly, so
/// both values are inferred. [unknown] is returned rather than guessed when the
/// signals are unavailable — a wrong classification is worse than an absent one,
/// because it silently mixes populations in an aggregate.
enum LaunchType {
  /// The process was created for this launch.
  cold,

  /// The process already existed; the UI was recreated.
  warm,

  /// Could not be determined on this platform or OS version.
  unknown,
}

/// Why a launch produced no reportable measurement.
///
/// Exposed as a reason rather than a bool because "no data" is the state people
/// most often need to debug, and a bare null tells them nothing.
enum ExclusionReason {
  /// iOS prewarmed the process ahead of the user, so process start predates any
  /// user intent. Detected via the `ActivePrewarm` environment variable.
  prewarmed,

  /// The process was started by the system rather than the user — a silent
  /// push, a background job, a content provider access.
  backgroundLaunch,

  /// The measured window exceeds [StartupReport.maxPlausibleLaunch]. Dropped
  /// rather than clamped: a clamped ceiling value is indistinguishable from a
  /// real one and quietly corrupts percentiles.
  implausiblyLong,

  /// An anchor arrived out of order, which means at least one clock moved.
  incoherentTimeline,

  /// The platform did not return launch information.
  nativeDataUnavailable,
}

/// One measured segment of the launch.
@immutable
class StartupPhase {
  const StartupPhase({
    required this.name,
    required this.start,
    required this.end,
  });

  /// Stable identifier, safe to use as a metric name.
  final String name;

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  @override
  String toString() => '$name: ${duration.inMicroseconds / 1000}ms';
}

/// The result of measuring one app launch.
///
/// Either [isReportable] is true and the timings are populated, or [exclusion]
/// explains why this launch should not be counted.
@immutable
class StartupReport {
  const StartupReport._({
    required this.launchType,
    required this.exclusion,
    required this.processStart,
    required this.firstFrameRasterized,
    required this.phases,
    required this.timeToFullDisplay,
  });

  /// Launches longer than this are dropped. Both Datadog and Sentry converged
  /// on 60s independently, which is a reasonable signal that it is the right
  /// order of magnitude.
  static const Duration maxPlausibleLaunch = Duration(seconds: 60);

  @internal
  factory StartupReport.excluded(ExclusionReason reason) => StartupReport._(
        launchType: LaunchType.unknown,
        exclusion: reason,
        processStart: null,
        firstFrameRasterized: null,
        phases: const [],
        timeToFullDisplay: null,
      );

  @internal
  factory StartupReport.measured({
    required LaunchType launchType,
    required DateTime processStart,
    required DateTime firstFrameRasterized,
    required List<StartupPhase> phases,
    Duration? timeToFullDisplay,
  }) =>
      StartupReport._(
        launchType: launchType,
        exclusion: null,
        processStart: processStart,
        firstFrameRasterized: firstFrameRasterized,
        phases: phases,
        timeToFullDisplay: timeToFullDisplay,
      );

  final LaunchType launchType;

  /// Null when the launch was measured successfully.
  final ExclusionReason? exclusion;

  bool get isReportable => exclusion == null;

  /// OS process start. Read from `Process.getStartUptimeMillis()` on Android and
  /// `sysctl(KERN_PROC_PID)` on iOS.
  ///
  /// These are not the same event. Android's is the zygote fork; iOS's is the
  /// exec. Treat cross-platform comparisons of the total with suspicion — the
  /// endpoint is equivalent across platforms, the origin is not.
  final DateTime? processStart;

  /// When Flutter finished rasterizing its first frame, from
  /// `FramePhase.rasterFinishWallTime`. This is the endpoint that means the same
  /// thing on every platform.
  final DateTime? firstFrameRasterized;

  /// Ordered, contiguous segments from [processStart] to [firstFrameRasterized].
  final List<StartupPhase> phases;

  /// Time from process start until the app called
  /// `FlutterStartupMetrics.reportFullyDisplayed()`, if it ever did.
  final Duration? timeToFullDisplay;

  /// Process start to first rasterized frame. The headline number.
  Duration? get timeToInitialDisplay =>
      processStart == null || firstFrameRasterized == null
          ? null
          : firstFrameRasterized!.difference(processStart!);

  @override
  String toString() {
    if (!isReportable) return 'StartupReport(excluded: ${exclusion!.name})';
    final buf = StringBuffer()
      ..writeln('StartupReport(${launchType.name}, '
          'TTID ${timeToInitialDisplay!.inMilliseconds}ms'
          '${timeToFullDisplay != null ? ', TTFD ${timeToFullDisplay!.inMilliseconds}ms' : ''})');
    for (final p in phases) {
      buf.writeln('  $p');
    }
    return buf.toString();
  }
}
