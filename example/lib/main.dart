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
  Widget build(BuildContext context) => const MaterialApp(home: ReportScreen());
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  StartupReport? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final report = await FlutterStartupMetrics.report;

    // Pretend the first screen needed data before it was truly usable. A real
    // app would call this once its content is populated, not on a timer.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    FlutterStartupMetrics.reportFullyDisplayed();

    final full = await FlutterStartupMetrics.fullDisplayReport;
    debugPrint('STARTUP_METRICS $full');
    if (mounted) setState(() => _report = full.isReportable ? full : report);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Startup metrics')),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!report.isReportable)
                  Text(
                    'Not reportable: ${report.exclusion!.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  )
                else ...[
                  Text(
                    'Time to initial display: '
                    '${report.timeToInitialDisplay!.inMilliseconds} ms',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (report.timeToFullDisplay case final ttfd?)
                    Text('Time to full display: ${ttfd.inMilliseconds} ms'),
                  Text('Launch type: ${report.launchType.name}'),
                  const Divider(height: 32),
                  for (final phase in report.phases)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(phase.name),
                          Text('${phase.duration.inMicroseconds / 1000} ms'),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
