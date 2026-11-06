package com.cybersight.alarmforaction

import android.content.Context
import org.json.JSONArray

class AlarmStore(context: Context) {
    // Device-protected storage so alarms are readable before the user's
    // first unlock after a reboot — required for the direct-boot-aware
    // BootReceiver (LOCKED_BOOT_COMPLETED) to actually restore and ring
    // alarms in that window. moveSharedPreferencesFrom migrates the legacy
    // credential-protected file once and is a cheap no-op afterwards.
    private val prefs = run {
        val storageContext = context.createDeviceProtectedStorageContext()
        storageContext.moveSharedPreferencesFrom(context, PREFS_NAME)
        storageContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private companion object {
        const val PREFS_NAME = "motivalarm_native"
    }

    fun getAlarms(): List<AlarmData> {
        val raw = prefs.getString("alarms", "[]") ?: "[]"
        val array = JSONArray(raw)
        return buildList {
            for (i in 0 until array.length()) {
                add(AlarmData.fromJson(array.getJSONObject(i)))
            }
        }
    }

    fun getAlarm(id: String): AlarmData? = getAlarms().firstOrNull { it.id == id }

    fun upsert(alarm: AlarmData) {
        val updated = getAlarms().filterNot { it.id == alarm.id }.toMutableList()
        updated.add(alarm)
        saveAll(updated)
    }

    fun remove(id: String) {
        saveAll(getAlarms().filterNot { it.id == id })
    }

    fun disable(id: String) {
        val updated = getAlarms().map {
            if (it.id == id) it.copy(enabled = false) else it
        }
        saveAll(updated)
    }

    private fun saveAll(alarms: List<AlarmData>) {
        val array = JSONArray()
        alarms.forEach { array.put(it.toJson()) }
        prefs.edit().putString("alarms", array.toString()).apply()
    }
}
