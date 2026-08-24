import 'package:flutter/services.dart';

import 'native_launch_info.dart';

/// Method-channel access to the native launch facts.
///
/// Deliberately not a `PlatformInterface` with a registrar: this package has one
/// implementation per platform and no extension story, so the indirection would
/// be ceremony. Swap the [instance] in tests.
class StartupMetricsPlatform {
  StartupMetricsPlatform();

  static StartupMetricsPlatform instance = StartupMetricsPlatform();

  static const MethodChannel _channel =
      MethodChannel('dev.brunosiqueira/flutter_startup_metrics');

  /// Returns null when the platform has no launch data — an unsupported OS
  /// version, or a platform with no native implementation.
  Future<NativeLaunchInfo?> getLaunchInfo() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('getLaunchInfo');
    return NativeLaunchInfo.fromMap(result);
  }
}
