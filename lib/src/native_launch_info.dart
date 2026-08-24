import 'package:meta/meta.dart';

import 'startup_report.dart';

/// The launch facts only native code can see.
///
/// Flutter has no view of process start — its own earliest timestamp is recorded
/// at Dart VM init, well after the OS began the launch — so everything before
/// Dart has to cross the method channel.
@immutable
class NativeLaunchInfo {
  const NativeLaunchInfo({
    required this.processStart,
    required this.platformInit,
    required this.uiInit,
    required this.launchType,
    required this.isPrewarmed,
    required this.isBackgroundLaunch,
  });

  /// OS process start, in wall-clock time.
  final DateTime processStart;

  /// The earliest moment this library existed in the process — ContentProvider
  /// creation on Android, plugin registration on iOS.
  final DateTime platformInit;

  /// When the host created the UI container: the first `Activity.onCreate` on
  /// Android.
  ///
  /// Null on iOS, where plugin registration already happens inside
  /// `didFinishLaunchingWithOptions` and there is no comparable later boundary
  /// to split on. Consumers get one fewer phase rather than a fabricated one.
  final DateTime? uiInit;

  final LaunchType launchType;

  /// iOS only: the process was prewarmed by the OS before the user acted.
  final bool isPrewarmed;

  /// The process was started by the system rather than by the user.
  final bool isBackgroundLaunch;

  static NativeLaunchInfo? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final processStartUs = map['processStartEpochUs'];
    final platformInitUs = map['platformInitEpochUs'];
    if (processStartUs is! int || platformInitUs is! int) return null;

    final uiInitUs = map['uiInitEpochUs'];
    return NativeLaunchInfo(
      processStart: DateTime.fromMicrosecondsSinceEpoch(
        processStartUs,
        isUtc: true,
      ),
      platformInit: DateTime.fromMicrosecondsSinceEpoch(
        platformInitUs,
        isUtc: true,
      ),
      uiInit:
          uiInitUs is int
              ? DateTime.fromMicrosecondsSinceEpoch(uiInitUs, isUtc: true)
              : null,
      launchType: switch (map['launchType']) {
        'cold' => LaunchType.cold,
        _ => LaunchType.unknown,
      },
      isPrewarmed: map['isPrewarmed'] == true,
      isBackgroundLaunch: map['isBackgroundLaunch'] == true,
    );
  }
}
