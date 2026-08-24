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
flutter run --profile
```

Use `--profile` or `--release`, never `--debug`. Debug builds run the Dart VM in
JIT mode, which inflates startup by a factor of several and makes every number
this package produces meaningless.

## Verifying a change

Unit tests cover the clock conversion, the phase partition, and the exclusion
rules against fake platform data. They cannot tell you whether the native side
still works, so anything touching Kotlin or Swift needs a real cold launch:

```bash
cd example
flutter build apk --profile
adb install -r build/app/outputs/flutter-apk/app-profile.apk

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
