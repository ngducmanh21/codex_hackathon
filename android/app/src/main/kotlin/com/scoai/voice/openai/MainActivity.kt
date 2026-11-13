package com.scoai.voice.openai

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val NOTIFICATION_REQUEST = 7301
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scoai.voice/recording")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Keeps the microphone alive with the screen off.
                    "start" -> {
                        askForNotifications()
                        RecordingService.send(
                            applicationContext,
                            RecordingService.ACTION_START,
                            call.argument<String>("title"),
                            call.argument<String>("text"),
                        )
                        result.success(null)
                    }
                    "update" -> {
                        RecordingService.send(
                            applicationContext,
                            RecordingService.ACTION_UPDATE,
                            call.argument<String>("title"),
                            call.argument<String>("text"),
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        RecordingService.send(applicationContext, RecordingService.ACTION_STOP)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android 13+ hides the recording notification unless the user allows
     * notifications. The service runs either way, so a refusal only costs
     * the notification.
     */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (!granted) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }
}
