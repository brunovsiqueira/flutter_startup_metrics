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
  Widget build(BuildContext context) => const MaterialApp(home: Launcher());
}

/// The case that makes time-to-full-display awkward in real apps: which screen
/// the user lands on is not known until an async check has run, so there is no
/// single place to report from. Every branch that can be a first screen needs
/// the call, and missing one means those launches silently report no TTFD.
class Launcher extends StatefulWidget {
  const Launcher({super.key});

  @override
  State<Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<Launcher> {
  Widget? _screen;

  @override
  void initState() {
    super.initState();
    _resolveFirstScreen();
  }

  Future<void> _resolveFirstScreen() async {
    // Stands in for reading a token, checking onboarding state, or resolving a
    // deep link — work that happens after the first frame has already painted.
    final signedIn = await _fakeAuthCheck();
    if (!mounted) return;
    setState(() => _screen = signedIn ? const Dashboard() : const SignIn());
  }

  Future<bool> _fakeAuthCheck() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return true;
  }

  @override
  Widget build(BuildContext context) =>
      _screen ?? const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// A first screen with its own async work. Reports once the content is real.
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _data = 'Dashboard content');

    // The call site: after the state that makes the screen useful. Not on a
    // timer, not in build(), and not in main() — at main() nothing is displayed
    // yet, so reporting there would make TTFD meaningless.
    FlutterStartupMetrics.reportFullyDisplayed();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Startup metrics')),
        body: _data == null
            ? const Center(child: CircularProgressIndicator())
            : const StartupSummary(),
      );
}

/// The other possible first screen. It has nothing to wait for, so it reports as
/// soon as it is built — but it still has to report, or launches that land here
/// would have no TTFD at all.
class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterStartupMetrics.reportFullyDisplayed();
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Sign in')),
      );
}

/// Reads the report and renders whichever outcome the launch produced.
class StartupSummary extends StatelessWidget {
  const StartupSummary({super.key});

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
        return switch (report) {
          StartupExcluded(:final reason) =>
            Center(child: Text('Launch not measured: ${reason.name}')),
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
    // How you would forward the whole breakdown in one call.
    debugPrint('STARTUP_METRICS $report');

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
        for (final entry in report.phases.toMap().entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key),
                Text('${entry.value.inMicroseconds / 1000} ms'),
              ],
            ),
          ),
      ],
    );
  }
}
