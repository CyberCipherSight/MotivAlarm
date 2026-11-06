package com.cybersight.alarmforaction

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri

class VideoMetadataReader(private val context: Context) {
    fun getDurationSeconds(uriString: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            val uri = parseUri(uriString)
            if (uri.scheme == null) {
                retriever.setDataSource(uriString)
            } else {
                retriever.setDataSource(context, uri)
            }
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            ((durationMs + 999L) / 1000L).toInt()
        } catch (_: Exception) {
            0
        } finally {
            // Some providers/codecs also throw while closing the retriever.
            try { retriever.release() } catch (_: Exception) { }
        }
    }

    fun validate(uriString: String): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        return try {
            val uri = parseUri(uriString)
            if (uri.scheme == null) {
                retriever.setDataSource(uriString)
            } else {
                retriever.setDataSource(context, uri)
            }
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val duration = ((durationMs + 999L) / 1000L).toInt()
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val rawWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val rawHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val valid = duration > 0 && rawWidth > 0 && rawHeight > 0
            val quarterTurned = rotation == 90 || rotation == 270
            val displayWidth = if (quarterTurned) rawHeight else rawWidth
            val displayHeight = if (quarterTurned) rawWidth else rawHeight
            mapOf(
                "uri" to uriString,
                "durationSeconds" to duration,
                "valid" to valid,
                // Display-space dimensions (rotation already accounted for) so
                // callers can size a preview box to the clip's exact aspect
                // ratio without needing to know about rotation themselves.
                "displayWidth" to displayWidth,
                "displayHeight" to displayHeight,
                "errorMessage" to if (valid) null else "Could not read this video."
            )
        } catch (_: Exception) {
            mapOf(
                "uri" to uriString,
                "durationSeconds" to 0,
                "valid" to false,
                "displayWidth" to 0,
                "displayHeight" to 0,
                "errorMessage" to "Could not read this video."
            )
        } finally {
            // Some providers/codecs also throw while closing the retriever.
            try { retriever.release() } catch (_: Exception) { }
        }
    }

    fun persistUriPermission(uriString: String) {
        val uri = parseUri(uriString)
        if (uri.scheme != "content") return
        val flags = IntentFlags.readPersistable
        try {
            context.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: Exception) {
        }
    }

    private fun parseUri(uriString: String): Uri = Uri.parse(uriString)
}

private object IntentFlags {
    const val readPersistable = android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
}
