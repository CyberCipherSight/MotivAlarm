package com.cybersight.alarmforaction

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.content.res.ColorStateList
import android.media.AudioAttributes
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.widget.VideoView
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AlarmRingActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var timeView: TextView
    private var alarm: AlarmData? = null
    private var videoUnavailable = false
    private var videoWindowRunnable: Runnable? = null
    private var isPreview = false
    private var isGentle = false
    private var videoStarted = false
    private var activeVideoView: VideoView? = null
    private val videoWatchdog = Runnable {
        if (!videoStarted) {
            handleVideoFailure()
        }
    }

    private val timeTicker = object : Runnable {
        override fun run() {
            timeView.text = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_FULLSCREEN
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            (getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)
                ?.requestDismissKeyguard(this, null)
        }
        volumeControlStream = AudioManager.STREAM_ALARM

        loadAlarmIntent()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (alarm?.id == intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID) &&
            isPreview == intent.getBooleanExtra(EXTRA_IS_PREVIEW, false) &&
            isGentle == intent.getBooleanExtra(EXTRA_GENTLE, false)
        ) return
        handler.removeCallbacksAndMessages(null)
        releaseVideo()
        loadAlarmIntent()
    }

    private fun loadAlarmIntent() {
        videoStarted = false
        videoUnavailable = false
        videoWindowRunnable = null
        isPreview = intent.getBooleanExtra(EXTRA_IS_PREVIEW, false)
        isGentle = intent.getBooleanExtra(EXTRA_GENTLE, false)
        val alarmId = intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID) ?: ""
        alarm = AlarmStore(this).getAlarm(alarmId)
        buildUi(alarm)
        handler.post(timeTicker)
        // Safety net: if the video hasn't started within this window (codec
        // failure, blocked surface, keyguard interference), fall back to the
        // tone so the alarm is never silent — same guarantee the "always
        // sounds" requirement asks for, just enforced from the activity side
        // since it's the one that knows whether the video actually started.
        if (!alarm?.videoUri.isNullOrBlank()) {
            handler.postDelayed(videoWatchdog, VIDEO_WATCHDOG_MS)
        }
        // An alarm nobody is around to stop shouldn't ring forever: after the
        // configured time it goes quiet and waits for the user to pick up
        // their phone (see AlarmResumeService), rather than being missed.
        if (!isPreview) {
            val timeout = RingSettings.timeoutMillis(this)
            if (timeout > 0L) handler.postDelayed(autoPause, timeout)
        }
    }

    @Deprecated("Alarm cannot be dismissed with back.")
    override fun onBackPressed() {
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        releaseVideo()
        super.onDestroy()
    }

    private fun buildUi(alarm: AlarmData?) {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        val videoView = VideoView(this)
        activeVideoView = videoView
        root.addView(videoView, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))

        val overlay = View(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0xD9000000.toInt(), 0x22000000, 0xCC000000.toInt())
            )
        }
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(34), dp(20), dp(24))
        }
        root.addView(content, FrameLayout.LayoutParams(-1, -1))

        if (isPreview) {
            content.addView(
                TextView(this).apply {
                    text = "PREVIEW"
                    setTextColor(0xFFFFB020.toInt())
                    textSize = 13f
                    typeface = Typeface.DEFAULT_BOLD
                    letterSpacing = 0.12f
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(-1, -2)
            )
        }

        timeView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 54f
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
            gravity = Gravity.CENTER
        }
        content.addView(timeView, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) })

        val labelView = TextView(this).apply {
            text = alarm?.label?.ifBlank { "Alarm" } ?: "Alarm"
            setTextColor(0xFFE5E7EB.toInt())
            textSize = 18f
            gravity = Gravity.CENTER
        }
        content.addView(labelView, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })

        val spacer = View(this)
        content.addView(spacer, LinearLayout.LayoutParams(1, 0, 1f))

        // Snooze is a single tap — low-stakes/reversible, so it shouldn't make
        // a groggy user decode a gesture. Stop is the only slide control, so
        // the two actions are never visually or physically interchangeable.
        content.addView(snoozeButton(alarm), LinearLayout.LayoutParams(-1, dp(58)))

        val stopTrack = SlideToConfirmTrack(
            context = this,
            label = "Slide to stop",
            knobLabel = "Stop",
            threshold = 0.90f,
            onComplete = { stopAlarm() }
        )
        content.addView(stopTrack, LinearLayout.LayoutParams(-1, dp(68)).apply { topMargin = dp(16) })
        content.addView(
            accessibilityFallback("Stop alarm") { stopAlarm() },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) }
        )

        setContentView(root)
        playVideo(videoView, alarm)
    }

    private fun snoozeButton(alarm: AlarmData?): TextView {
        val minutes = alarm?.snoozeMinutes ?: 5
        val base = GradientDrawable().apply {
            setColor(0x33FFFFFF)
            cornerRadius = dp(18).toFloat()
        }
        return TextView(this).apply {
            text = "Snooze $minutes min"
            contentDescription = "Snooze for $minutes minutes"
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = RippleDrawable(ColorStateList.valueOf(0x55FFFFFF.toInt()), base, base)
            isClickable = true
            isFocusable = true
            setOnClickListener { snoozeAlarm() }
        }
    }

    private fun accessibilityFallback(description: String, onTap: () -> Unit): TextView {
        return TextView(this).apply {
            text = description
            contentDescription = "$description (no hold required)"
            setTextColor(0xFF8A8A8A.toInt())
            textSize = 13f
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            setPadding(0, dp(4), 0, dp(4))
            setOnClickListener { onTap() }
        }
    }

    private fun playVideo(videoView: VideoView, alarm: AlarmData?) {
        val uriString = alarm?.videoUri
        if (uriString.isNullOrBlank()) return
        try {
            val uri = if (Uri.parse(uriString).scheme == null) Uri.fromFile(File(uriString)) else Uri.parse(uriString)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                videoView.setAudioAttributes(alarmAudioAttributes())
            }
            videoView.setOnPreparedListener { player ->
                if (activeVideoView !== videoView || videoUnavailable || isFinishing || isDestroyed) return@setOnPreparedListener
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        player.setAudioAttributes(alarmAudioAttributes())
                    }
                    player.isLooping = false
                    if (alarm.videoBehavior == "muteVideoPlayTone") {
                        player.setVolume(0f, 0f)
                    } else if (isGentle) {
                        player.setVolume(GENTLE_VOLUME, GENTLE_VOLUME)
                    }
                    videoView.start()
                    videoStarted = true
                    handler.removeCallbacks(videoWatchdog)
                    startService(
                        Intent(this, AlarmForegroundService::class.java)
                            .setAction(AlarmForegroundService.ACTION_VIDEO_STARTED)
                            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
                    )
                    scheduleVideoWindow(videoView, alarm)
                } catch (_: Exception) {
                    handleVideoFailure()
                }
            }
            videoView.setOnCompletionListener {
                if (activeVideoView !== videoView || videoUnavailable || isFinishing || isDestroyed) return@setOnCompletionListener
                try {
                    if (alarm.videoBehavior == "playOnceThenTone") {
                        startTone()
                    } else {
                        videoView.seekTo(0)
                        videoView.start()
                        scheduleVideoWindow(videoView, alarm)
                    }
                } catch (_: Exception) {
                    handleVideoFailure()
                }
            }
            videoView.setOnErrorListener { _, _, _ ->
                if (activeVideoView === videoView) handleVideoFailure()
                true
            }
            videoView.setVideoURI(uri)
        } catch (_: Exception) {
            handleVideoFailure()
        }
    }

    private fun handleVideoFailure() {
        if (videoUnavailable || isFinishing || isDestroyed) return
        videoUnavailable = true
        handler.removeCallbacks(videoWatchdog)
        videoWindowRunnable?.let { handler.removeCallbacks(it) }
        releaseVideo()
        startTone(force = true)
    }

    private fun releaseVideo() {
        val video = activeVideoView
        activeVideoView = null
        video?.setOnPreparedListener(null)
        video?.setOnCompletionListener(null)
        // Consume late errors rather than showing VideoView's system dialog.
        video?.setOnErrorListener { _, _, _ -> true }
        try { video?.stopPlayback() } catch (_: Exception) { }
    }

    /**
     * Stops the noise but keeps the alarm pending: [AlarmResumeService] waits
     * for the user to unlock, then rings it again at reduced volume. A gentle
     * resume that's also ignored just ends — the user was already reached, so
     * re-parking it would loop.
     */
    private val autoPause = Runnable {
        val id = alarm?.id
        stopService(Intent(this, AlarmForegroundService::class.java).setAction(AlarmForegroundService.ACTION_STOP))
        if (!isGentle && id != null) AlarmResumeService.startWaiting(this, id)
        finish()
    }

    private fun stopAlarm() {
        val id = alarm?.id ?: return finish()
        AlarmResumeService.cancel(this)
        if (isPreview) {
            endPreview(id)
        } else {
            AlarmScheduler(this).stop(id)
        }
        maybeShowVideoFallbackMessage()
        finish()
    }

    private fun snoozeAlarm() {
        val currentAlarm = alarm ?: return finish()
        AlarmResumeService.cancel(this)
        if (isPreview) {
            endPreview(currentAlarm.id)
        } else {
            AlarmScheduler(this).snooze(currentAlarm.id, currentAlarm.snoozeMinutes)
        }
        stopService(Intent(this, AlarmForegroundService::class.java).setAction(AlarmForegroundService.ACTION_STOP))
        maybeShowVideoFallbackMessage()
        finish()
    }

    /** Cleans up a one-off preview without touching real alarm scheduling. */
    private fun endPreview(id: String) {
        stopService(Intent(this, AlarmForegroundService::class.java).setAction(AlarmForegroundService.ACTION_STOP))
        AlarmStore(this).remove(id)
    }

    private fun startTone(force: Boolean = false) {
        val id = alarm?.id ?: return
        if (isFinishing || isDestroyed) return
        try {
            startService(
                Intent(this, AlarmForegroundService::class.java)
                    .setAction(AlarmForegroundService.ACTION_START_TONE)
                    .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                    .putExtra(AlarmForegroundService.EXTRA_FORCE_FALLBACK, force)
            )
        } catch (_: Exception) {
            // The service also has its own watchdog when this request cannot
            // be delivered (for example, during an activity/service teardown).
            Log.w("AlarmRingActivity", "Could not deliver alarm tone request")
        }
    }

    private fun scheduleVideoWindow(videoView: VideoView, alarm: AlarmData) {
        videoWindowRunnable?.let { handler.removeCallbacks(it) }
        val limitMillis = ((alarm.videoDurationSeconds ?: 60).coerceIn(1, 60)) * 1000L
        val runnable = Runnable {
            if (activeVideoView !== videoView || videoUnavailable || isFinishing || isDestroyed) return@Runnable
            try {
                if (alarm.videoBehavior == "playOnceThenTone") {
                    videoView.pause()
                    startTone()
                } else {
                    videoView.seekTo(0)
                    videoView.start()
                    scheduleVideoWindow(videoView, alarm)
                }
            } catch (_: Exception) {
                handleVideoFailure()
            }
        }
        videoWindowRunnable = runnable
        handler.postDelayed(runnable, limitMillis)
    }

    private fun maybeShowVideoFallbackMessage() {
        if (videoUnavailable) {
            Toast.makeText(this, "Selected video was unavailable. Default alarm tone was used.", Toast.LENGTH_LONG).show()
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun alarmAudioAttributes(): AudioAttributes {
        return AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
    }

    companion object {
        const val EXTRA_IS_PREVIEW = "isPreview"
        const val EXTRA_GENTLE = "gentle"

        /** Volume for a gentle resume — audible without startling. */
        private const val GENTLE_VOLUME = 0.25f

        /** How long to wait for video to confirm it started before falling
         *  back to the tone so the alarm is never silent. */
        const val VIDEO_WATCHDOG_MS = 1800L
    }

    /**
     * Plain single-continuous-swipe dismiss control — no hold step. A track
     * with a thumb visually promises one smooth slide from start to finish,
     * so reaching the end completes immediately, exactly as it looks like it
     * should. The instruction text lives in the track and fades out as the
     * knob travels over it (instead of both texts competing for the same
     * space); the action word lives permanently on the knob itself.
     */
    private class SlideToConfirmTrack(
        context: Context,
        private val label: String,
        private val knobLabel: String,
        private val threshold: Float,
        private val onComplete: () -> Unit
    ) : FrameLayout(context) {
        private val density = resources.displayMetrics.density
        private var startX = 0f
        private var progress = 0f
        private var finished = false
        private val knobWidth = dp(118)

        private val trackLabel = TextView(context).apply {
            text = label
            setTextColor(0xCCFFFFFF.toInt())
            textSize = 15f
            gravity = Gravity.CENTER
        }

        private val knob = TextView(context).apply {
            text = knobLabel
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = rounded(0x44FFFFFF)
        }

        private val fill = View(context).apply {
            background = rounded(0x332F80ED)
        }

        init {
            background = rounded(0x24FFFFFF).apply {
                setStroke(dp(1), 0x44FFFFFF)
            }
            addView(trackLabel, LayoutParams(-1, -1))
            addView(fill, LayoutParams(knobWidth, -1, Gravity.START))
            addView(knob, LayoutParams(knobWidth, -1, Gravity.START))
            setPadding(dp(4), dp(4), dp(4), dp(4))
            contentDescription = "$label."
            setOnTouchListener { _, event -> handleTouch(event) }
        }

        private fun handleTouch(event: MotionEvent): Boolean {
            if (finished) return true
            val maxTravel = (width - paddingLeft - paddingRight - knobWidth).coerceAtLeast(1)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    parent.requestDisallowInterceptTouchEvent(true)
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.x - startX).coerceIn(0f, maxTravel.toFloat())
                    progress = dx / maxTravel
                    knob.translationX = dx
                    setFillWidth(knobWidth + dx.toInt())
                    trackLabel.alpha = (1f - progress * 1.4f).coerceIn(0f, 1f)
                    if (progress >= threshold) complete(maxTravel)
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    parent.requestDisallowInterceptTouchEvent(false)
                    if (!finished) resetSlider()
                    return true
                }
            }
            return true
        }

        private fun complete(maxTravel: Int) {
            finished = true
            knob.translationX = maxTravel.toFloat()
            setFillWidth(knobWidth + maxTravel)
            trackLabel.alpha = 0f
            fill.background = rounded(0xFF22C55E.toInt())
            vibrate(60)
            onComplete()
        }

        private fun resetSlider() {
            progress = 0f
            knob.animate().translationX(0f).setDuration(180).start()
            setFillWidth(knobWidth)
            trackLabel.alpha = 1f
        }

        private fun setFillWidth(width: Int) {
            val params = fill.layoutParams as LayoutParams
            params.width = width
            fill.layoutParams = params
        }

        private fun vibrate(durationMs: Long) {
            val vibrator = vibratorService() ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs)
            }
        }

        private fun vibratorService(): Vibrator? {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        }

        private fun dp(value: Int): Int = (value * density).toInt()

        private fun rounded(color: Int): GradientDrawable {
            return GradientDrawable().apply {
                setColor(color)
                cornerRadius = dp(20).toFloat()
            }
        }
    }
}
