package dev.brunosiqueira.flutter_startup_metrics

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock

/**
 * Records the earliest timestamp this library can reach on Android.
 *
 * ContentProviders are created before `Application.onCreate` returns, so this
 * runs earlier than any plugin registration and earlier than the first Activity.
 * It is declared in this library's own manifest, so it merges into host apps
 * with no setup on their part.
 *
 * The provider does nothing else — it exists purely for its creation time.
 */
class StartupMetricsInitProvider : ContentProvider() {

    override fun onCreate(): Boolean {
        createdAtUptimeMs = SystemClock.uptimeMillis()
        // Process importance is only meaningful at process creation. Read it now:
        // by the time a launch finishes, a background-started process that the
        // user later opened looks identical to a foreground one.
        processImportance = readProcessImportance()
        observeFirstActivity()
        return true
    }

    /**
     * Records when the first Activity is created.
     *
     * Without this boundary the whole span from process init to Dart entry
     * collapses into one phase, and on Android that phase is dominated by
     * Application and Activity setup rather than by anything Flutter does —
     * which is precisely the attribution the breakdown exists to provide.
     *
     * Registering here works because a ContentProvider is created before
     * `Application.onCreate` returns, so no Activity can have been created yet.
     */
    private fun observeFirstActivity() {
        val app = context?.applicationContext as? Application ?: return
        app.registerActivityLifecycleCallbacks(
            object : Application.ActivityLifecycleCallbacks {
                override fun onActivityCreated(activity: Activity, bundle: Bundle?) {
                    if (firstActivityCreatedAtUptimeMs == null) {
                        firstActivityCreatedAtUptimeMs = SystemClock.uptimeMillis()
                    }
                    app.unregisterActivityLifecycleCallbacks(this)
                }

                override fun onActivityStarted(activity: Activity) = Unit
                override fun onActivityResumed(activity: Activity) = Unit
                override fun onActivityPaused(activity: Activity) = Unit
                override fun onActivityStopped(activity: Activity) = Unit
                override fun onActivitySaveInstanceState(activity: Activity, out: Bundle) = Unit
                override fun onActivityDestroyed(activity: Activity) = Unit
            },
        )
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private fun readProcessImportance(): Int {
        val info = ActivityManager.RunningAppProcessInfo()
        return try {
            ActivityManager.getMyMemoryState(info)
            info.importance
        } catch (e: RuntimeException) {
            // Defaults to IMPORTANCE_FOREGROUND, which biases towards reporting
            // rather than silently dropping every launch on a broken device.
            info.importance
        }
    }

    companion object {
        /**
         * Uptime-domain timestamp of provider creation, or null if this process
         * somehow never ran it (which would mean the library is not installed
         * the way it expects).
         */
        @Volatile
        @JvmStatic
        var createdAtUptimeMs: Long? = null
            private set

        /** Uptime-domain timestamp of the first Activity's onCreate. */
        @Volatile
        @JvmStatic
        var firstActivityCreatedAtUptimeMs: Long? = null
            private set

        @Volatile
        @JvmStatic
        var processImportance: Int = ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            private set
    }
}
