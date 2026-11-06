package com.cybersight.alarmforaction

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmScheduler(private val context: Context) {
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val store = AlarmStore(context)

    fun schedule(alarm: AlarmData, triggerAtMillis: Long = alarm.nextTriggerMillis()) {
        store.upsert(alarm)
        if (!alarm.enabled) {
            cancel(alarm.id)
            return
        }
        val pendingIntent = receiverPendingIntent(alarm)
        val canScheduleExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
        if (canScheduleExact) {
            // setAlarmClock is what Android expects real alarm-clock apps to use: it shows
            // the status-bar alarm icon and is the most resistant to Doze/App Standby and
            // OEM battery killers. setExactAndAllowWhileIdle requires the same permission
            // without that extra protection, so there's no reason to prefer it here.
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAtMillis, contentPendingIntent(alarm.id)),
                pendingIntent
            )
        } else {
            // Without the exact-alarm permission, setAlarmClock/setExact* throw
            // SecurityException on API 31+. Fall back to a best-effort inexact alarm so
            // it still fires (possibly delayed by Doze) instead of never being scheduled.
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    fun cancel(alarmId: String) {
        alarmManager.cancel(receiverPendingIntent(alarmId))
        store.remove(alarmId)
    }

    fun snooze(alarmId: String, minutes: Int) {
        val alarm = store.getAlarm(alarmId) ?: return
        val triggerAt = System.currentTimeMillis() + AlarmData.clampSnoozeMinutes(minutes) * 60_000L
        schedule(alarm.copy(enabled = true), triggerAt)
    }

    fun stop(alarmId: String) {
        val serviceIntent = Intent(context, AlarmForegroundService::class.java).setAction(AlarmForegroundService.ACTION_STOP)
        context.startService(serviceIntent)
        val alarm = store.getAlarm(alarmId)
        if (alarm?.repeatDays?.isNotEmpty() == true && alarm.enabled) {
            schedule(alarm, alarm.nextTriggerMillis(System.currentTimeMillis() + 60_000L))
        } else {
            store.disable(alarmId)
        }
    }

    fun rescheduleEnabled() {
        store.getAlarms().filter { it.enabled }.forEach { schedule(it) }
    }

    fun getNextAlarmTime(): Long? {
        return store.getAlarms()
            .filter { it.enabled }
            .map { it.nextTriggerMillis() }
            .minOrNull()
    }

    private fun receiverPendingIntent(alarm: AlarmData): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_FIRE_ALARM)
            .putExtra(EXTRA_ALARM_ID, alarm.id)
            .putExtra(EXTRA_ALARM_JSON, alarm.toJson().toString())
        return PendingIntent.getBroadcast(context, requestCode(alarm.id), intent, flags())
    }

    private fun receiverPendingIntent(alarmId: String): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).setAction(ACTION_FIRE_ALARM)
        return PendingIntent.getBroadcast(context, requestCode(alarmId), intent, flags())
    }

    private fun contentPendingIntent(alarmId: String): PendingIntent {
        val intent = Intent(context, AlarmRingActivity::class.java)
            .putExtra(EXTRA_ALARM_ID, alarmId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode(alarmId) + 1,
            intent,
            flags(),
            backgroundActivityStartOptions()
        )
    }

    companion object {
        const val ACTION_FIRE_ALARM = "com.motivalarm.FIRE_ALARM"
        const val EXTRA_ALARM_ID = "alarmId"
        const val EXTRA_ALARM_JSON = "alarmJson"

        fun requestCode(alarmId: String): Int = alarmId.hashCode() and 0x7fffffff
        fun flags(): Int = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }
}
