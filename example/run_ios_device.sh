#!/bin/bash
# Cold-launch the example on a physical iPhone N times and print each report.
#
# Prerequisites, once per device:
#   1. Settings > General > VPN & Device Management > trust your developer cert.
#   2. Accept the "Trust This Computer?" dialog when prompted over USB.
#
# The app writes each report into its Documents container rather than logging it,
# because Dart's print does not reach the iOS system log in release builds and
# USB syslog capture is unreliable on older iOS. The container is pulled at the
# end with `ios-deploy --download`.
#
# usage: ./run_ios_device.sh [runs]
set -u
N=${1:-10}
DEV=74c76d4dc782a2a68424328b164747fbef487236
APP=build/ios/iphoneos/Runner.app
BUNDLE=dev.brunosiqueira.flutterStartupMetricsExample
IOSDEPLOY=~/development/flutter/bin/cache/artifacts/ios-deploy/ios-deploy
OUT=/tmp/ios_device_reports

for i in $(seq 1 "$N"); do
  # Launch attached and detach after the app has reported. --justlaunch would be
  # cleaner, but iOS terminates the app as soon as the debugger goes away, which
  # happens before the example finishes its simulated first-screen load.
  #
  # This means the debugger is attached during the measured launch. Treat these
  # numbers as an upper bound: debugserver adds real overhead to process start.
  "$IOSDEPLOY" --id "$DEV" --bundle "$APP" --noinstall --noninteractive \
    >/dev/null 2>&1 &
  sleep 14
  pkill -f ios-deploy >/dev/null 2>&1
  sleep 2
  echo "run $i done"
done

rm -rf "$OUT"
"$IOSDEPLOY" --id "$DEV" --bundle_id "$BUNDLE" --download=/Documents --to "$OUT" \
  >/dev/null 2>&1
echo "--- reports ---"
cat "$OUT/Documents/startup_reports.txt" 2>/dev/null
