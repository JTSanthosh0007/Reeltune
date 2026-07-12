package com.reeltune.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import io.flutter.plugins.googlemobileads.NativeAdFactory
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val TAG = "ReelTune-MainActivity"
    private val SHARING_CHANNEL = "com.reeltune.app/sharing"
    private var sharedText: String? = null
    private var methodChannel: MethodChannel? = null
    private var shouldOpenQueue: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        try {
            // Register Native Ad Factory
            val factory = ListTileNativeAdFactory(layoutInflater)
            GoogleMobileAdsPlugin.registerNativeAdFactory(flutterEngine, "listTile", factory)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register NativeAdFactory: ${e.message}", e)
        }

        // Setup Sharing & Overlay MethodChannel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARING_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getSharedText" -> {
                        result.success(sharedText)
                        sharedText = null // Consume it
                    }
                    "shouldOpenQueue" -> {
                        result.success(shouldOpenQueue)
                        shouldOpenQueue = false // Consume it
                    }
                    "checkOverlayPermission" -> {
                        result.success(checkOverlayPermission())
                    }
                    "requestOverlayPermission" -> {
                        requestOverlayPermission()
                        result.success(null)
                    }
                    "checkAccessibilityPermission" -> {
                        result.success(checkAccessibilityPermission())
                    }
                    "requestAccessibilityPermission" -> {
                        requestAccessibilityPermission()
                        result.success(null)
                    }
                    "showBubble" -> {
                        val badge = call.argument<Int>("badgeCount") ?: 1
                        startBubbleService(badge)
                        result.success(null)
                    }
                    "updateBubbleBadge" -> {
                        val badge = call.argument<Int>("badgeCount") ?: 1
                        FloatingBubbleService.updateBadge(badge)
                        result.success(null)
                    }
                    "dismissBubble" -> {
                        stopBubbleService()
                        result.success(null)
                    }
                    "minimizeToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "MethodChannel handler error for ${call.method}: ${e.message}", e)
                result.error("NATIVE_ERROR", e.message, null)
            }
        }

        // Handle intent text on launch
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    /**
     * Handle incoming intents safely. This is the #1 crash point — 
     * every line is wrapped in try/catch to prevent "ReelTune keeps stopping".
     */
    private fun handleIntent(intent: Intent?) {
        try {
            if (intent == null) return

            // Handle navigate_to=queue from FloatingBubbleService tap
            try {
                val navigateTo = intent.getStringExtra("navigate_to")
                if (navigateTo == "queue") {
                    Log.d(TAG, "Navigate to queue requested")
                    shouldOpenQueue = true
                    methodChannel?.invokeMethod("onNavigateToQueue", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling navigate_to extra: ${e.message}", e)
            }

            // Handle ACTION_SEND (share intent from Instagram, YouTube, etc.)
            if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                Log.d(TAG, "Received shared text: $text")

                if (text.isNullOrBlank()) {
                    Log.w(TAG, "Shared text is null or blank, ignoring")
                    return
                }

                // Validate that the text contains a URL
                val urlPattern = Regex("https?://[^\\s]+")
                if (!urlPattern.containsMatchIn(text)) {
                    Log.w(TAG, "Shared text does not contain a valid URL: $text")
                    return
                }

                sharedText = text
                
                // Send to Flutter if channel is ready
                try {
                    methodChannel?.invokeMethod("onSharedTextReceived", text)
                } catch (e: Exception) {
                    Log.e(TAG, "Error sending shared text to Flutter: ${e.message}", e)
                }
                
                // Launch floating overlay ONLY if we have permission
                try {
                    if (checkOverlayPermission()) {
                        startBubbleService(1)
                    } else {
                        Log.w(TAG, "Overlay permission not granted, skipping bubble service")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error starting bubble service: ${e.message}", e)
                }

                // Pop activity to background so user stays in Instagram/YouTube
                try {
                    moveTaskToBack(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Error moving task to back: ${e.message}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "CRITICAL: handleIntent crashed: ${e.message}", e)
            // Never let this crash propagate to the system
        }
    }

    private fun checkOverlayPermission(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(this)
            } else {
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking overlay permission: ${e.message}", e)
            false
        }
    }

    private fun checkAccessibilityPermission(): Boolean {
        return try {
            val string = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
            string.contains(packageName)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking accessibility permission: ${e.message}")
            false
        }
    }

    private fun requestAccessibilityPermission() {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting accessibility permission: ${e.message}")
        }
    }

    private fun requestOverlayPermission() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, 1234)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting overlay permission: ${e.message}", e)
        }
    }

    private fun startBubbleService(badgeCount: Int) {
        try {
            val intent = Intent(this, FloatingBubbleService::class.java).apply {
                putExtra("badge_count", badgeCount)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start bubble service: ${e.message}", e)
            // On Android 14+ this can throw ForegroundServiceStartNotAllowedException
            // Swallow it — the user just doesn't get the floating bubble
        }
    }

    private fun stopBubbleService() {
        try {
            val intent = Intent(this, FloatingBubbleService::class.java)
            stopService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping bubble service: ${e.message}", e)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        try {
            GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "listTile")
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering NativeAdFactory: ${e.message}", e)
        }
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

class ListTileNativeAdFactory(private val layoutInflater: LayoutInflater) : NativeAdFactory {
    override fun createNativeAd(nativeAd: NativeAd, customOptions: MutableMap<String, Any>?): NativeAdView {
        val adView = layoutInflater.inflate(R.layout.my_native_ad, null) as NativeAdView

        // Headline
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        // Body
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        bodyView.text = nativeAd.body
        adView.bodyView = bodyView

        // Media / Icon
        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        val icon = nativeAd.icon
        if (icon != null) {
            iconView.setImageDrawable(icon.drawable)
            iconView.visibility = View.VISIBLE
        } else {
            iconView.visibility = View.GONE
        }
        adView.iconView = iconView

        // Call to action button
        val ctaView = adView.findViewById<TextView>(R.id.ad_call_to_action)
        if (nativeAd.callToAction != null) {
            ctaView.text = nativeAd.callToAction
            ctaView.visibility = View.VISIBLE
        } else {
            ctaView.visibility = View.GONE
        }
        adView.callToActionView = ctaView

        adView.setNativeAd(nativeAd)
        return adView
    }
}
