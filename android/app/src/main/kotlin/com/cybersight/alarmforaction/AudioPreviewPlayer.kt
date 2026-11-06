package com.cybersight.alarmforaction

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import java.io.File

class AudioPreviewPlayer(private val context: Context) {
    private var player: MediaPlayer? = null
    private var toneGenerator: ToneGenerator? = null
    private val beepHandler = Handler(Looper.getMainLooper())

    fun play(uriString: String) {
        stop()
        val uri = parseUri(uriString)
        playUri(uri)
    }

    fun playDefaultAlarmTone() {
        stop()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: return
        playUri(uri)
    }

    private fun playUri(uri: Uri) {
        val current = MediaPlayer()
        player = current
        try {
            current.setOnErrorListener { _, _, _ ->
                if (player === current) stop()
                true
            }
            current.setOnCompletionListener { if (player === current) stop() }
            current.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            if (uri.scheme == "file") {
                current.setDataSource(uri.path ?: uri.toString())
            } else {
                current.setDataSource(context, uri)
            }
            current.isLooping = false
            current.prepare()
            current.start()
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    fun stop() {
        val previous = player
        player = null
        // release() is valid in every state, including the error state;
        // isPlaying()/stop() can throw and prevent cleanup in that state.
        try { previous?.release() } catch (_: Exception) { }
    }

    /** Simple repeating "beep beep" + vibration for quick-timer completion —
     *  a [ToneGenerator] tone rather than a bundled sound file, so it needs
     *  no audio asset, and deliberately distinct from the full alarm tone
     *  used for actual alarms. Repeats until [stopTimerAlert] is called. */
    fun startTimerAlert() {
        stopTimerAlert()
        val generator = ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
        toneGenerator = generator
        val runnable = object : Runnable {
            override fun run() {
                if (!playTimerBeep(generator)) return
                beepHandler.postDelayed({
                    playTimerBeep(generator)
                }, 350)
                beepHandler.postDelayed(this, 1200)
            }
        }
        beepHandler.post(runnable)
    }

    private fun playTimerBeep(generator: ToneGenerator): Boolean {
        if (toneGenerator !== generator) return false
        try {
            generator.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 200)
        } catch (_: Exception) {
            stopTimerAlert()
            return false
        }
        try { vibrate(200) } catch (_: Exception) { }
        return true
    }

    fun stopTimerAlert() {
        // Includes the second beep posted by the first, before release().
        beepHandler.removeCallbacksAndMessages(null)
        try { toneGenerator?.release() } catch (_: Exception) { }
        toneGenerator = null
    }

    private fun vibrate(durationMs: Long) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(durationMs)
        }
    }

    private fun parseUri(uriString: String): Uri {
        val uri = Uri.parse(uriString)
        return if (uri.scheme == null) Uri.fromFile(File(uriString)) else uri
    }
}
