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
        val providerUptimeMs = StartupMetricsInitProvider.createdAtUptimeMs

        // Process.getStartUptimeMillis is API 24+. Below that, the earliest
        // knowable moment is our own ContentProvider, which is later than the
        // real process start but never earlier — so the metric under-reports
        // rather than inventing time.
        val processStartUptimeMs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            sanityCheckedProcessStart(providerUptimeMs)
        } else {
            providerUptimeMs
        } ?: return null

        val platformInitUptimeMs = providerUptimeMs ?: processStartUptimeMs

        val isBackground = StartupMetricsInitProvider.processImportance !=
            ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND

        return mapOf(
            "processStartEpochUs" to uptimeMsToEpochUs(processStartUptimeMs),
            "platformInitEpochUs" to uptimeMsToEpochUs(platformInitUptimeMs),
            // Splits Android's host-startup span, which is otherwise dominated by
            // Application and Activity setup and would be misattributed to Flutter.
            "uiInitEpochUs" to StartupMetricsInitProvider
                .firstActivityCreatedAtUptimeMs
                ?.let { uptimeMsToEpochUs(it) },
            // This library only ever observes a process it was loaded into, and
            // the provider runs exactly once per process, so a launch we can see
            // at all is a cold one. Warm starts reuse the process and are not
            // measurable from process start; say "unknown" rather than guess.
            "launchType" to if (providerUptimeMs != null) "cold" else "unknown",
            "isPrewarmed" to false, // iOS-only concept
            "isBackgroundLaunch" to isBackground,
        )
    }

    /**
     * [Process.getStartUptimeMillis] has been observed returning implausible
     * values. Cross-check it against our provider: process start must precede
     * provider creation, and not by an absurd margin.
     */
    private fun sanityCheckedProcessStart(providerUptimeMs: Long?): Long? {
        val reported = Process.getStartUptimeMillis()
        if (providerUptimeMs == null) return reported
        val precedesProvider = reported <= providerUptimeMs
        val withinReason = providerUptimeMs - reported <= MAX_PROCESS_START_LEAD_MS
        return if (precedesProvider && withinReason) reported else providerUptimeMs
    }

    /**
     * Converts an uptime-domain value to wall-clock epoch microseconds.
     *
     * The skew is sampled once, here, so every anchor in a report shares the same
     * conversion. Sampling it per-anchor would fold clock drift into the phases.
     */
    private fun uptimeMsToEpochUs(uptimeMs: Long): Long {
        val skewMs = System.currentTimeMillis() - SystemClock.uptimeMillis()
        return (uptimeMs + skewMs) * 1_000L
    }

    private companion object {
        const val MAX_PROCESS_START_LEAD_MS = 60_000L
    }
}
