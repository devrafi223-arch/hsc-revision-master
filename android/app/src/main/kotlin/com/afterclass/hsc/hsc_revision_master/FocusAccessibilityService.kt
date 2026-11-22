package com.afterclass.hsc.hsc_revision_master

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
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

/**
 * Focus Mode blocking, Android only.
 *
 * While a focus session is active (state lives in the service's own
 * SharedPreferences file "focus_prefs", written by MainActivity through
 * the MethodChannel — never Flutter's SharedPreferences file layout),
 * every TYPE_WINDOW_STATE_CHANGED event is checked: if the new foreground
 * app is not this app and not in the whitelist, a calm full-screen
 * block overlay is shown over it. The overlay itself is a full-screen
 * WindowManager view, so it consumes all touches — the app underneath
 * cannot be used. "End focus" on the overlay stops the session and
 * brings the revision app back.
 *
 * Stale sessions self-clear: [isFocusActive] returns false (and clears
 * the flag) once the stored end time has passed, so blocking can never
 * stay on forever if the app is killed mid-focus.
 */
class FocusAccessibilityService : AccessibilityService() {

    companion object {
        const val PREFS_NAME = "focus_prefs"
        const val KEY_ACTIVE = "active"
        const val KEY_END = "endEpochMs"
        const val KEY_WHITELIST = "whitelist"
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
    }

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private var timeView: TextView? = null
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
        if (!isFocusActive(this)) {
            hideOverlay()
            return
        }
        val pkg = event.packageName?.toString() ?: return
        if (pkg == OWN_PACKAGE || isWhitelisted(pkg)) {
            hideOverlay()
            return
        }
        showOverlay()
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

    private fun endEpochMs(): Long {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_END, 0L)
    }

    private fun endFocus() {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ACTIVE, false)
            .apply()
        hideOverlay()
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(intent)
    }

    private fun updateTime() {
        val view = timeView ?: return
        val remainingMs = endEpochMs() - System.currentTimeMillis()
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

    private fun showOverlay() {
        if (overlayView != null) {
            updateTime()
            return
        }
        // No overlay permission, no overlay — the Dart side tells the user
        // to grant it first and never claims blocking works without it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)
        ) {
            return
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
        val title = TextView(this).apply {
            text = "Focus cholche"
            textSize = 28f
            setTextColor(Color.parseColor("#1C1A17"))
            gravity = Gravity.CENTER
        }
        val sub = TextView(this).apply {
            text = "Ei app-ta ekhon bondho.\nPorashona shesh kore abar khulbe."
            textSize = 16f
            setTextColor(Color.parseColor("#6F6A62"))
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 0)
        }
        timeView = TextView(this).apply {
            textSize = 40f
            setTextColor(Color.parseColor("#A9716B"))
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 0)
        }
        val endButton = Button(this).apply {
            text = "End focus"
            setOnClickListener { endFocus() }
        }
        val buttonParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = 48
            gravity = Gravity.CENTER
        }
        layout.addView(title)
        layout.addView(sub)
        layout.addView(timeView)
        layout.addView(endButton, buttonParams)
        root.addView(
            layout,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        )

        // Full-screen, focusable overlay: it consumes every touch, so the
        // app underneath cannot be used, and the End focus button works.
        // (No FLAG_NOT_FOCUSABLE — that would make the button untappable.)
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
        updateTime()
        handler.postDelayed(ticker, 1000)
    }

    private fun hideOverlay() {
        handler.removeCallbacks(ticker)
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
