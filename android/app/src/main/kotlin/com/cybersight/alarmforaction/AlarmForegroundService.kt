package com.cybersight.alarmforaction

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class AlarmForegroundService : Service() {
    private val tonePlayer by lazy { AlarmTonePlayer(this) }
    private var videoConfirmed = false
    private val videoWatchdog = Runnable {
        if (!videoConfirmed) startTone(forceFallback = true)
    }
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopEffects()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_VIDEO_STARTED -> {
                if (intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID) == currentAlarmId) {
                    videoConfirmed = true
                    handler.removeCallbacks(videoWatchdog)
                }
                return START_STICKY
            }
            ACTION_START_TONE -> {
                if (intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID) != currentAlarmId) return START_NOT_STICKY
                startTone(forceFallback = intent.getBooleanExtra(EXTRA_FORCE_FALLBACK, false))
                return START_STICKY
            }
        }

        val alarmId = intent?.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID) ?: return START_NOT_STICKY
        val alarm = AlarmStore(this).getAlarm(alarmId) ?: run {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        stopEffects()
        videoConfirmed = false
        currentAlarmId = alarmId
        gentle = intent.getBooleanExtra(EXTRA_GENTLE, false)
        val notification = buildNotification(alarm)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // An unavailable vibrator must not prevent audio from starting.
        try { startVibrationIfNeeded(alarm) } catch (_: Exception) { }
        startToneForBehavior(alarm)
        if (!alarm.videoUri.isNullOrBlank()) {
            handler.postDelayed(videoWatchdog, AlarmRingActivity.VIDEO_WATCHDOG_MS)
        }
        scheduleAutoPause()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopEffects()
        super.onDestroy()
    }

    private fun buildNotification(alarm: AlarmData): Notification {
        val openIntent = Intent(this, AlarmRingActivity::class.java)
            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingIntent = PendingIntent.getActivity(
            this,
            AlarmScheduler.requestCode(alarm.id) + 2,
            openIntent,
            AlarmScheduler.flags(),
            backgroundActivityStartOptions()
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("VideoAlarmClock")
            .setContentText(alarm.label.ifBlank { "Alarm" })
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()
    }

    private fun startToneForBehavior(alarm: AlarmData) {
        val hasVideo = !alarm.videoUri.isNullOrBlank()
        when {
            !hasVideo -> startTone()
            alarm.videoBehavior == "muteVideoPlayTone" -> startTone()
            alarm.videoBehavior == "loopVideo" -> startTone()
            alarm.videoBehavior == "playOnceThenTone" -> {
                val delay = ((alarm.videoDurationSeconds ?: 60).coerceIn(1, 60)) * 1000L
                handler.postDelayed({ startTone() }, delay)
            }
        }
    }

    /**
     * @param forceFallback Set when this is the last-resort "make sure the alarm
     *   isn't silent" path (video never started, decode error, etc.) — overrides
     *   the user's "silent" backup-tone choice and the chosen custom tone, since
     *   a chosen-but-broken tone is exactly what this fallback exists to route
     *   around. Intentional behavior-driven calls (mute+tone, loop+tone, etc.)
     *   leave this false and keep respecting the user's setting as normal.
     */
    private fun startTone(forceFallback: Boolean = false) {
        val alarmId = currentAlarmId ?: return
        val alarm = AlarmStore(this).getAlarm(alarmId) ?: return
        if (alarm.toneUri == "silent" && !forceFallback) return
        if (tonePlayer.isActive) return
        tonePlayer.start(
            chosenTone = if (forceFallback) null else alarm.toneUri,
            volume = if (gentle) GENTLE_VOLUME else 1f
        )
    }

    private fun startVibrationIfNeeded(alarm: AlarmData) {
        if (!alarm.vibrate) return
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 600, 350, 600)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    /**
     * Backstop for the "nobody is there to stop it" case: an alarm that rings
     * unattended for the configured time stops making noise and parks itself
     * in [AlarmResumeService], which rings it again gently once the user
     * actually picks up their phone. [AlarmRingActivity] runs the same
     * timeout slightly earlier when it's on screen; this covers the case
     * where the ring screen never launched and only the notification showed.
     * A gentle resume never re-parks — the user has already been reached, so
     * it simply ends rather than looping.
     */
    private fun scheduleAutoPause() {
        val timeout = RingSettings.timeoutMillis(this)
        if (timeout <= 0L) return
        handler.postDelayed({
            val id = currentAlarmId
            val shouldWait = !gentle && id != null
            stopEffects()
            stopForeground(STOP_FOREGROUND_REMOVE)
            if (shouldWait) AlarmResumeService.startWaiting(this, id!!)
            stopSelf()
        }, timeout + BACKSTOP_GRACE_MILLIS)
    }

    private fun stopEffects() {
        handler.removeCallbacksAndMessages(null)
        tonePlayer.stop()
        try { vibrator?.cancel() } catch (_: Exception) { }
        vibrator = null
    }

    private var currentAlarmId: String? = null
    private var gentle = false

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, "Alarm alerts", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Full-screen alarm alerts"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.motivalarm.START_ALARM"
        const val ACTION_STOP = "com.motivalarm.STOP_ALARM"
        const val ACTION_VIDEO_STARTED = "com.motivalarm.VIDEO_STARTED"
        const val ACTION_START_TONE = "com.motivalarm.START_TONE"
        const val EXTRA_FORCE_FALLBACK = "forceFallback"
        const val EXTRA_GENTLE = "gentle"

        /** Volume for a gentle resume — audible without startling. */
        private const val GENTLE_VOLUME = 0.25f

        /** Lets the on-screen ring activity's identical timeout win. */
        private const val BACKSTOP_GRACE_MILLIS = 10_000L
        private const val CHANNEL_ID = "motivalarm_alarm_channel"
        private const val NOTIFICATION_ID = 2107
    }
}
