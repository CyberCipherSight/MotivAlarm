package com.cybersight.alarmforaction

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import org.json.JSONArray

/**
 * Drives an interval workout/study session (work and break phases) as a
 * foreground service, so the countdown and the audio cues keep running with
 * the screen off or the app backgrounded — a Dart-side timer stops the moment
 * the Flutter engine is paused.
 *
 * Deliberately separate from [AlarmForegroundService]: that service is shaped
 * around a single ringing alarm (bypass-DND alarm channel, CATEGORY_ALARM,
 * state loaded from [AlarmStore], dismissal semantics). A pausable workout
 * timer is a different lifecycle, and it must NOT bypass Do Not Disturb or
 * pose as an alarm — it gets its own quiet channel and its own FGS type.
 *
 * Flutter is not notified push-style; it polls [stateSnapshot] (via the
 * method channel) on lifecycle resume and periodically while visible. The
 * service is the single source of truth for phase/remaining time.
 */
class IntervalSessionService : Service() {

    private data class Phase(val label: String, val seconds: Int, val isBreak: Boolean)

    private var phases: List<Phase> = emptyList()
    private var phaseIndex = 0
    private var remainingSeconds = 0
    private var ticking = false

    private val handler = Handler(Looper.getMainLooper())
    private var toneGenerator: ToneGenerator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    // Ticks are anchored to elapsedRealtime so a long session doesn't drift
    // the way naive postDelayed(1000) chains do.
    private var nextTickAt = 0L

    private val tick = object : Runnable {
        override fun run() {
            if (!ticking) return
            remainingSeconds -= 1
            if (remainingSeconds <= 0) {
                advancePhase()
            } else {
                publishState()
                updateNotification()
            }
            if (ticking) {
                nextTickAt += 1000L
                handler.postDelayed(this, (nextTickAt - SystemClock.elapsedRealtime()).coerceAtLeast(1L))
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startSession(intent.getStringExtra(EXTRA_PHASES_JSON) ?: "[]")
            ACTION_PAUSE -> pauseSession()
            ACTION_RESUME -> resumeSession()
            ACTION_END -> {
                endSession()
                return START_NOT_STICKY
            }
            else -> if (phases.isEmpty()) {
                // Restarted by the system with no session to run — nothing to do.
                stopSelf()
                return START_NOT_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopTicking()
        releaseCues()
        // A finished session keeps its snapshot so Flutter (which may resync
        // seconds later) can still show the completion state; the next
        // startSession resets it. Any other teardown wipes to inactive.
        if (!finished) clearState()
        super.onDestroy()
    }

    private fun startSession(phasesJson: String) {
        val parsed = parsePhases(phasesJson)
        if (parsed.isEmpty()) {
            stopSelf()
            return
        }
        stopTicking()
        phases = parsed
        phaseIndex = 0
        remainingSeconds = parsed.first().seconds
        finished = false
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        cuePhaseStart(parsed.first())
        startTicking()
    }

    private fun pauseSession() {
        if (!ticking) return
        stopTicking()
        publishState()
        updateNotification()
    }

    private fun resumeSession() {
        if (ticking || phases.isEmpty() || remainingSeconds <= 0) return
        startTicking()
        updateNotification()
    }

    private fun endSession() {
        stopTicking()
        releaseCues()
        clearState()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun advancePhase() {
        phaseIndex += 1
        if (phaseIndex >= phases.size) {
            cueSessionComplete()
            stopTicking()
            finished = true
            remainingSeconds = 0
            publishState()
            stopForeground(STOP_FOREGROUND_REMOVE)
            // The completion cue posts its 2nd/3rd beeps up to ~800ms out;
            // stopping the service immediately would release the
            // ToneGenerator underneath them (startTone on a released
            // generator throws and kills the process). Let the cue finish.
            handler.postDelayed({ stopSelf() }, 1500L)
            return
        }
        val phase = phases[phaseIndex]
        remainingSeconds = phase.seconds
        cuePhaseStart(phase)
        publishState()
        updateNotification()
    }

    private fun startTicking() {
        ticking = true
        acquireWakeLock()
        nextTickAt = SystemClock.elapsedRealtime() + 1000L
        handler.postDelayed(tick, 1000L)
        publishState()
    }

    private fun stopTicking() {
        ticking = false
        handler.removeCallbacks(tick)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        publishState()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "motivalarm:intervalSession").apply {
            setReferenceCounted(false)
            // Hard ceiling so a bug can never hold the CPU indefinitely;
            // sessions longer than 4h are re-covered by the resume path.
            acquire(4 * 60 * 60 * 1000L)
        }
    }

    // --- Audio/vibration cues -------------------------------------------------
    // Distinct patterns per event so the session is usable eyes-free:
    // set start = double high beep, break start = one long lower tone,
    // complete = triple beep. STREAM_MUSIC, not STREAM_ALARM — this is a
    // user-attended timer, not an alarm.

    private fun generator(): ToneGenerator {
        toneGenerator?.let { return it }
        return ToneGenerator(AudioManager.STREAM_MUSIC, ToneGenerator.MAX_VOLUME).also { toneGenerator = it }
    }

    private fun cuePhaseStart(phase: Phase) {
        val gen = generator()
        if (phase.isBreak) {
            gen.startTone(ToneGenerator.TONE_CDMA_ONE_MIN_BEEP, 650)
            vibrate(longArrayOf(0, 500))
        } else {
            gen.startTone(ToneGenerator.TONE_PROP_BEEP2, 350)
            vibrate(longArrayOf(0, 180, 120, 180))
        }
    }

    private fun cueSessionComplete() {
        generator().startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 250)
        // Delayed beeps go through the field (nulled on release), never a
        // captured instance — a released ToneGenerator throws on startTone.
        handler.postDelayed({ toneGenerator?.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 250) }, 400)
        handler.postDelayed({ toneGenerator?.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 400) }, 800)
        vibrate(longArrayOf(0, 250, 150, 250, 150, 500))
    }

    private fun releaseCues() {
        // Drop any pending delayed beeps before releasing the generator.
        handler.removeCallbacksAndMessages(null)
        toneGenerator?.release()
        toneGenerator = null
    }

    private fun vibrate(pattern: LongArray) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, -1)
        }
    }

    // --- Notification ---------------------------------------------------------

    private fun buildNotification(): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val contentIntent = openIntent?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val endIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, IntervalSessionService::class.java).setAction(ACTION_END),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val phase = phases.getOrNull(phaseIndex)
        val minutes = remainingSeconds / 60
        val seconds = remainingSeconds % 60
        val timeText = String.format("%d:%02d", minutes, seconds)
        val title = phase?.label ?: "Interval session"
        val text = if (ticking) "$timeText remaining" else "Paused — $timeText remaining"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .addAction(Notification.Action.Builder(null, "End session", endIntent).build())
            .build()
    }

    private fun updateNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, "Interval sessions", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Ongoing workout/study interval session"
        }
        manager.createNotificationChannel(channel)
    }

    // --- State shared with the method channel ----------------------------------

    private fun publishState() {
        val phase = phases.getOrNull(phaseIndex)
        synchronized(stateLock) {
            snapshot = mapOf(
                "active" to (phases.isNotEmpty() && !finished),
                "running" to ticking,
                "finished" to finished,
                "phaseIndex" to phaseIndex,
                "phaseCount" to phases.size,
                "phaseLabel" to (phase?.label ?: ""),
                "isBreak" to (phase?.isBreak ?: false),
                "remainingSeconds" to remainingSeconds,
            )
        }
    }

    private fun clearState() {
        phases = emptyList()
        phaseIndex = 0
        remainingSeconds = 0
        finished = false
        synchronized(stateLock) { snapshot = inactiveSnapshot() }
    }

    private fun parsePhases(json: String): List<Phase> {
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.getJSONObject(i)
                val seconds = obj.optInt("seconds", 0)
                if (seconds <= 0) null
                else Phase(obj.optString("label", ""), seconds, obj.optBoolean("isBreak", false))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    companion object {
        const val ACTION_START = "com.motivalarm.session.START"
        const val ACTION_PAUSE = "com.motivalarm.session.PAUSE"
        const val ACTION_RESUME = "com.motivalarm.session.RESUME"
        const val ACTION_END = "com.motivalarm.session.END"
        const val EXTRA_PHASES_JSON = "phasesJson"
        private const val CHANNEL_ID = "motivalarm_session_channel"
        private const val NOTIFICATION_ID = 2108

        private val stateLock = Any()
        private var finished = false
        private var snapshot: Map<String, Any> = inactiveSnapshot()

        private fun inactiveSnapshot(): Map<String, Any> = mapOf(
            "active" to false,
            "running" to false,
            "finished" to false,
            "phaseIndex" to 0,
            "phaseCount" to 0,
            "phaseLabel" to "",
            "isBreak" to false,
            "remainingSeconds" to 0,
        )

        /** Read by [AlarmMethodChannel] so Flutter can re-sync its display. */
        fun stateSnapshot(): Map<String, Any> = synchronized(stateLock) { snapshot }
    }
}
