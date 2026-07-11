package com.reeltune.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat

class FloatingBubbleService : Service() {

    private lateinit var windowManager: WindowManager
    private var floatingView: FrameLayout? = null
    private var badgeTextView: TextView? = null
    private val CHANNEL_ID = "ReelTuneOverlayServiceChannel"

    companion object {
        var isRunning = false
        var activeBadgeCount = 1
        private var instance: FloatingBubbleService? = null

        fun updateBadge(count: Int) {
            activeBadgeCount = count
            instance?.badgeTextView?.post {
                if (count <= 0) {
                    instance?.stopSelf()
                } else {
                    instance?.badgeTextView?.text = count.toString()
                    instance?.badgeTextView?.visibility = View.VISIBLE
                }
            }
        }
        
        fun dismiss() {
            instance?.stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val badge = intent?.getIntExtra("badge_count", 1) ?: 1
        activeBadgeCount = badge
        updateBadge(badge)
        return START_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        
        createNotificationChannel()
        startForeground(9999, getNotification())
        
        showBubble()
        Toast.makeText(this, "Saved to Queue ✓", Toast.LENGTH_SHORT).show()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "ReelTune Background Downloader",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun getNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ReelTune Background Queue")
            .setContentText("Downloading shared clips in the background...")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun showBubble() {
        floatingView = FrameLayout(this)
        
        // Base bubble container
        val bubbleSize = dpToPx(60)
        val bubbleLayout = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(bubbleSize, bubbleSize, Gravity.CENTER)
            
            // Circular background with cyan-teal gradient
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.parseColor("#14B8A6"), Color.parseColor("#10B981"))
            ).apply {
                shape = GradientDrawable.OVAL
            }
            elevation = dpToPx(8).toFloat()
        }

        // Central music icon
        val musicIcon = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(dpToPx(28), dpToPx(28), Gravity.CENTER)
            setImageResource(android.R.drawable.ic_media_play)
            setColorFilter(Color.WHITE)
        }
        bubbleLayout.addView(musicIcon)

        // Badge count text view
        val badgeSize = dpToPx(20)
        badgeTextView = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(badgeSize, badgeSize, Gravity.TOP or Gravity.END).apply {
                topMargin = dpToPx(2)
                rightMargin = dpToPx(2)
            }
            gravity = Gravity.CENTER
            text = activeBadgeCount.toString()
            setTextColor(Color.WHITE)
            textSize = 10f
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.RED)
            }
            visibility = if (activeBadgeCount > 0) View.VISIBLE else View.GONE
        }
        bubbleLayout.addView(badgeTextView)

        floatingView?.addView(bubbleLayout)

        // WindowManager parameters for overlay
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dpToPx(16)
            y = dpToPx(120)
        }

        // Draggable listener
        bubbleLayout.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isClick = true
            private val CLICK_ACTION_THRESHOLD = 10

            override fun onTouch(v: View?, event: MotionEvent?): Boolean {
                if (event == null) return false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isClick = true
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        
                        if (Math.abs(dx) > CLICK_ACTION_THRESHOLD || Math.abs(dy) > CLICK_ACTION_THRESHOLD) {
                            isClick = false
                        }
                        
                        params.x = initialX + dx
                        params.y = initialY + dy
                        try {
                            windowManager.updateViewLayout(floatingView, params)
                        } catch (e: Exception) {}
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (isClick) {
                            // On click: Open MainActivity
                            val intent = Intent(this@FloatingBubbleService, MainActivity::class.java).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                putExtra("navigate_to", "queue")
                            }
                            startActivity(intent)
                            stopSelf()
                        } else {
                            // Snap to nearest edge (left or right)
                            val screenWidth = windowManager.defaultDisplay.width
                            val bubbleWidth = v?.width ?: 0
                            val targetX = if (params.x + bubbleWidth / 2 < screenWidth / 2) {
                                dpToPx(8)
                            } else {
                                screenWidth - bubbleWidth - dpToPx(8)
                            }
                            params.x = targetX
                            try {
                                windowManager.updateViewLayout(floatingView, params)
                            } catch (e: Exception) {}
                        }
                        return true
                    }
                }
                return false
            }
        })

        try {
            windowManager.addView(floatingView, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return (dp * density).toInt()
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        instance = null
        floatingView?.let {
            try {
                windowManager.removeView(it)
            } catch (e: Exception) {}
        }
    }
}
