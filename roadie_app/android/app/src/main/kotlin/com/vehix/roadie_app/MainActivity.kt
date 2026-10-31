package com.vehix.roadie_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val BACKGROUND_CHANNEL = "vehix/background"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register custom OverlayPlugin to handle MethodChannels across isolates
        flutterEngine.plugins.add(OverlayPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeService" -> {
                    val title = call.argument<String>("notificationTitle") ?: "SRS Mechanic"
                    val text = call.argument<String>("notificationText") ?: "Online and ready"
                    val intent = Intent(this, BackgroundService::class.java)
                    intent.putExtra("title", title)
                    intent.putExtra("text", text)
                    startServiceSafely(intent)
                    result.success(true)
                }
                "updateStatus" -> {
                    // This is handled by overlay update as well, but can be used for notification updates
                    val isOnline = call.argument<Boolean>("isOnline") ?: false
                    val intent = Intent(this, BackgroundService::class.java)
                    intent.putExtra("isOnline", isOnline)
                    startServiceSafely(intent)
                    result.success(true)
                }
                "stopService" -> {
                    stopService(Intent(this, BackgroundService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startServiceSafely(intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            // Fallback for some weird background restrictions
            try {
                startService(intent)
            } catch (ex: Exception) {
                // Last resort
            }
        }
    }
}
