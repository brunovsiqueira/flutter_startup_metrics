import 'package:flutter/material.dart';
import 'package:flutter_startup_metrics/flutter_startup_metrics.dart';

void main() {
  // First statement: the Dart-entry anchor is taken here, so anything above it
  // is attributed to the previous phase instead.
  FlutterStartupMetrics.start();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: DashboardScreen());
}

/// Stands in for a real first screen: it paints immediately with a spinner, then
/// fills in once its data arrives. The gap between those two moments is exactly
/// what time-to-full-display measures, and why nothing but the app can report it.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _data;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    // Whatever your first screen actually waits on: an API call, a database
    // read, an auth check.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    setState(() => _data = 'Dashboard content');

    // The screen now holds real content rather than a spinner. This is the call
    // site: after the state that makes the screen useful, not on a timer and not
    // in build().
    FlutterStartupMetrics.reportFullyDisplayed();

    // In a real app this is where you would forward the numbers to whatever you
    // already run — a RUM SDK, an analytics event, a log line.
    final report = await FlutterStartupMetrics.fullDisplay;
    debugPrint('STARTUP_METRICS $report');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Startup metrics')),
      body: _data == null
          ? const Center(child: CircularProgressIndicator())
          : const _StartupSummary(),
    );
  }
}

/// Reads both reports and renders whichever outcome the launch produced.
class _StartupSummary extends StatelessWidget {
  const _StartupSummary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StartupReport>(
      // fullDisplay resolves once reportFullyDisplayed() lands, or after the
      // timeout. Use initialDisplay instead if you only want TTID.
      future: FlutterStartupMetrics.fullDisplay,
      builder: (context, snapshot) {
        final report = snapshot.data;
        if (report == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // Sealed, so this is exhaustive and needs no null checks.
        return switch (report) {
          StartupExcluded(:final reason) => Center(
              child: Text('Launch not measured: ${reason.name}'),
            ),
          StartupMeasurement() => _MeasurementView(report),
        };
      },
    );
  }
}

class _MeasurementView extends StatelessWidget {
  const _MeasurementView(this.report);

  final StartupMeasurement report;

  @override
  Widget build(BuildContext context) {
    final phases = report.phases;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Time to initial display: '
          '${report.timeToInitialDisplay.inMilliseconds} ms',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (report.timeToFullDisplay case final ttfd?)
          Text('Time to full display: ${ttfd.inMilliseconds} ms'),
        Text('Launch type: ${report.launchType.name}'),
        const Divider(height: 32),

        // Named access, for the fixed set of metrics you care about.
        _Row('engineBoot', phases.engineBoot),
        _Row('frameRaster', phases.frameRaster),
        const Divider(height: 32),

        // Or iterate, to forward whatever this platform produced without
        // enumerating it.
        for (final phase in phases.all) _Row(phase.name, phase.duration),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.duration);

  final String label;
  final Duration duration;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${duration.inMicroseconds / 1000} ms'),
          ],
        ),
      );
}
