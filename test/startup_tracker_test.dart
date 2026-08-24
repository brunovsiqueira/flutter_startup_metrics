import 'dart:ui';

import 'package:flutter_startup_metrics/flutter_startup_metrics.dart';
import 'package:flutter_startup_metrics/src/native_launch_info.dart';
import 'package:flutter_startup_metrics/src/startup_metrics_platform.dart';
import 'package:flutter_startup_metrics/src/startup_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// The engine's monotonic clock shares no origin with the wall clock, so tests
/// use a deliberately large, arbitrary offset to catch any code that quietly
/// assumes the two are interchangeable.
const int kMonoToWallOffsetUs = 1700000000000000;

class _FakePlatform extends StartupMetricsPlatform {
  _FakePlatform(this.info);
  final NativeLaunchInfo? info;
  bool throwOnCall = false;

  @override
  Future<NativeLaunchInfo?> getLaunchInfo() async {
    if (throwOnCall) throw StateError('channel down');
    return info;
  }
}

DateTime _wall(int us) =>
    DateTime.fromMicrosecondsSinceEpoch(kMonoToWallOffsetUs + us, isUtc: true);

/// Builds a frame whose monotonic phases are [vsync]..[rasterFinish] and whose
/// wall-time anchor is consistent with [kMonoToWallOffsetUs].
FrameTiming _frame({
  int vsync = 1000,
  int buildStart = 1100,
  int buildFinish = 1200,
  int rasterStart = 1250,
  int rasterFinish = 1400,
  int? rasterFinishWallTime,
}) =>
    FrameTiming(
      vsyncStart: vsync,
      buildStart: buildStart,
      buildFinish: buildFinish,
      rasterStart: rasterStart,
      rasterFinish: rasterFinish,
      rasterFinishWallTime:
          rasterFinishWallTime ?? kMonoToWallOffsetUs + rasterFinish,
    );

NativeLaunchInfo _native({
  int processStartUs = 0,
  int platformInitUs = 500,
  int? uiInitUs,
  LaunchType launchType = LaunchType.cold,
  bool isPrewarmed = false,
  bool isBackgroundLaunch = false,
}) =>
    NativeLaunchInfo(
      processStart: _wall(processStartUs),
      platformInit: _wall(platformInitUs),
      uiInit: uiInitUs == null ? null : _wall(uiInitUs),
      launchType: launchType,
      isPrewarmed: isPrewarmed,
      isBackgroundLaunch: isBackgroundLaunch,
    );

StartupTracker _tracker(NativeLaunchInfo? info, {int dartMainUs = 800}) {
  StartupMetricsPlatform.instance = _FakePlatform(info);
  return StartupTracker()..debugSetDartMain(_wall(dartMainUs));
}

/// Asserts the launch was measurable and narrows the sealed type, so the tests
/// below read the same way a consumer's code does.
StartupMeasurement _measured(StartupReport report) {
  expect(report, isA<StartupMeasurement>(),
      reason: 'expected a measurable launch, got $report');
  return report as StartupMeasurement;
}

Duration _sum(StartupMeasurement m) =>
    m.phases.all.fold(Duration.zero, (acc, p) => acc + p.duration);

void main() {
  tearDown(() => StartupMetricsPlatform.instance = StartupMetricsPlatform());

  group('measurement', () {
    test('derives wall-clock phases from the monotonic frame', () async {
      final tracker = _tracker(_native());
      await tracker.debugHandleTimings([_frame()]);
      final report = _measured(await tracker.initialDisplay);

      expect(report.launchType, LaunchType.cold);
      // 1400us of monotonic frame time, anchored at process start 0.
      expect(report.timeToInitialDisplay, const Duration(microseconds: 1400));
      expect(report.firstFrameRasterized, _wall(1400));
    });

    test('phases partition the launch exactly', () async {
      final tracker = _tracker(_native());
      await tracker.debugHandleTimings([_frame()]);
      final report = _measured(await tracker.initialDisplay);

      expect(_sum(report), report.timeToInitialDisplay,
          reason: 'phases must be contiguous, or the breakdown misleads');

      expect(
        report.phases.all.map((p) => p.name),
        containsAllInOrder(<String>[
          'processInit',
          'engineBoot',
          'dartBootstrap',
          'frameScheduling',
          'frameBuild',
          'rasterHandoff',
          'frameRaster',
        ]),
      );
    });

    test('splits host startup when the platform supplies a UI anchor', () async {
      final tracker = _tracker(_native(uiInitUs: 600));
      await tracker.debugHandleTimings([_frame()]);
      final report = _measured(await tracker.initialDisplay);

      expect(report.phases.hostStartup, isNotNull,
          reason: 'Android splits Application/Activity setup out of engineBoot');
      final names = report.phases.all.map((p) => p.name).toList();
      expect(names.indexOf('hostStartup'), lessThan(names.indexOf('engineBoot')));

      expect(_sum(report), report.timeToInitialDisplay,
          reason: 'the extra boundary must not break contiguity');
    });

    test('omits the UI phase when the platform has no such anchor', () async {
      final tracker = _tracker(_native());
      await tracker.debugHandleTimings([_frame()]);
      final report = _measured(await tracker.initialDisplay);
      expect(report.phases.hostStartup, isNull,
          reason: 'iOS should get one fewer phase, not a fabricated one');
    });

    test('keeps launches whose vsync precedes Dart entry', () async {
      // The engine's frame pipeline ticks independently of when main() runs, so
      // this ordering is legitimate and must not discard the launch.
      final tracker = _tracker(_native(), dartMainUs: 1050);
      await tracker.debugHandleTimings([_frame(vsync: 1000)]);
      final report = _measured(await tracker.initialDisplay);

      expect(report.phases.frameScheduling, isNull,
          reason: 'the vsync boundary folds away rather than voiding the launch');
      expect(report.phases.dartBootstrap, greaterThan(Duration.zero));
      expect(_sum(report), report.timeToInitialDisplay);
    });

    test('ignores frames after the first', () async {
      final tracker = _tracker(_native());
      await tracker.debugHandleTimings([_frame()]);
      await tracker.debugHandleTimings([_frame(rasterFinish: 99999)]);
      final report = _measured(await tracker.initialDisplay);
      expect(report.timeToInitialDisplay, const Duration(microseconds: 1400));
    });
  });

  group('exclusion', () {
    test('drops prewarmed launches', () async {
      final tracker = _tracker(_native(isPrewarmed: true));
      await tracker.debugHandleTimings([_frame()]);
      final report = await tracker.initialDisplay;
      expect(report, isA<StartupExcluded>()
          .having((e) => e.reason, 'reason', ExclusionReason.prewarmed));
    });

    test('drops background launches', () async {
      final tracker = _tracker(_native(isBackgroundLaunch: true));
      await tracker.debugHandleTimings([_frame()]);
      expect((await tracker.initialDisplay) as StartupExcluded,
          isA<StartupExcluded>()
              .having((e) => e.reason, 'reason', ExclusionReason.backgroundLaunch));
    });

    test('drops launches past the plausibility ceiling', () async {
      // Process started 61s before the frame rasterized.
      final tracker = _tracker(
        _native(processStartUs: -61 * Duration.microsecondsPerSecond),
      );
      await tracker.debugHandleTimings([_frame()]);
      expect((await tracker.initialDisplay) as StartupExcluded,
          isA<StartupExcluded>()
              .having((e) => e.reason, 'reason', ExclusionReason.implausiblyLong));
    });

    test('drops timelines that run backwards', () async {
      // Platform init before process start is impossible; a clock moved.
      final tracker = _tracker(_native(processStartUs: 600, platformInitUs: 500));
      await tracker.debugHandleTimings([_frame()]);
      expect(
        await tracker.initialDisplay,
        isA<StartupExcluded>()
            .having((e) => e.reason, 'reason', ExclusionReason.incoherentTimeline),
      );
    });

    test('drops when the platform returns nothing', () async {
      final tracker = _tracker(null);
      await tracker.debugHandleTimings([_frame()]);
      expect(
        await tracker.initialDisplay,
        isA<StartupExcluded>()
            .having((e) => e.reason, 'reason', ExclusionReason.nativeDataUnavailable),
      );
    });

    test('survives a channel failure', () async {
      StartupMetricsPlatform.instance = _FakePlatform(_native())
        ..throwOnCall = true;
      final tracker = StartupTracker()..debugSetDartMain(_wall(800));
      await tracker.debugHandleTimings([_frame()]);
      expect(
        await tracker.initialDisplay,
        isA<StartupExcluded>()
            .having((e) => e.reason, 'reason', ExclusionReason.nativeDataUnavailable),
        reason: 'a dead channel must not leave initialDisplay() hanging',
      );
    });
  });

  group('full display', () {
    test('reports time to full display when the app declares it', () async {
      final tracker = _tracker(_native());
      await tracker.debugHandleTimings([_frame()]);
      await tracker.initialDisplay;

      tracker.reportFullyDisplayed();
      final full = _measured(await tracker.fullDisplay);

      expect(full.timeToFullDisplay, isNotNull);
      expect(full.timeToFullDisplay! >= full.timeToInitialDisplay, isTrue);
    });

    test('resolves with a null TTFD when the app never declares it', () async {
      StartupMetricsPlatform.instance = _FakePlatform(_native());
      final tracker = StartupTracker()
        ..debugSetDartMain(
          _wall(800),
          fullDisplayTimeout: const Duration(milliseconds: 10),
        );
      await tracker.debugHandleTimings([_frame()]);
      await tracker.initialDisplay;

      final full = _measured(await tracker.fullDisplay);
      expect(full.timeToFullDisplay, isNull,
          reason: 'an abandoned TTFD must resolve, not hang');
      tracker.dispose();
    });

    test('honours a full-display call made before the first frame', () async {
      final tracker = _tracker(_native());
      tracker.reportFullyDisplayed();
      await tracker.debugHandleTimings([_frame()]);

      final full = _measured(await tracker.fullDisplay);
      expect(full.timeToFullDisplay, isNotNull);
    });

    test('an excluded launch still resolves the full-display future', () async {
      final tracker = _tracker(_native(isPrewarmed: true));
      await tracker.debugHandleTimings([_frame()]);
      expect(await tracker.fullDisplay, isA<StartupExcluded>());
    });
  });
}
