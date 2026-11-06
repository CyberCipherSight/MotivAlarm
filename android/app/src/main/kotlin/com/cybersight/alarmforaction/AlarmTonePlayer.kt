package com.cybersight.alarmforaction

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File

/** Owns alarm audio, including failures delivered after preparation/playback. */
internal class AlarmTonePlayer(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var generator: ToneGenerator? = null
    var isActive = false
        private set

    fun start(chosenTone: String?, volume: Float = 1f) {
        if (isActive) return
        isActive = true
        val candidates = buildList {
            chosenTone?.takeIf { it.isNotBlank() && it != "silent" }?.let { add(it) }
            // A default URI can itself point to a deleted file. Try independent
            // system sounds before falling back to a generated, file-free beep.
            for (type in listOf(RingtoneManager.TYPE_ALARM, RingtoneManager.TYPE_NOTIFICATION, RingtoneManager.TYPE_RINGTONE)) {
                RingtoneManager.getDefaultUri(type)?.let { add(it.toString()) }
            }
        }.distinct()
        tryNext(candidates.iterator(), volume)
    }

    private fun tryNext(candidates: Iterator<String>, volume: Float) {
        if (!isActive) return
        if (!candidates.hasNext()) {
            startBeep(volume)
            return
        }
        var candidate: MediaPlayer? = null
        try {
            val value = candidates.next()
            val parsed = Uri.parse(value)
            val uri = if (parsed.scheme == null) Uri.fromFile(File(value)) else parsed
            val current = MediaPlayer()
            candidate = current
            player = current
            current.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            current.isLooping = true
            current.setVolume(volume, volume)
            val timeout = Runnable { fail(current, candidates, volume) }
            current.setOnErrorListener { _, what, extra ->
                Log.w(TAG, "Alarm audio failed ($what, $extra); trying fallback")
                fail(current, candidates, volume)
                true
            }
            current.setOnPreparedListener {
                if (player === current && isActive) {
                    handler.removeCallbacks(timeout)
                    try {
                        current.start()
                    } catch (_: Exception) {
                        fail(current, candidates, volume)
                    }
                }
            }
            current.setDataSource(context, uri)
            current.prepareAsync()
            handler.postDelayed(timeout, 5_000L)
        } catch (_: Exception) {
            candidate?.let { release(it) }
            player = null
            tryNext(candidates, volume)
        }
    }

    private fun fail(current: MediaPlayer, candidates: Iterator<String>, volume: Float) {
        // Ignore callbacks from a released player or a stopped/replaced alarm.
        if (player !== current || !isActive) return
        handler.removeCallbacksAndMessages(null)
        player = null
        release(current)
        tryNext(candidates, volume)
    }

    private fun startBeep(volume: Float) {
        try {
            val current = ToneGenerator(AudioManager.STREAM_ALARM, (volume * ToneGenerator.MAX_VOLUME).toInt())
            generator = current
            val beep = object : Runnable {
                override fun run() {
                    if (!isActive || generator !== current) return
                    try {
                        current.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 700)
                        handler.postDelayed(this, 1_200L)
                    } catch (_: Exception) {
                        stop()
                        Log.w(TAG, "Alarm audio output is unavailable")
                    }
                }
            }
            handler.post(beep)
        } catch (_: Exception) {
            isActive = false
            Log.w(TAG, "Alarm audio output is unavailable")
        }
    }

    fun stop() {
        isActive = false
        handler.removeCallbacksAndMessages(null)
        val previous = player
        player = null
        previous?.let { release(it) }
        val previousGenerator = generator
        generator = null
        try { previousGenerator?.release() } catch (_: Exception) { }
    }

    private fun release(current: MediaPlayer) {
        try {
            current.setOnErrorListener(null)
            current.setOnPreparedListener(null)
        } catch (_: Exception) { }
        try { current.release() } catch (_: Exception) { }
    }

    private companion object {
        const val TAG = "AlarmTonePlayer"
    }
}
