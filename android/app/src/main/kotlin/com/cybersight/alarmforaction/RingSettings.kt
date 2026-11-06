package com.cybersight.alarmforaction

import android.content.Context

/**
 * The one user-tunable knob for how long an unattended alarm rings before it
 * pauses and waits for the user (see [AlarmResumeService]). Kept in
 * device-protected storage so the ringing path can read it before first
 * unlock after a reboot, exactly like [AlarmStore].
 */
object RingSettings {
    private const val PREFS = "motivalarm_ring"
    private const val KEY_TIMEOUT_MINUTES = "ringTimeoutMinutes"
    const val DEFAULT_TIMEOUT_MINUTES = 5

    /** 0 = never pause (ring until stopped), matching the old behaviour. */
    fun timeoutMinutes(context: Context): Int =
        prefs(context).getInt(KEY_TIMEOUT_MINUTES, DEFAULT_TIMEOUT_MINUTES).coerceIn(0, 60)

    fun setTimeoutMinutes(context: Context, minutes: Int) {
        prefs(context).edit().putInt(KEY_TIMEOUT_MINUTES, minutes.coerceIn(0, 60)).apply()
    }

    fun timeoutMillis(context: Context): Long = timeoutMinutes(context) * 60_000L

    private fun prefs(context: Context) = context.createDeviceProtectedStorageContext()
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
