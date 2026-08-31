# Contributing

Thanks for taking an interest.

## Getting set up

```bash
flutter pub get
flutter test
flutter analyze
```

The example app is where the package is actually exercised end to end:

```bash
cd example
flutter run --release
```

Use `--release` for anything you intend to draw a conclusion from. Debug runs
the Dart VM in JIT mode and is meaningless for startup. Profile is AOT and looks
plausible, but on a Galaxy S25 it totals 180 ms against release's 83 ms — and
the *shares* move too, with the platform phases going from 15% of the launch to
69%. A profile-mode measurement will point you at the wrong phase.

Discard the first launch after an install; it runs 1.5–2× slower than the steady
state.

## Verifying a change

Unit tests cover the clock conversion, the phase partition, and the exclusion
rules against fake platform data. They cannot tell you whether the native side
still works, so anything touching Kotlin or Swift needs a real cold launch:

```bash
cd example
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

adb shell am force-stop dev.brunosiqueira.flutter_startup_metrics_example
adb shell am kill dev.brunosiqueira.flutter_startup_metrics_example
adb logcat -c
adb shell am start -W -n dev.brunosiqueira.flutter_startup_metrics_example/.MainActivity
adb logcat -d | grep STARTUP_METRICS
```

Force-stop *and* kill: without both you measure a warm start, and warm starts
report `LaunchType.unknown` rather than failing loudly.

Two properties are worth checking by eye on every native change, because a bug
in either produces plausible-looking numbers rather than an error:

- the phases sum to the reported time to initial display
- time to full display is never smaller than time to initial display

## Things to keep in mind

**Everything here runs on the startup critical path.** Work the package does is
work it adds to the thing it is measuring. Prefer deferring anything that does
not have to happen before the first frame.

**A wrong number is worse than no number.** When a launch cannot be measured
honestly, return a `StartupExcluded` with a reason rather than a plausible
value. The one exception is clamping time to full display up to time to initial
display, where the ordering is true by definition and the discrepancy is clock
noise between two sources.

**Emulator numbers are not device numbers.** The share of time attributed to
each phase differs substantially between an emulator and real hardware. Claims
about where startup time goes need a physical device.

**You cannot get a clean startup number off a cabled iPhone.** iOS terminates a
developer-signed app the moment the debugger detaches, so
`example/run_ios_device.sh` has to keep `debugserver` attached for the launch it
is measuring — and that added roughly 900 ms to process start on an iPhone 8,
against tens of milliseconds for the same phase on Android.

This is a property of the test rig, not of iOS or of this package. A user who
taps the app icon on their own phone has no debugger attached and sees normal
timings. So use on-device iOS runs to verify *behaviour* — phases contiguous,
`hostStartup` absent, nothing falsely excluded — and never to quote a magnitude.
For real iOS numbers, ship a TestFlight or App Store build and read what the
package reports in the field.
