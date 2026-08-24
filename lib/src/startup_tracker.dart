import 'dart:async';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'native_launch_info.dart';
import 'startup_metrics_platform.dart';
import 'startup_report.dart';

/// Measures one cold start, from OS process start to Flutter's first rasterized
/// frame.
///
/// Call [start] as the first statement in `main()`. Everything after that is
/// passive: the tracker listens for the first frame, asks the platform for the
/// launch facts, and resolves [initialDisplay].
class StartupTracker {
  StartupTracker();

  final Completer<StartupReport> _initialDisplay = Completer<StartupReport>();
  final Completer<StartupReport> _fullDisplay = Completer<StartupReport>();

  DateTime? _dartMain;
  DateTime? _fullyDisplayedAt;
  StartupReport? _initialReport;
  Timer? _fullDisplayDeadline;

  /// Held so [_detach] can pass the exact instance back to the scheduler.
  /// `removeTimingsCallback` asserts the callback is registered, so a null field
  /// is what keeps detaching on a never-attached tracker from tripping it.
  TimingsCallback? _timingsCallback;

  Future<StartupReport> get initialDisplay => _initialDisplay.future;

  Future<StartupReport> get fullDisplay => _fullDisplay.future;

  /// Begins measurement. Safe to call more than once; only the first counts.
  void start({required Duration fullDisplayTimeout}) {
    if (_dartMain != null) return;

    // The binding must exist before frame callbacks can be registered, and doing
    // it here means the host app does not have to remember to.
    WidgetsFlutterBinding.ensureInitialized();
    _dartMain = DateTime.now().toUtc();

    _timingsCallback = _onTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);

    _armFullDisplayDeadline(fullDisplayTimeout);
  }

  void _armFullDisplayDeadline(Duration timeout) {
    _fullDisplayDeadline?.cancel();
    _fullDisplayDeadline = Timer(timeout, _resolveFullDisplay);
  }

  /// Marks the moment the app is meaningfully usable.
  void reportFullyDisplayed() {
    if (_fullDisplay.isCompleted) return;
    _fullyDisplayedAt ??= DateTime.now().toUtc();
    // The initial report may not exist yet if the app reports full display
    // during the very first frame; _buildReport picks the timestamp up.
    if (_initialReport != null) _resolveFullDisplay();
  }

  void _onTimings(List<FrameTiming> timings) =>
      unawaited(debugHandleTimings(timings));

  void _detach() {
    final cb = _timingsCallback;
    if (cb != null) {
      SchedulerBinding.instance.removeTimingsCallback(cb);
      _timingsCallback = null;
    }
  }

  Future<void> _buildReport(FrameTiming frame) async {
    NativeLaunchInfo? native;
    try {
      native = await StartupMetricsPlatform.instance.getLaunchInfo();
    } catch (_) {
      // A dead channel is indistinguishable from an unsupported platform, and
      // both mean the same thing to the caller.
    }

    final report = _assemble(frame, native);
    if (_initialDisplay.isCompleted) return;
    _initialReport = report;
    _initialDisplay.complete(report);

    // An app that reported full display before the first frame finished is
    // unusual but legal; honour it rather than waiting for the deadline. An
    // excluded launch has nothing further to wait for either.
    if (_fullyDisplayedAt != null || report is StartupExcluded) {
      _resolveFullDisplay();
    }
  }

  StartupReport _assemble(FrameTiming frame, NativeLaunchInfo? native) {
    final dartMain = _dartMain;
    if (native == null || dartMain == null) {
      return const StartupExcluded(ExclusionReason.nativeDataUnavailable);
    }
    if (native.isPrewarmed) {
      return const StartupExcluded(ExclusionReason.prewarmed);
    }
    if (native.isBackgroundLaunch) {
      return const StartupExcluded(ExclusionReason.backgroundLaunch);
    }

    // FrameTiming stamps raster-end on both the engine's steady clock and the
    // wall clock. Their difference converts every other phase into wall time,
    // which is the only way to line frame internals up against native anchors in
    // a release build.
    final rasterFinishWall = frame.timestampInMicroseconds(
      FramePhase.rasterFinishWallTime,
    );
    final offset =
        rasterFinishWall -
        frame.timestampInMicroseconds(FramePhase.rasterFinish);

    DateTime at(FramePhase phase) => DateTime.fromMicrosecondsSinceEpoch(
      frame.timestampInMicroseconds(phase) + offset,
      isUtc: true,
    );

    final firstFrame = DateTime.fromMicrosecondsSinceEpoch(
      rasterFinishWall,
      isUtc: true,
    );
    final vsync = at(FramePhase.vsyncStart);
    final buildStart = at(FramePhase.buildStart);
    final buildFinish = at(FramePhase.buildFinish);
    final rasterStart = at(FramePhase.rasterStart);

    // The vsync that drove the first frame can be signalled before Dart's
    // `main()` runs — the engine's frame pipeline is already ticking, so the two
    // are not causally ordered. Observed on roughly one cold launch in three on a
    // Galaxy S25, where this phase is only a couple of milliseconds wide. Fold
    // the boundary away rather than discarding an otherwise good launch.
    final hasVsyncBoundary = !vsync.isBefore(dartMain);

    final ordered = <DateTime>[
      native.processStart,
      native.platformInit,
      if (native.uiInit case final uiInit?) uiInit,
      dartMain,
      if (hasVsyncBoundary) vsync,
      buildStart,
      buildFinish,
      rasterStart,
      firstFrame,
    ];

    // Any remaining anchor out of order means a clock moved under us. Report
    // nothing rather than a plausible-looking wrong number.
    for (var i = 1; i < ordered.length; i++) {
      if (ordered[i].isBefore(ordered[i - 1])) {
        return const StartupExcluded(ExclusionReason.incoherentTimeline);
      }
    }

    if (firstFrame.difference(native.processStart) >
        StartupReport.maxPlausibleLaunch) {
      return const StartupExcluded(ExclusionReason.implausiblyLong);
    }

    final engineBootFrom = native.uiInit ?? native.platformInit;
    return StartupMeasurement(
      launchType: native.launchType,
      processStart: native.processStart,
      firstFrameRasterized: firstFrame,
      phases: StartupPhases(
        processInit: native.platformInit.difference(native.processStart),
        hostStartup: native.uiInit?.difference(native.platformInit),
        engineBoot: dartMain.difference(engineBootFrom),
        dartBootstrap: (hasVsyncBoundary ? vsync : buildStart).difference(
          dartMain,
        ),
        frameScheduling: hasVsyncBoundary ? buildStart.difference(vsync) : null,
        frameBuild: buildFinish.difference(buildStart),
        rasterHandoff: rasterStart.difference(buildFinish),
        frameRaster: firstFrame.difference(rasterStart),
      ),
    );
  }

  void _resolveFullDisplay() {
    if (_fullDisplay.isCompleted) return;
    _fullDisplayDeadline?.cancel();
    _fullDisplayDeadline = null;

    _fullDisplay.complete(switch (_initialReport) {
      StartupMeasurement m => m.withFullDisplay(_clampToInitial(m)),
      StartupExcluded e => e,
      // The deadline fired before any frame was ever rasterized.
      null => const StartupExcluded(ExclusionReason.noFrameRendered),
    });
  }

  /// Full display cannot precede initial display, but the two timestamps come
  /// from different clocks — `DateTime.now()` here, the engine's `system_clock`
  /// for the frame — so a report made within a millisecond of the first frame
  /// can land fractionally before it.
  ///
  /// That is measurement noise, not a corrupt launch, so it is clamped rather
  /// than dropped. Datadog and Sentry both take `max(ttid, ttfd)` for the same
  /// reason. Emitting TTFD < TTID would read as broken data to anyone consuming
  /// it, which is worse than a sub-millisecond overstatement.
  Duration? _clampToInitial(StartupMeasurement m) {
    final at = _fullyDisplayedAt;
    if (at == null) return null;
    final ttfd = at.difference(m.processStart);
    return ttfd < m.timeToInitialDisplay ? m.timeToInitialDisplay : ttfd;
  }

  /// Feeds a frame in directly, bypassing the scheduler.
  ///
  /// Exists because the interesting logic — clock conversion, ordering checks,
  /// exclusion — is otherwise only reachable through a real first frame.
  @visibleForTesting
  Future<void> debugHandleTimings(List<FrameTiming> timings) async {
    if (timings.isEmpty || _initialDisplay.isCompleted) return;
    _detach();
    await _buildReport(timings.first);
  }

  /// Sets the Dart-entry anchor without starting frame observation.
  ///
  /// Pass [fullDisplayTimeout] to also arm the real deadline, which is the only
  /// way to exercise the abandoned-TTFD path without waiting 30 seconds.
  @visibleForTesting
  void debugSetDartMain(DateTime value, {Duration? fullDisplayTimeout}) {
    _dartMain = value;
    if (fullDisplayTimeout != null) _armFullDisplayDeadline(fullDisplayTimeout);
  }

  /// Releases the frame callback and pending timer. Tests only.
  @visibleForTesting
  void dispose() {
    _detach();
    _fullDisplayDeadline?.cancel();
  }
}
