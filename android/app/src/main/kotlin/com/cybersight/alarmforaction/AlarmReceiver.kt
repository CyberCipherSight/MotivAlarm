package com.cybersight.alarmforaction

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_ID) ?: return
        val store = AlarmStore(context)
        val alarm = intent.getStringExtra(AlarmScheduler.EXTRA_ALARM_JSON)
            ?.let { AlarmData.fromJson(JSONObject(it)) }
            ?: store.getAlarm(alarmId)
            ?: return
        store.upsert(alarm)

        val serviceIntent = Intent(context, AlarmForegroundService::class.java)
            .setAction(AlarmForegroundService.ACTION_START)
            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        val activityIntent = Intent(context, AlarmRingActivity::class.java)
            .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        context.startActivity(activityIntent)

        if (alarm.repeatDays.isEmpty()) {
            store.disable(alarm.id)
        } else {
            AlarmScheduler(context).schedule(alarm, alarm.nextTriggerMillis(System.currentTimeMillis() + 60_000L))
        }
    }
}
