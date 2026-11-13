package com.scoai.voice.openai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the meeting recording alive while the screen is off or the user is
 * in another app. Android stops an ordinary app's microphone as soon as it
 * leaves the foreground; a foreground service of type "microphone" is the
 * only way to keep capturing, and it must show an ongoing notification.
 *
 * The notification carries the meeting's name and its running time, and
 * tapping it returns to the app. Dart drives it through
 * `scoai.voice/recording` (start, update, stop).
 */
class RecordingService : Service() {
    companion object {
        const val CHANNEL_ID = "scoai_recording"
        const val NOTIFICATION_ID = 4701
        const val ACTION_START = "start"
        const val ACTION_UPDATE = "update"
        const val ACTION_STOP = "stop"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        fun send(context: Context, action: String, title: String? = null, text: String? = null) {
            val intent = Intent(context, RecordingService::class.java).setAction(action)
            if (title != null) intent.putExtra(EXTRA_TITLE, title)
            if (text != null) intent.putExtra(EXTRA_TEXT, text)
            if (action == ACTION_STOP) {
                context.stopService(intent)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private var title = "SCOAI Voice"
    private var text = "Đang ghi cuộc họp"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra(EXTRA_TITLE)?.let { title = it }
        intent?.getStringExtra(EXTRA_TEXT)?.let { text = it }
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        val notification = build()
        if (intent?.action == ACTION_UPDATE) {
            manager().notify(NOTIFICATION_ID, notification)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // The session belongs to the screen that started it: if Android
        // kills us, do not resurrect a recording with no microphone.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun manager() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Đang ghi cuộc họp",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Hiện khi SCOAI Voice đang ghi và dịch một cuộc họp."
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        manager().createNotificationChannel(channel)
    }

    private fun build(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_recording)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }
}
