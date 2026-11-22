package com.afterclass.hsc.hsc_revision_master

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
                        .apply()
                    result.success(null)
                }
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
                        "overlay" to Settings.canDrawOverlays(this)
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
                else -> result.notImplemented()
            }
        }
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
