/// Vendor-neutral cold-start measurement for Flutter.
///
/// Measures from OS process start to the first frame Flutter actually
/// rasterizes, and reports the phases in between. It does not send anything
/// anywhere — forward the report to whatever you already run.
library;

import 'src/startup_report.dart';
import 'src/startup_tracker.dart';

export 'src/startup_report.dart'
    show StartupReport, StartupPhase, LaunchType, ExclusionReason;

/// Entry point.
///
/// ```dart
/// void main() {
///   FlutterStartupMetrics.start();
///   runApp(const MyApp());
/// }
/// ```
///
/// Then, once your first screen has real content rather than a skeleton:
///
/// ```dart
/// FlutterStartupMetrics.reportFullyDisplayed();
/// ```
///
/// And wherever you report metrics:
///
/// ```dart
/// final report = await FlutterStartupMetrics.report;
/// if (report.isReportable) {
///   send('app.startup.ttid', report.timeToInitialDisplay!);
///   for (final phase in report.phases) {
///     send('app.startup.${phase.name}', phase.duration);
///   }
/// }
/// ```
abstract final class FlutterStartupMetrics {
  static final StartupTracker _tracker = StartupTracker();

  /// Begins measurement. Call as the first statement in `main()`.
  ///
  /// Calling it later still works but shortens the measured window, because the
  /// Dart-entry anchor is taken here.
  static void start({
    Duration fullDisplayTimeout = StartupTracker.defaultFullDisplayTimeout,
  }) =>
      _tracker.start(fullDisplayTimeout: fullDisplayTimeout);

  /// Resolves once Flutter has rasterized its first frame.
  ///
  /// Always resolves. An unusable launch — prewarmed, background-started, or
  /// with an incoherent timeline — resolves with an [ExclusionReason] instead of
  /// timings.
  static Future<StartupReport> get report => _tracker.report;

  /// Resolves when [reportFullyDisplayed] is called, or when the timeout passes.
  ///
  /// Separate from [report] so time-to-initial-display is not delayed by a call
  /// your app may never make.
  static Future<StartupReport> get fullDisplayReport =>
      _tracker.fullDisplayReport;

  /// Marks the app as meaningfully usable. Only your app knows when that is.
  static void reportFullyDisplayed() => _tracker.reportFullyDisplayed();
}
