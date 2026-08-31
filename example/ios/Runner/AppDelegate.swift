import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Dart's print/debugPrint does not reach the iOS system log in release
    // builds, which is the only build mode worth measuring. This bridge lets the
    // example emit its report through NSLog so `idevicesyslog` can capture it
    // from a physical device. Example-only; the package logs nothing.
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: "example/device_log",
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        if call.method == "log", let message = call.arguments as? String {
          NSLog("%@", message)
          // Also append to a file in Documents. Device syslog is unreliable to
          // capture over USB on older iOS, and the container can be pulled with
          // `ios-deploy --download`.
          if let dir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first {
            let url = dir.appendingPathComponent("startup_reports.txt")
            let line = message + "\n\n"
            if let handle = try? FileHandle(forWritingTo: url) {
              handle.seekToEndOfFile()
              handle.write(Data(line.utf8))
              handle.closeFile()
            } else {
              try? line.write(to: url, atomically: true, encoding: .utf8)
            }
          }
        }
        result(nil)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
