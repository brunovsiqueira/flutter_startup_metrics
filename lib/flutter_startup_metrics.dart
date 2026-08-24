/// Vendor-neutral cold-start measurement for Flutter.
///
/// Measures from OS process start to the first frame Flutter actually
/// rasterizes, and reports the phases in between. It does not send anything
/// anywhere — forward the report to whatever you already run.
library;

import 'src/startup_report.dart';
import 'src/startup_tracker.dart';

export 'src/startup_report.dart'
    show
        ExclusionReason,
        LaunchType,
        StartupExcluded,
        StartupMeasurement,
        StartupPhase,
        StartupPhases,
        StartupReport;

/// Entry point.
///
/// ```dart
/// void main() {
///   FlutterStartupMetrics.start();
///   runApp(const MyApp());
/// }
/// ```
abstract final class FlutterStartupMetrics {
  static final StartupTracker _tracker = StartupTracker();

  /// How long [fullDisplay] waits for [reportFullyDisplayed] before giving up.
  ///
  /// Matches Sentry's, and exists so an app that never makes the call leaves a
  /// resolved future rather than a permanently pending one.
  static const Duration defaultFullDisplayTimeout = Duration(seconds: 30);

  /// Begins measurement. Call as the first statement in `main()`.
  ///
  /// Calling it later still works but shortens the measured window, because the
  /// Dart-entry anchor is taken here.
  static void start({
    Duration fullDisplayTimeout = defaultFullDisplayTimeout,
  }) => _tracker.start(fullDisplayTimeout: fullDisplayTimeout);

  /// Resolves once Flutter has rasterized its first frame — typically within a
  /// second of launch.
  ///
  /// Always resolves. A launch that cannot be measured honestly arrives as
  /// [StartupExcluded] with a reason, never as a throw or a hang.
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
  static Future<StartupReport> get initialDisplay => _tracker.initialDisplay;

  /// Resolves when [reportFullyDisplayed] is called, or when the timeout passes.
  ///
  /// Asynchronous because it waits on a call only your app can make, and that
  /// call happens after data loads. It is deliberately a second future rather
  /// than folded into [initialDisplay]: time-to-initial-display is available in
  /// milliseconds and should not be held back by something that may take
  /// seconds, or never arrive at all.
  ///
  /// Resolves as a [StartupMeasurement] with a null `timeToFullDisplay` if the
  /// deadline passes without a call — so awaiting this is always safe.
  static Future<StartupReport> get fullDisplay => _tracker.fullDisplay;

  /// Marks the app as meaningfully usable: first screen populated with real
  /// content, not a skeleton or a spinner.
  ///
  /// Nothing can infer this, which is why it is your call to make. Typically it
  /// goes wherever your first screen stops loading:
  ///
  /// ```dart
  /// final data = await repository.loadDashboard();
  /// setState(() => _data = data);
  /// FlutterStartupMetrics.reportFullyDisplayed();
  /// ```
  ///
  /// Second and late calls are ignored.
  static void reportFullyDisplayed() => _tracker.reportFullyDisplayed();
}
