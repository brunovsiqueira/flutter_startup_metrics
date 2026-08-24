import Flutter
import UIKit

/// Hands Dart the launch facts it cannot see: when the OS started this process,
/// when this library first existed, and whether the launch was user-initiated.
public class FlutterStartupMetricsPlugin: NSObject, FlutterPlugin {

    /// Captured at plugin registration, which the app performs inside
    /// `didFinishLaunchingWithOptions`.
    ///
    /// This is the earliest moment reachable without shipping an Objective-C
    /// `+load` or a C constructor, and it is deliberately not one: the pre-main
    /// dyld phase is real but attributing it needs machinery disproportionate to
    /// a package this size. The consequence is that `platformInit` on iOS means
    /// "library loaded", not "process reached main", and everything before it is
    /// folded into the first phase.
    private static var registrationDate: Date?
    private static var wasBackgroundAtRegistration = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        registrationDate = Date()
        // applicationState must be read on the main thread; registration is.
        wasBackgroundAtRegistration =
            UIApplication.shared.applicationState == .background

        let channel = FlutterMethodChannel(
            name: "dev.brunosiqueira/flutter_startup_metrics",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(
            FlutterStartupMetricsPlugin(), channel: channel
        )
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "getLaunchInfo":
            result(Self.launchInfo())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func launchInfo() -> [String: Any]? {
        guard let processStart = processStartDate(),
              let registration = registrationDate
        else { return nil }

        // iOS 15+ may start the process well before the user taps the icon. When
        // it does, process start is not the start of anything the user
        // experienced, and the only honest move is to report nothing.
        // getenv rather than ProcessInfo.environment, which materializes and
        // bridges the entire environment dictionary to read one key.
        let isPrewarmed = getenv("ActivePrewarm").map { String(cString: $0) } == "1"

        return [
            "processStartEpochUs": epochMicros(processStart),
            "platformInitEpochUs": epochMicros(registration),
            // The plugin registers once per process, so any launch we observe at
            // all is a process creation. A resumed app never reaches here.
            "launchType": "cold",
            "isPrewarmed": isPrewarmed,
            "isBackgroundLaunch": wasBackgroundAtRegistration,
        ]
    }

    /// Process start via `sysctl(KERN_PROC_PID)`.
    ///
    /// `p_starttime` is a wall-clock `timeval`, so a clock adjustment during
    /// launch shifts it. There is no monotonic equivalent exposed for process
    /// start on Darwin; the ordering checks on the Dart side are what catch the
    /// resulting anomalies.
    private static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        let seconds = Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
        return Date(timeIntervalSince1970: seconds)
    }

    private static func epochMicros(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1_000_000).rounded())
    }
}
