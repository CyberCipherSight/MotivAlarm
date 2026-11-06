package com.cybersight.alarmforaction

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Holds a ringing alarm in a paused state instead of letting it ring forever
 * or silently giving up: once an unattended alarm has rung for the
 * user-configured time, the noise stops and this service waits for the user
 * to actually pick up their phone, then rings again *gently* (reduced
 * volume) so they aren't startled and the alarm is never simply missed.
 *
 * Deliberately its own service rather than a mode on [AlarmForegroundService]
 * — that one is the ringing-alarm path (bypass-DND alarm channel,
 * CATEGORY_ALARM, media-playback type) and must stay single-purpose. This is
 * a quiet, low-importance waiter.
 *
 * ACTION_USER_PRESENT can't be delivered to a manifest-declared receiver on
 * Android 8+, so a live process has to hold the registration — hence a
 * foreground service, bounded by [MAX_WAIT_MILLIS] so it can never linger.
 */
class AlarmResumeService : Service() {

    private var alarmId: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val giveUp = Runnable { stopWaiting() }

    /** Fires when the user unlocks (or wakes an unsecured device). */
    private val presenceReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_USER_PRESENT -> resumeGently()
                Intent.ACTION_SCREEN_ON -> {
                    // Devices with no secure lock screen never send
                    // USER_PRESENT; there, screen-on *is* the user picking
                    // the phone up.
                    val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    if (keyguard?.isKeyguardLocked != true) resumeGently()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            stopWaiting()
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID)
        if (id == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Already waiting (e.g. both the activity and the service backstop
        // timed out) — keep the existing wait rather than restarting it.
        if (alarmId == id) return START_STICKY
        alarmId = id

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        registerReceiver(
            presenceReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
                addAction(Intent.ACTION_SCREEN_ON)
            },
            Context.RECEIVER_NOT_EXPORTED
        )
        handler.postDelayed(giveUp, MAX_WAIT_MILLIS)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(giveUp)
        runCatching { unregisterReceiver(presenceReceiver) }
        super.onDestroy()
    }

    /** Rings the alarm again at reduced volume, then hands off and exits. */
    private fun resumeGently() {
        val id = alarmId ?: return stopWaiting()
        alarmId = null

        val serviceIntent = Intent(this, AlarmForegroundService::class.java)
            .setAction(AlarmForegroundService.ACTION_START)
            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            .putExtra(AlarmForegroundService.EXTRA_GENTLE, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        // The screen is on and just unlocked, so this normally lands; the
        // full-screen-intent notification the service posts remains the
        // guaranteed fallback if the launch is refused.
        runCatching {
            startActivity(
                Intent(this, AlarmRingActivity::class.java)
                    .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                    .putExtra(AlarmRingActivity.EXTRA_GENTLE, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            )
        }
        stopWaiting()
    }

    private fun stopWaiting() {
        alarmId = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val cancelIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, AlarmResumeService::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Alarm paused")
            .setContentText("It will finish quietly when you unlock your phone.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Dismiss alarm", cancelIntent).build())
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Paused alarms", NotificationManager.IMPORTANCE_LOW).apply {
                description = "An alarm waiting for you to pick up your phone"
            }
        )
    }

    companion object {
        const val ACTION_WAIT = "com.motivalarm.resume.WAIT"
        const val ACTION_CANCEL = "com.motivalarm.resume.CANCEL"
        private const val CHANNEL_ID = "motivalarm_paused_channel"
        private const val NOTIFICATION_ID = 2109

        /** Hard ceiling so a pending alarm can't hold a service all day. */
        private const val MAX_WAIT_MILLIS = 2 * 60 * 60 * 1000L

        /** Parks [alarmId] until the user next picks up their phone. */
        fun startWaiting(context: Context, alarmId: String) {
            val intent = Intent(context, AlarmResumeService::class.java)
                .setAction(ACTION_WAIT)
                .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun cancel(context: Context) {
            context.startService(
                Intent(context, AlarmResumeService::class.java).setAction(ACTION_CANCEL)
            )
        }
    }
}
