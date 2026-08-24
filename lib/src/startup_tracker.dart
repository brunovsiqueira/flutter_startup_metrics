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
/// launch facts, and resolves [report].
class StartupTracker {
  StartupTracker();

  /// Default deadline for [reportFullyDisplayed]. Matches Sentry's, and exists
  /// so an app that forgets to call it leaves a resolved future rather than a
  /// permanently pending one.
  static const Duration defaultFullDisplayTimeout = Duration(seconds: 30);

  final Completer<StartupReport> _initialDisplay = Completer<StartupReport>();
  final Completer<StartupReport> _fullDisplay = Completer<StartupReport>();

  DateTime? _dartMain;
  DateTime? _fullyDisplayedAt;
  StartupReport? _initialReport;
  Timer? _fullDisplayDeadline;
  bool _started = false;
  TimingsCallback? _timingsCallback;

  /// Resolves when Flutter has rasterized its first frame.
  ///
  /// Always resolves — an unusable launch resolves with an [ExclusionReason]
  /// rather than hanging or throwing.
  Future<StartupReport> get report => _initialDisplay.future;

  /// Resolves when [reportFullyDisplayed] is called, or when the deadline
  /// passes, whichever comes first.
  ///
  /// Kept separate from [report] deliberately: time-to-initial-display is
  /// available in milliseconds and should not be held hostage to a call the app
  /// might never make.
  Future<StartupReport> get fullDisplayReport => _fullDisplay.future;

  /// Begins measurement. Safe to call more than once; only the first call counts.
  void start({Duration fullDisplayTimeout = defaultFullDisplayTimeout}) {
    if (_started) return;
    _started = true;

    // Binding must exist before frame callbacks can be registered, and calling
    // this here means the host app does not have to remember to.
    WidgetsFlutterBinding.ensureInitialized();
    _dartMain = DateTime.now().toUtc();

    _timingsCallback = _onTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);

    _fullDisplayDeadline = Timer(fullDisplayTimeout, () {
      _resolveFullDisplay(null);
    });
  }

  /// Marks the moment the app is meaningfully usable — first screen populated,
  /// not merely painted.
  ///
  /// There is no way to infer this: only the app knows when its content is real
  /// rather than a skeleton. Calls after the deadline, or second calls, are
  /// ignored.
  void reportFullyDisplayed() {
    if (_fullDisplay.isCompleted) return;
    _fullyDisplayedAt ??= DateTime.now().toUtc();
    // The initial report may not exist yet if the app reports full display
    // during the very first frame; _onTimings will pick the timestamp up.
    if (_initialReport != null) {
      _resolveFullDisplay(_fullyDisplayedAt);
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty || _initialDisplay.isCompleted) return;

    // Deferred frames never reach the engine and so never produce a FrameTiming.
    // That makes the first entry here the first frame a user could actually see,
    // which is the semantics we want and the reason this is not an
    // addPostFrameCallback.
    final first = timings.first;
    _detach();
    unawaited(_buildReport(first));
  }

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
      native = null;
    }

    final report = _assemble(frame, native);
    _initialReport = report;
    if (!_initialDisplay.isCompleted) _initialDisplay.complete(report);

    // An app that reported full display before the first frame finished is
    // unusual but legal; honour it rather than waiting for the deadline.
    if (_fullyDisplayedAt != null) _resolveFullDisplay(_fullyDisplayedAt);
    if (!report.isReportable) _resolveFullDisplay(null);
  }

  StartupReport _assemble(FrameTiming frame, NativeLaunchInfo? native) {
    final dartMain = _dartMain;
    if (native == null || dartMain == null) {
      return StartupReport.excluded(ExclusionReason.nativeDataUnavailable);
    }
    if (native.isPrewarmed) {
      return StartupReport.excluded(ExclusionReason.prewarmed);
    }
    if (native.isBackgroundLaunch) {
      return StartupReport.excluded(ExclusionReason.backgroundLaunch);
    }

    // FrameTiming stamps raster-end on both the engine's steady clock and the
    // wall clock. Their difference converts every other phase into wall time,
    // which is the only way to line frame internals up against native anchors
    // in a release build.
    final rasterFinishWall = frame.timestampInMicroseconds(
      FramePhase.rasterFinishWallTime,
    );
    final offset =
        rasterFinishWall - frame.timestampInMicroseconds(FramePhase.rasterFinish);

    DateTime at(FramePhase phase) => DateTime.fromMicrosecondsSinceEpoch(
          frame.timestampInMicroseconds(phase) + offset,
          isUtc: true,
        );

    final firstFrame =
        DateTime.fromMicrosecondsSinceEpoch(rasterFinishWall, isUtc: true);

    final marks = <String, DateTime>{
      'processStart': native.processStart,
      'platformInit': native.platformInit,
      if (native.uiInit case final uiInit?) 'uiInit': uiInit,
      'dartMain': dartMain,
      'frameVsync': at(FramePhase.vsyncStart),
      'buildStart': at(FramePhase.buildStart),
      'buildFinish': at(FramePhase.buildFinish),
      'rasterStart': at(FramePhase.rasterStart),
      'rasterFinish': firstFrame,
    };

    // The vsync that drove the first frame can be signalled before Dart's
    // `main()` runs — the engine's frame pipeline is already ticking by then, so
    // the two are not causally ordered. Observed on roughly one cold launch in
    // three on a Galaxy S25, where this phase is only a couple of milliseconds
    // wide. Fold the boundary away instead of treating a legitimate ordering as
    // a corrupt timeline and discarding an otherwise good launch.
    if (marks['frameVsync'] case final vsync?
        when vsync.isBefore(marks['dartMain']!)) {
      marks.remove('frameVsync');
    }

    // Any remaining anchor out of order means a clock moved under us. Report
    // nothing rather than a plausible-looking wrong number.
    final ordered = marks.values.toList();
    for (var i = 1; i < ordered.length; i++) {
      if (ordered[i].isBefore(ordered[i - 1])) {
        return StartupReport.excluded(ExclusionReason.incoherentTimeline);
      }
    }

    final total = firstFrame.difference(native.processStart);
    if (total > StartupReport.maxPlausibleLaunch) {
      return StartupReport.excluded(ExclusionReason.implausiblyLong);
    }

    return StartupReport.measured(
      launchType: native.launchType,
      processStart: native.processStart,
      firstFrameRasterized: firstFrame,
      phases: _phases(marks),
    );
  }

  /// A contiguous partition of the launch, so the phases sum exactly to the
  /// total. Each boundary is an anchor a developer can act on.
  ///
  /// Built by walking the ordered marks rather than from a fixed table, because
  /// the set of available boundaries is platform-dependent: Android can split
  /// host startup at the first Activity, iOS cannot.
  List<StartupPhase> _phases(Map<String, DateTime> marks) {
    // Names the *span* ending at each mark. `processStart` opens the sequence
    // and so names nothing.
    final spanEndingAt = <String, String>{
      'platformInit': 'processInit',
      'uiInit': 'hostStartup',
      'dartMain': 'engineBoot',
      'frameVsync': 'dartBootstrap',
      // When the vsync boundary was dropped, this span absorbs it and is named
      // for what it then actually covers.
      'buildStart':
          marks.containsKey('frameVsync') ? 'frameScheduling' : 'dartBootstrap',
      'buildFinish': 'frameBuild',
      'rasterStart': 'rasterHandoff',
      'rasterFinish': 'frameRaster',
    };

    final entries = marks.entries.toList(growable: false);
    return [
      for (var i = 1; i < entries.length; i++)
        StartupPhase(
          name: spanEndingAt[entries[i].key]!,
          start: entries[i - 1].value,
          end: entries[i].value,
        ),
    ];
  }

  void _resolveFullDisplay(DateTime? fullyDisplayedAt) {
    if (_fullDisplay.isCompleted) return;
    _fullDisplayDeadline?.cancel();
    _fullDisplayDeadline = null;

    final base = _initialReport;
    if (base == null || !base.isReportable) {
      _fullDisplay.complete(
        base ?? StartupReport.excluded(ExclusionReason.nativeDataUnavailable),
      );
      return;
    }
    _fullDisplay.complete(
      StartupReport.measured(
        launchType: base.launchType,
        processStart: base.processStart!,
        firstFrameRasterized: base.firstFrameRasterized!,
        phases: base.phases,
        timeToFullDisplay:
            fullyDisplayedAt?.difference(base.processStart!),
      ),
    );
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
    _started = true;
    _dartMain = value;
    if (fullDisplayTimeout != null) {
      _fullDisplayDeadline?.cancel();
      _fullDisplayDeadline =
          Timer(fullDisplayTimeout, () => _resolveFullDisplay(null));
    }
  }

  /// Releases the frame callback and pending timer. Tests only.
  @visibleForTesting
  void dispose() {
    _detach();
    _fullDisplayDeadline?.cancel();
  }
}
