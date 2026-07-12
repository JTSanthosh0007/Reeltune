package com.reeltune.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class AppDetectionService : AccessibilityService() {
    private val TAG = "ReelTune-Accessibility"
    private val handler = Handler(Looper.getMainLooper())
    private var pendingStateAction: Runnable? = null
    private var lastTargetState: Boolean? = null // true = show, false = hide

    // Supported target apps package names
    private val targetPackages = setOf(
        "com.instagram.android",      // Instagram
        "com.google.android.youtube",  // YouTube / YT Shorts / YT Music
        "com.facebook.katana",         // Facebook
        "com.facebook.lite",           // Facebook Lite
        "com.instagram.threads",       // Threads
        "com.zhiliaoapp.musically",    // TikTok (Global)
        "com.ss.android.ugc.trill"     // TikTok (Asia)
    )

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        // Listen for window state changes (app switching)
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: return

            val isTarget = targetPackages.contains(packageName)
            val isIgnored = packageName == "com.reeltune.app" || 
                            packageName.contains("com.android.systemui") || 
                            packageName.contains("com.google.android.inputmethod.latin") ||
                            packageName.contains("android")

            val shouldShow = if (isTarget) {
                true
            } else if (isIgnored) {
                // Keep showing if we transitioned to our app or system UI/keyboard
                lastTargetState ?: false
            } else {
                false
            }

            if (shouldShow != lastTargetState) {
                lastTargetState = shouldShow
                debounceStateChange(shouldShow)
            }
        }
    }

    private fun debounceStateChange(shouldShow: Boolean) {
        pendingStateAction?.let { handler.removeCallbacks(it) }
        
        val action = Runnable {
            if (shouldShow) {
                Log.d(TAG, "Debounced action: start bubble service")
                startBubbleService()
            } else {
                Log.d(TAG, "Debounced action: stop bubble service")
                stopBubbleService()
            }
        }
        pendingStateAction = action
        handler.postDelayed(action, 500) // 500ms debounce to smooth out fast swiping and animation window changes
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service Interrupted")
    }

    private fun startBubbleService() {
        try {
            // Check overlay permission first
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!android.provider.Settings.canDrawOverlays(this)) {
                    return
                }
            }
            if (FloatingBubbleService.isRunning) return // Already running

            val intent = Intent(this, FloatingBubbleService::class.java).apply {
                putExtra("badge_count", 1) // default badge
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting bubble from accessibility: ${e.message}")
        }
    }

    private fun stopBubbleService() {
        try {
            if (!FloatingBubbleService.isRunning) return
            val intent = Intent(this, FloatingBubbleService::class.java)
            stopService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping bubble from accessibility: ${e.message}")
        }
    }

    override fun onDestroy() {
        pendingStateAction?.let { handler.removeCallbacks(it) }
        super.onDestroy()
    }
}
