package com.afterclass.hsc.hsc_revision_master

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.afterclass.hsc/focus"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> result.success(getInstalledApps())
                "startFocus" -> {
                    val whitelist =
                        call.argument<List<String>>("whitelist") ?: emptyList()
                    val endEpochMs =
                        (call.argument<Number>("endEpochMs")?.toLong()) ?: 0L
                    val prefs = getSharedPreferences(
                        FocusAccessibilityService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    prefs.edit()
                        .putBoolean(FocusAccessibilityService.KEY_ACTIVE, true)
                        .putLong(FocusAccessibilityService.KEY_END, endEpochMs)
                        .putStringSet(
                            FocusAccessibilityService.KEY_WHITELIST,
                            whitelist.toSet()
                        )
                        .putBoolean(
                            FocusAccessibilityService.KEY_LOCKED,
                            call.argument<Boolean>("locked") ?: false
                        )
                        .putString(
                            FocusAccessibilityService.KEY_SCHEDULE,
                            call.argument<String>("schedule") ?: "{}"
                        )
                        .putString(
                            FocusAccessibilityService.KEY_CAPS,
                            call.argument<String>("caps") ?: "{}"
                        )
                        .putLong(
                            FocusAccessibilityService.KEY_DISMISSED_UNTIL,
                            (call.argument<Number>("dismissedUntilMs")?.toLong()) ?: 0L
                        )
                        .apply()
                    result.success(null)
                }
                // Push schedule / locked / caps rules without starting or
                // stopping a session, so the service can enforce scheduled
                // blocks and daily caps on its own.
                "syncBlocking" -> {
                    getSharedPreferences(
                        FocusAccessibilityService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    ).edit()
                        .putString(
                            FocusAccessibilityService.KEY_SCHEDULE,
                            call.argument<String>("schedule") ?: "{}"
                        )
                        .putBoolean(
                            FocusAccessibilityService.KEY_LOCKED,
                            call.argument<Boolean>("locked") ?: false
                        )
                        .putString(
                            FocusAccessibilityService.KEY_CAPS,
                            call.argument<String>("caps") ?: "{}"
                        )
                        .putLong(
                            FocusAccessibilityService.KEY_DISMISSED_UNTIL,
                            (call.argument<Number>("dismissedUntilMs")?.toLong()) ?: 0L
                        )
                        .apply()
                    result.success(null)
                }
                "getDailyUsage" -> result.success(getDailyUsage())
                "stopFocus" -> {
                    getSharedPreferences(
                        FocusAccessibilityService.PREFS_NAME,
                        Context.MODE_PRIVATE
                    ).edit()
                        .putBoolean(FocusAccessibilityService.KEY_ACTIVE, false)
                        .apply()
                    result.success(null)
                }
                "isFocusActive" ->
                    result.success(FocusAccessibilityService.isFocusActive(this))
                "checkPermissions" -> result.success(
                    mapOf(
                        "accessibility" to isAccessibilityServiceEnabled(),
                        "overlay" to Settings.canDrawOverlays(this),
                        "usage" to hasUsageAccess()
                    )
                )
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "openOverlaySettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(null)
                }
                "openUsageSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                // App info screen — needed for the "Allow restricted
                // settings" step on Android 13+ sideloaded APKs.
                "openAppInfo" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /// Today's foreground minutes per package. Empty when usage access
    /// is not granted (the query then returns nothing).
    private fun getDailyUsage(): Map<String, Int> {
        if (!hasUsageAccess()) return emptyMap()
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val startOfDay = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startOfDay,
            System.currentTimeMillis()
        ) ?: return emptyMap()
        val totals = mutableMapOf<String, Long>()
        for (stat in stats) {
            val total = totals.getOrDefault(stat.packageName, 0L) +
                stat.totalTimeInForeground
            totals[stat.packageName] = total
        }
        return totals
            .mapValues { (_, ms) -> (ms / 60_000L).toInt() }
            .filterValues { it > 0 }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                android.content.pm.PackageManager.ResolveInfoFlags.of(0L)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        return resolveInfos
            .mapNotNull { info ->
                val pkg = info.activityInfo.packageName ?: return@mapNotNull null
                if (pkg == packageName) return@mapNotNull null // this app is always allowed
                val label = info.loadLabel(packageManager)?.toString() ?: pkg
                mapOf("label" to label, "packageName" to pkg)
            }
            .sortedBy { it["label"]?.lowercase() }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expected = ComponentName(
            this,
            FocusAccessibilityService::class.java
        ).flattenToString()
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return TextUtils.SimpleStringSplitter(':').let { splitter ->
            splitter.setString(enabled)
            var found = false
            while (splitter.hasNext()) {
                if (splitter.next() == expected) {
                    found = true
                    break
                }
            }
            found
        }
    }
}
