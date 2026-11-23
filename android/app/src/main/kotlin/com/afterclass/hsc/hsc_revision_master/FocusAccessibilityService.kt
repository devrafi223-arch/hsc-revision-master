package com.afterclass.hsc.hsc_revision_master

import android.accessibilityservice.AccessibilityService
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.util.Calendar

/**
 * Focus Mode blocking, Android only.
 *
 * State lives in the service's own SharedPreferences file
 * "focus_prefs", written by MainActivity through the MethodChannel —
 * never Flutter's SharedPreferences file layout. The rules there are:
 * - KEY_ACTIVE / KEY_END: a manual focus session.
 * - KEY_SCHEDULE: weekly schedule JSON `{"1":[32,33,...]}` (day 1..7
 *   -> 15-minute block indices 0..95). Focus is active inside a
 *   blocked run even when no manual session exists, and even when
 *   the app itself is killed.
 * - KEY_LOCKED: a running session cannot be ended early — the overlay
 *   hides its End button until the timer finishes.
 * - KEY_CAPS: daily caps JSON `{"com.example.app":30}`. A cap is
 *   enforced all day, even outside a focus session, and beats the
 *   whitelist — a limit is a limit (HALT model).
 * - KEY_DISMISSED_UNTIL: until when a schedule block must not
 *   restart (set when the user ends a scheduled session early).
 *
 * On every TYPE_WINDOW_STATE_CHANGED event the foreground app is
 * checked: over-cap apps get a "daily limit reached" overlay; other
 * non-whitelisted apps during blocking get the focus overlay. The
 * overlay is a full-screen WindowManager view, so it consumes all
 * touches — the app underneath cannot be used.
 *
 * Stale sessions self-clear: [isFocusActive] returns false (and
 * clears the flag) once the stored end time has passed, so blocking
 * can never stay on forever if the app is killed mid-focus.
 *
 * Honest limits (also stated in the app UI): force-stopping this app,
 * turning the Accessibility service off in Settings, uninstalling,
 * or safe mode all stop the blocking. No normal app can prevent that.
 */
class FocusAccessibilityService : AccessibilityService() {

    companion object {
        const val PREFS_NAME = "focus_prefs"
        const val KEY_ACTIVE = "active"
        const val KEY_END = "endEpochMs"
        const val KEY_WHITELIST = "whitelist"
        const val KEY_LOCKED = "locked"
        const val KEY_SCHEDULE = "schedule"
        const val KEY_CAPS = "caps"
        const val KEY_DISMISSED_UNTIL = "dismissedUntilMs"
        const val OWN_PACKAGE = "com.afterclass.hsc.hsc_revision_master"

        fun isFocusActive(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_ACTIVE, false)) return false
            val end = prefs.getLong(KEY_END, 0L)
            if (end <= System.currentTimeMillis()) {
                prefs.edit().putBoolean(KEY_ACTIVE, false).apply()
                return false
            }
            return true
        }

        /** (blocking active, end epoch ms, locked) for manual sessions
         *  and scheduled blocks combined. */
        fun blockingState(context: Context): Triple<Boolean, Long, Boolean> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val locked = prefs.getBoolean(KEY_LOCKED, false)
            var end = 0L
            var active = false
            if (isFocusActive(context)) {
                active = true
                end = prefs.getLong(KEY_END, 0L)
            }
            val (scheduleActive, scheduleEnd) = scheduleState(context)
            if (scheduleActive) {
                active = true
                if (scheduleEnd > end) end = scheduleEnd
            }
            return Triple(active, end, locked)
        }

        /** (active now, end of the current blocked run) for the weekly
         *  schedule. Respects the dismiss-until time. */
        fun scheduleState(context: Context): Pair<Boolean, Long> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val dismissedUntil = prefs.getLong(KEY_DISMISSED_UNTIL, 0L)
            if (dismissedUntil > System.currentTimeMillis()) {
                return false to 0L
            }
            val jsonStr = prefs.getString(KEY_SCHEDULE, null) ?: return false to 0L
            return try {
                val obj = JSONObject(jsonStr)
                val cal = Calendar.getInstance()
                val day = when (cal.get(Calendar.DAY_OF_WEEK)) {
                    Calendar.MONDAY -> 1
                    Calendar.TUESDAY -> 2
                    Calendar.WEDNESDAY -> 3
                    Calendar.THURSDAY -> 4
                    Calendar.FRIDAY -> 5
                    Calendar.SATURDAY -> 6
                    else -> 7
                }
                val block = (cal.get(Calendar.HOUR_OF_DAY) * 60 +
                    cal.get(Calendar.MINUTE)) / 15
                val dayArr = obj.optJSONArray(day.toString())
                    ?: return false to 0L
                var blockedNow = false
                for (i in 0 until dayArr.length()) {
                    if (dayArr.getInt(i) == block) {
                        blockedNow = true
                        break
                    }
                }
                if (!blockedNow) return false to 0L
                // Walk forward while the blocks continue (across midnight).
                var cursorDay = day
                var cursorBlock = block
                var guard = 0
                while (guard++ < 96 * 2) {
                    val nextBlock = cursorBlock + 1
                    val (nextDay, nextIdx) = if (nextBlock >= 96) {
                        (if (cursorDay == 7) 1 else cursorDay + 1) to 0
                    } else {
                        cursorDay to nextBlock
                    }
                    val arr = obj.optJSONArray(nextDay.toString()) ?: break
                    var found = false
                    for (i in 0 until arr.length()) {
                        if (arr.getInt(i) == nextIdx) {
                            found = true
                            break
                        }
                    }
                    if (!found) break
                    cursorDay = nextDay
                    cursorBlock = nextIdx
                }
                // End = start of the block after the last blocked one.
                val daysAhead = (cursorDay - day + 7) % 7
                val endCal = Calendar.getInstance().apply {
                    add(Calendar.DAY_OF_YEAR, daysAhead)
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                endCal.add(Calendar.MINUTE, (cursorBlock + 1) * 15)
                true to endCal.timeInMillis
            } catch (_: Exception) {
                false to 0L
            }
        }
    }

    private enum class OverlayKind { NONE, FOCUS, CAP }

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private var timeView: TextView? = null
    private var overlayKind = OverlayKind.NONE
    private var overlayEndMs = 0L
    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            updateTime()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        // If a session was left active (app killed mid-focus), the stale
        // check in isFocusActive clears it on the next event; nothing to
        // do here until an app actually changes.
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == OWN_PACKAGE) {
            hideOverlay()
            return
        }
        // Daily caps beat everything, even the whitelist: a limit is a
        // limit, and it applies all day, not only during focus.
        val cap = capMinutesFor(pkg)
        if (cap != null && isOverCap(pkg, cap)) {
            showCapOverlay(pkg, cap)
            return
        }
        val (active, endMs, locked) = blockingState(this)
        if (!active) {
            hideOverlay()
            return
        }
        if (isWhitelisted(pkg)) {
            hideOverlay()
            return
        }
        showFocusOverlay(endMs, locked)
    }

    override fun onInterrupt() {
        hideOverlay()
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }

    private fun isWhitelisted(pkg: String): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getStringSet(KEY_WHITELIST, emptySet())?.contains(pkg) == true
    }

    private fun capMinutesFor(pkg: String): Int? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val jsonStr = prefs.getString(KEY_CAPS, null) ?: return null
        return try {
            val cap = JSONObject(jsonStr).optInt(pkg, 0)
            if (cap > 0) cap else null
        } catch (_: Exception) {
            null
        }
    }

    private fun isOverCap(pkg: String, capMinutes: Int): Boolean {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return false
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
        ) ?: return false
        var totalMs = 0L
        for (stat in stats) {
            if (stat.packageName == pkg) totalMs += stat.totalTimeInForeground
        }
        return totalMs >= capMinutes * 60_000L
    }

    private fun endFocus() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit().putBoolean(KEY_ACTIVE, false)
        // Ending early during a scheduled block: don't let the block
        // restart on the next event — dismiss it until the run ends.
        val (scheduleActive, scheduleEnd) = scheduleState(this)
        if (scheduleActive) {
            editor.putLong(KEY_DISMISSED_UNTIL, scheduleEnd)
        }
        editor.apply()
        hideOverlay()
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(intent)
    }

    private fun updateTime() {
        val view = timeView ?: return
        if (overlayKind != OverlayKind.FOCUS) return
        val remainingMs = overlayEndMs - System.currentTimeMillis()
        if (remainingMs <= 0) {
            // Session ended on its own: stop blocking.
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ACTIVE, false)
                .apply()
            hideOverlay()
            return
        }
        val totalSeconds = remainingMs / 1000
        val minutes = (totalSeconds / 60).toString().padStart(2, '0')
        val seconds = (totalSeconds % 60).toString().padStart(2, '0')
        view.text = "$minutes:$seconds"
    }

    private fun showFocusOverlay(endMs: Long, locked: Boolean) {
        if (overlayKind == OverlayKind.FOCUS && overlayView != null) {
            overlayEndMs = endMs
            updateTime()
            return
        }
        hideOverlay()
        val endLabel = if (locked) {
            val cal = Calendar.getInstance().apply { timeInMillis = endMs }
            val hour = cal.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
            val minute = cal.get(Calendar.MINUTE).toString().padStart(2, '0')
            "Locked — ends at $hour:$minute, cannot be stopped early."
        } else {
            null
        }
        val root = buildOverlay(
            title = "Focus cholche",
            sub = "Ei app-ta ekhon bondho.\nPorashona shesh kore abar khulbe.",
            showTimer = true,
            note = endLabel,
            buttonLabel = if (locked) null else "End focus",
            onButton = if (locked) null else ::endFocus,
        ) ?: return
        overlayKind = OverlayKind.FOCUS
        overlayEndMs = endMs
        updateTime()
        handler.postDelayed(ticker, 1000)
    }

    private fun showCapOverlay(pkg: String, capMinutes: Int) {
        if (overlayKind == OverlayKind.CAP && overlayView != null) return
        hideOverlay()
        val label = try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(pkg, 0)
            ).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            pkg
        }
        val root = buildOverlay(
            title = "Daily limit reached",
            sub = "$label — you have used your $capMinutes minutes today.\n"
                + "It opens again tomorrow.",
            showTimer = false,
            note = null,
            buttonLabel = "Go back",
            onButton = {
                hideOverlay()
                performGlobalAction(GLOBAL_ACTION_HOME)
            },
        ) ?: return
        overlayKind = OverlayKind.CAP
    }

    /**
     * Builds the calm full-screen block overlay. Returns the root view,
     * or null when no overlay permission is granted (the Dart side
     * tells the user to grant it first and never claims blocking
     * works without it). Full-screen and focusable: it consumes every
     * touch, so the app underneath cannot be used, and the button
     * works (no FLAG_NOT_FOCUSABLE — that would make it untappable).
     */
    private fun buildOverlay(
        title: String,
        sub: String,
        showTimer: Boolean,
        note: String?,
        buttonLabel: String?,
        onButton: (() -> Unit)?,
    ): FrameLayout? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)
        ) {
            return null
        }
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#F8F6F1"))
        }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }
        val titleView = TextView(this).apply {
            text = title
            textSize = 28f
            setTextColor(Color.parseColor("#1C1A17"))
            gravity = Gravity.CENTER
        }
        val subView = TextView(this).apply {
            text = sub
            textSize = 16f
            setTextColor(Color.parseColor("#6F6A62"))
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 0)
        }
        layout.addView(titleView)
        layout.addView(subView)
        if (showTimer) {
            timeView = TextView(this).apply {
                textSize = 40f
                setTextColor(Color.parseColor("#A9716B"))
                gravity = Gravity.CENTER
                setPadding(0, 32, 0, 0)
            }
            layout.addView(timeView)
        }
        if (note != null) {
            val noteView = TextView(this).apply {
                text = note
                textSize = 15f
                setTextColor(Color.parseColor("#A9716B"))
                gravity = Gravity.CENTER
                setPadding(0, 24, 0, 0)
            }
            layout.addView(noteView)
        }
        if (buttonLabel != null && onButton != null) {
            val button = Button(this).apply {
                text = buttonLabel
                setOnClickListener { onButton() }
            }
            val buttonParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = 48
                gravity = Gravity.CENTER
            }
            layout.addView(button, buttonParams)
        }
        root.addView(
            layout,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        )

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        overlayView = root
        wm.addView(root, params)
        return root
    }

    private fun hideOverlay() {
        handler.removeCallbacks(ticker)
        overlayKind = OverlayKind.NONE
        overlayEndMs = 0L
        val view = overlayView ?: return
        overlayView = null
        timeView = null
        try {
            windowManager?.removeView(view)
        } catch (_: IllegalArgumentException) {
            // View was already removed; nothing to do.
        }
        windowManager = null
    }
}
