package com.cybersight.alarmforaction

import android.content.Context
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.VideoView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

/**
 * `video_player`/Media3-ExoPlayer selects a MediaTek hardware decoder
 * (c2.mtk.avc.decoder) for certain non-16px-aligned resolutions that renders
 * a corrupted/torn texture on MediaTek-chipset devices — a confirmed, open
 * Flutter engine bug (flutter/flutter#174026) with no fix at the Dart API
 * level. `android.widget.VideoView`/`MediaPlayer` goes through a different
 * decoder-selection path that doesn't hit it — it's what the real alarm
 * ringing screen already uses and has never shown this corruption. This
 * embeds that same proven-reliable native player as a Flutter PlatformView
 * for in-app preview surfaces (home feed, video picker) instead of
 * `video_player`.
 */
class NativeVideoView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<*, *>?
) : PlatformView, MethodChannel.MethodCallHandler {
    private val root = FrameLayout(context)
    private val videoView = VideoView(context)
    private val channel = MethodChannel(messenger, "motivalarm/native_video_view_$viewId")
    private var shouldLoop = true
    private var playing = true
    private var unavailable = false
    private var disposed = false
    // Dart confirms the owning route is still visible after async creation.
    private var previewVisible = false
    private var prepared = false
    private var needsFirstFrame = true

    init {
        channel.setMethodCallHandler(this)
        root.clipChildren = true
        root.addView(videoView, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))

        val uriString = creationParams?.get("uri") as? String
        val muted = creationParams?.get("muted") as? Boolean ?: true
        playing = creationParams?.get("playing") as? Boolean ?: true
        shouldLoop = creationParams?.get("looping") as? Boolean ?: true
        instances.add(this)
        updateVisibility()

        if (!uriString.isNullOrBlank()) {
            try {
                val uri = parseUri(uriString)
                videoView.setOnPreparedListener { player ->
                    if (disposed || unavailable) return@setOnPreparedListener
                    try {
                        player.isLooping = shouldLoop
                        if (muted) player.setVolume(0f, 0f)
                        fillCrop(player.videoWidth, player.videoHeight)
                        prepared = true
                        updateVisibility()
                    } catch (_: Exception) {
                        failPlayback()
                    }
                }
                videoView.setOnCompletionListener {
                    try {
                        if (shouldLoop && playing && previewVisible && hostResumed && !disposed && !unavailable) {
                            videoView.seekTo(0)
                            videoView.start()
                        }
                    } catch (_: Exception) {
                        failPlayback()
                    }
                }
                videoView.setOnErrorListener { _, _, _ ->
                    failPlayback()
                    true
                }
                videoView.setVideoURI(uri)
            } catch (_: Exception) {
                failPlayback()
                // Leave a blank surface — the Dart side already has its own
                // placeholder for alarms with no/unreadable video.
            }
        }
    }

    private fun failPlayback() {
        unavailable = true
        prepared = false
        try { videoView.stopPlayback() } catch (_: Exception) { }
    }

    private fun updateVisibility() {
        val visible = previewVisible && hostResumed && !disposed
        // Pausing alone leaves the SurfaceView visible over other routes.
        root.visibility = if (visible) View.VISIBLE else View.INVISIBLE
        if (!prepared || unavailable || disposed) return
        try {
            if (visible && (playing || needsFirstFrame)) videoView.start()
            if (!visible || !playing) videoView.pause()
            if (visible) needsFirstFrame = false
        } catch (_: Exception) {
            failPlayback()
        }
    }

    /** Scales [videoView] up to cover the root bounds (cropping overflow via
     *  the root's clipChildren) instead of VideoView's default letterboxing. */
    private fun fillCrop(videoWidth: Int, videoHeight: Int) {
        if (videoWidth <= 0 || videoHeight <= 0) return
        root.post {
            if (disposed || unavailable) return@post
            val containerWidth = root.width.takeIf { it > 0 } ?: return@post
            val containerHeight = root.height.takeIf { it > 0 } ?: return@post
            val scale = maxOf(
                containerWidth.toFloat() / videoWidth,
                containerHeight.toFloat() / videoHeight
            )
            videoView.layoutParams = FrameLayout.LayoutParams(
                (videoWidth * scale).toInt(),
                (videoHeight * scale).toInt(),
                Gravity.CENTER
            )
        }
    }

    private fun parseUri(uriString: String): Uri {
        val uri = Uri.parse(uriString)
        return if (uri.scheme == null) Uri.fromFile(File(uriString)) else uri
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setVisibility" -> {
                previewVisible = call.argument<Boolean>("visible") ?: false
                playing = call.argument<Boolean>("playing") ?: playing
                updateVisibility()
                result.success(null)
            }
            "play", "pause" -> {
                playing = call.method == "play"
                updateVisibility()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        disposed = true
        instances.remove(this)
        root.visibility = View.INVISIBLE
        channel.setMethodCallHandler(null)
        videoView.setOnPreparedListener(null)
        videoView.setOnCompletionListener(null)
        failPlayback()
    }

    companion object {
        private val instances = java.util.Collections.newSetFromMap(
            java.util.WeakHashMap<NativeVideoView, Boolean>()
        )
        private var hostResumed = false

        fun setHostResumed(resumed: Boolean) {
            hostResumed = resumed
            instances.toList().forEach { it.updateVisibility() }
        }
    }
}

class NativeVideoViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativeVideoView(context, messenger, viewId, args as? Map<*, *>)
    }
}
