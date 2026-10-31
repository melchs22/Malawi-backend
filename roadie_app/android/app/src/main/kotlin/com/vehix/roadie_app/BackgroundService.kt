package com.vehix.roadie_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import android.util.Log

class BackgroundService : Service() {
    private val CHANNEL_ID = "VehixBackgroundService"
    private val NOTIFICATION_ID = 1002
    private val TAG = "VehixBackgroundService"

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var params: WindowManager.LayoutParams? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        Log.d(TAG, "onStartCommand action: $action")

        when (action) {
            "SHOW_OVERLAY" -> {
                showOverlay()
                val isOnline = intent.getBooleanExtra("isOnline", false)
                updateOverlayStatus(isOnline)
            }
            "HIDE_OVERLAY" -> {
                hideOverlay()
            }
            "UPDATE_OVERLAY_STATUS" -> {
                val isOnline = intent.getBooleanExtra("isOnline", false)
                updateOverlayStatus(isOnline)
            }
            "SHOW_ALERT" -> {
                val title = intent.getStringExtra("title") ?: "New Service Request!"
                updateForegroundNotification(title, "Tap to view details")
            }
        }

        // Always ensure foreground status to prevent crashes
        val title = intent?.getStringExtra("title") ?: "SRS Mechanic"
        val text = intent?.getStringExtra("text") ?: "App is running in background"
        updateForegroundNotification(title, text)

        return START_STICKY
    }

    private fun updateForegroundNotification(title: String, text: String) {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start foreground with location type: ${e.message}")
                // Fallback to standard startForeground if location permission is missing but type is declared
                try {
                    startForeground(NOTIFICATION_ID, notification)
                } catch (ex: Exception) {
                    Log.e(TAG, "Fatal: Could not start foreground at all")
                }
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun showOverlay() {
        if (floatingView != null) return

        try {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
            floatingView = inflater.inflate(R.layout.overlay_layout, null)

            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 0
                y = 100
            }

            // Add touch listener for dragging
            floatingView?.setOnTouchListener(object : View.OnTouchListener {
                private var initialX: Int = 0
                private var initialY: Int = 0
                private var initialTouchX: Float = 0.0f
                private var initialTouchY: Float = 0.0f

                override fun onTouch(v: View, event: MotionEvent): Boolean {
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            initialX = params!!.x
                            initialY = params!!.y
                            initialTouchX = event.rawX
                            initialTouchY = event.rawY
                            return true
                        }
                        MotionEvent.ACTION_UP -> {
                            val diffX = event.rawX - initialTouchX
                            val diffY = event.rawY - initialTouchY
                            if (Math.abs(diffX) < 10 && Math.abs(diffY) < 10) {
                                // Clicked! Bring app to front
                                val intent = Intent(this@BackgroundService, MainActivity::class.java)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            }
                            return true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            params!!.x = initialX + (event.rawX - initialTouchX).toInt()
                            params!!.y = initialY + (event.rawY - initialTouchY).toInt()
                            try {
                                windowManager?.updateViewLayout(floatingView, params)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error updating overlay layout: ${e.message}")
                            }
                            return true
                        }
                    }
                    return false
                }
            })

            windowManager?.addView(floatingView, params)
            Log.d(TAG, "Overlay added successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add overlay: ${e.message}")
            floatingView = null
        }
    }

    private fun hideOverlay() {
        if (floatingView != null) {
            try {
                windowManager?.removeView(floatingView)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing overlay: ${e.message}")
            }
            floatingView = null
        }
    }

    private fun updateOverlayStatus(isOnline: Boolean) {
        if (floatingView == null) return
        try {
            val indicator = floatingView?.findViewById<View>(R.id.online_indicator)
            indicator?.visibility = if (isOnline) View.VISIBLE else View.GONE
        } catch (e: Exception) {
            Log.e(TAG, "Error updating overlay status: ${e.message}")
        }
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "SRS Mechanic background service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }
}
