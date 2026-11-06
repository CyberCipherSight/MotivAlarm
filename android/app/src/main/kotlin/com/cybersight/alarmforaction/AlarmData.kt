package com.cybersight.alarmforaction

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

data class AlarmData(
    val id: String,
    val timeHour: Int,
    val timeMinute: Int,
    val enabled: Boolean,
    val repeatDays: List<Int>,
    val label: String,
    val snoozeMinutes: Int,
    val toneUri: String?,
    val videoUri: String?,
    val videoDurationSeconds: Int?,
    val videoBehavior: String,
    val vibrate: Boolean,
    val volumeRampUp: Boolean,
    val createdAt: String,
    val updatedAt: String
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("id", id)
            .put("timeHour", timeHour)
            .put("timeMinute", timeMinute)
            .put("enabled", enabled)
            .put("repeatDays", JSONArray(repeatDays))
            .put("label", label)
            .put("snoozeMinutes", snoozeMinutes)
            .put("toneUri", toneUri)
            .put("videoUri", videoUri)
            .put("videoDurationSeconds", videoDurationSeconds)
            .put("videoBehavior", videoBehavior)
            .put("vibrate", vibrate)
            .put("volumeRampUp", volumeRampUp)
            .put("createdAt", createdAt)
            .put("updatedAt", updatedAt)
    }

    fun nextTriggerMillis(fromMillis: Long = System.currentTimeMillis()): Long {
        val now = Calendar.getInstance().apply { timeInMillis = fromMillis }
        val candidates = mutableListOf<Long>()

        if (repeatDays.isEmpty()) {
            val candidate = Calendar.getInstance().apply {
                timeInMillis = fromMillis
                set(Calendar.HOUR_OF_DAY, timeHour)
                set(Calendar.MINUTE, timeMinute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= fromMillis) add(Calendar.DAY_OF_YEAR, 1)
            }
            return candidate.timeInMillis
        }

        repeatDays.forEach { day ->
            val candidate = Calendar.getInstance().apply {
                timeInMillis = fromMillis
                set(Calendar.HOUR_OF_DAY, timeHour)
                set(Calendar.MINUTE, timeMinute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                val androidDay = flutterDayToCalendar(day)
                val daysAhead = (androidDay - get(Calendar.DAY_OF_WEEK) + 7) % 7
                add(Calendar.DAY_OF_YEAR, daysAhead)
                if (timeInMillis <= fromMillis) add(Calendar.DAY_OF_YEAR, 7)
            }
            candidates.add(candidate.timeInMillis)
        }
        return candidates.minOrNull() ?: now.timeInMillis
    }

    companion object {
        fun fromMap(map: Map<*, *>): AlarmData {
            val days = (map["repeatDays"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
            return AlarmData(
                id = map["id"].toString(),
                timeHour = (map["timeHour"] as Number).toInt(),
                timeMinute = (map["timeMinute"] as Number).toInt(),
                enabled = map["enabled"] as? Boolean ?: true,
                repeatDays = days,
                label = map["label"] as? String ?: "Alarm",
                snoozeMinutes = clampSnoozeMinutes((map["snoozeMinutes"] as? Number)?.toInt() ?: 5),
                toneUri = map["toneUri"] as? String,
                videoUri = map["videoUri"] as? String,
                videoDurationSeconds = (map["videoDurationSeconds"] as? Number)?.toInt(),
                videoBehavior = map["videoBehavior"] as? String ?: "loopVideo",
                vibrate = map["vibrate"] as? Boolean ?: true,
                volumeRampUp = map["volumeRampUp"] as? Boolean ?: false,
                createdAt = map["createdAt"] as? String ?: "",
                updatedAt = map["updatedAt"] as? String ?: ""
            )
        }

        fun fromJson(json: JSONObject): AlarmData {
            val days = mutableListOf<Int>()
            val repeat = json.optJSONArray("repeatDays") ?: JSONArray()
            for (i in 0 until repeat.length()) days.add(repeat.optInt(i))
            return AlarmData(
                id = json.getString("id"),
                timeHour = json.getInt("timeHour"),
                timeMinute = json.getInt("timeMinute"),
                enabled = json.optBoolean("enabled", true),
                repeatDays = days,
                label = json.optString("label", "Alarm"),
                snoozeMinutes = clampSnoozeMinutes(json.optInt("snoozeMinutes", 5)),
                toneUri = json.optString("toneUri").takeIf { it.isNotEmpty() && it != "null" },
                videoUri = json.optString("videoUri").takeIf { it.isNotEmpty() && it != "null" },
                videoDurationSeconds = if (json.isNull("videoDurationSeconds")) null else json.optInt("videoDurationSeconds"),
                videoBehavior = json.optString("videoBehavior", "loopVideo"),
                vibrate = json.optBoolean("vibrate", true),
                volumeRampUp = json.optBoolean("volumeRampUp", false),
                createdAt = json.optString("createdAt", ""),
                updatedAt = json.optString("updatedAt", "")
            )
        }

        private fun flutterDayToCalendar(day: Int): Int {
            return when (day) {
                1 -> Calendar.MONDAY
                2 -> Calendar.TUESDAY
                3 -> Calendar.WEDNESDAY
                4 -> Calendar.THURSDAY
                5 -> Calendar.FRIDAY
                6 -> Calendar.SATURDAY
                else -> Calendar.SUNDAY
            }
        }

        fun clampSnoozeMinutes(minutes: Int): Int = minutes.coerceIn(1, 5)
    }
}
