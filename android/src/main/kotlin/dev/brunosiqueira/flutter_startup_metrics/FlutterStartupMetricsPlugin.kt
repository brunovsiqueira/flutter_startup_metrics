package dev.brunosiqueira.flutter_startup_metrics

import android.app.ActivityManager
import android.os.Build
import android.os.Process
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hands Dart the launch facts it cannot see: when the OS started this process,
 * when the platform reached its first library-observable moment, and whether the
 * launch was user-initiated at all.
 */
class FlutterStartupMetricsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger,
            "dev.brunosiqueira/flutter_startup_metrics",
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getLaunchInfo" -> result.success(launchInfo())
            else -> result.notImplemented()
        }
    }

    private fun launchInfo(): Map<String, Any?>? {
        // Absent means the provider never ran, so the library is not installed
        // the way it expects. Reporting nothing is the honest answer, and it
        // keeps every value below non-null.
        val providerUptimeMs = StartupMetricsInitProvider.createdAtUptimeMs ?: return null

        // Process.getStartUptimeMillis is API 24+. Below that, the earliest
        // knowable moment is our own ContentProvider, which is later than the
        // real process start but never earlier — so the metric under-reports
        // rather than inventing time.
        val processStartUptimeMs =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                sanityCheckedProcessStart(providerUptimeMs)
            } else {
                providerUptimeMs
            }

        // Sampled once so every anchor in a report shares the same conversion.
        // Sampling per anchor would fold clock drift into the phases.
        val skewMs = System.currentTimeMillis() - SystemClock.uptimeMillis()
        fun toEpochUs(uptimeMs: Long): Long = (uptimeMs + skewMs) * 1_000L

        val isBackground = StartupMetricsInitProvider.processImportance !=
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND

        return mapOf(
            "processStartEpochUs" to toEpochUs(processStartUptimeMs),
            "platformInitEpochUs" to toEpochUs(providerUptimeMs),
            // Splits Android's host-startup span, which is otherwise dominated by
            // Application and Activity setup and would be misattributed to Flutter.
            "uiInitEpochUs" to StartupMetricsInitProvider
                .firstActivityCreatedAtUptimeMs
                ?.let { toEpochUs(it) },
            // The provider runs exactly once per process, so a launch we can see
            // at all is a cold one. Warm starts reuse the process and are not
            // measurable from process start.
            "launchType" to "cold",
            "isBackgroundLaunch" to isBackground,
        )
    }

    /**
     * [Process.getStartUptimeMillis] has been observed returning implausible
     * values. Cross-check it against our provider: process start must precede
     * provider creation, and not by an absurd margin.
     */
    private fun sanityCheckedProcessStart(providerUptimeMs: Long): Long {
        val reported = Process.getStartUptimeMillis()
        val precedesProvider = reported <= providerUptimeMs
        val withinReason = providerUptimeMs - reported <= MAX_PROCESS_START_LEAD_MS
        return if (precedesProvider && withinReason) reported else providerUptimeMs
    }

    private companion object {
        /**
         * Kept in step with `StartupReport.maxPlausibleLaunch` on the Dart side.
         * The two are different checks — this one picks which timestamp to
         * trust, that one drops the report — but they encode the same judgement
         * about what counts as a plausible launch.
         */
        const val MAX_PROCESS_START_LEAD_MS = 60_000L
    }
}
