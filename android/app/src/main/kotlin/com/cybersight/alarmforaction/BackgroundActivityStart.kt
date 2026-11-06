package com.cybersight.alarmforaction

import android.app.ActivityOptions
import android.os.Build
import android.os.Bundle

/**
 * Apps targeting API 35+ no longer implicitly grant their PendingIntents
 * background-activity-launch rights — must opt in explicitly per intent, or
 * the alarm's full-screen activity can silently fail to appear on top of
 * the lock screen on Android 15+. Exact alarms are an exempted use case,
 * but the exemption still requires this opt-in on the PendingIntent itself.
 * https://developer.android.com/guide/components/activities/background-starts
 */
fun backgroundActivityStartOptions(): Bundle? {
    if (Build.VERSION.SDK_INT < 35) return null
    return ActivityOptions.makeBasic()
        .apply { pendingIntentCreatorBackgroundActivityStartMode = ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED }
        .toBundle()
}
