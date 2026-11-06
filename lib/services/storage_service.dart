import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_model.dart';
import '../models/interval_session_models.dart';
import '../models/timetable_models.dart';

class StorageService {
  static const _alarmsKey = 'motivalarm.alarms';
  static const _settingsKey = 'motivalarm.settings';
  static const _sessionPresetsKey = 'motivalarm.sessionPresets';
  static const _timetableKey = 'motivalarm.timetable';
  static const _timetableTodayKey = 'motivalarm.timetableToday';
  static const _timetableHistoryKey = 'motivalarm.timetableHistory';

  Future<List<AlarmModel>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_alarmsKey) ?? const [];
    return encoded
        .map(
          (item) =>
              AlarmModel.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList()
      ..sort((a, b) {
        final aMinutes = a.timeHour * 60 + a.timeMinute;
        final bMinutes = b.timeHour * 60 + b.timeMinute;
        return aMinutes.compareTo(bMinutes);
      });
  }

  Future<void> saveAlarms(List<AlarmModel> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _alarmsKey,
      alarms.map((alarm) => alarm.encode()).toList(),
    );
  }

  Future<Map<String, Object?>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return {};
    return Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  Future<void> saveSettings(Map<String, Object?> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings));
  }

  Future<List<SessionPreset>> loadSessionPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_sessionPresetsKey) ?? const [];
    return encoded
        .map(
          (item) =>
              SessionPreset.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> saveSessionPresets(List<SessionPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _sessionPresetsKey,
      presets.map((preset) => preset.encode()).toList(),
    );
  }

  Future<List<TimetableTask>> loadTimetable() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_timetableKey) ?? const [];
    return encoded
        .map(
          (item) =>
              TimetableTask.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList()
      ..sort((a, b) => a.startMinutesOfDay.compareTo(b.startMinutesOfDay));
  }

  Future<void> saveTimetable(List<TimetableTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _timetableKey,
      tasks.map((task) => task.encode()).toList(),
    );
  }

  /// Returns today's shift/skip/done overrides; a record from a previous
  /// day is treated as absent, which is exactly the "resets tomorrow" rule.
  Future<TimetableDayOverride> loadDayOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_timetableTodayKey);
    if (raw != null) {
      final override = TimetableDayOverride.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (override.isToday) return override;
    }
    return TimetableDayOverride.emptyForToday();
  }

  Future<void> saveDayOverride(TimetableDayOverride override) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timetableTodayKey, override.encode());
  }

  Future<List<TaskRecord>> loadTaskHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_timetableHistoryKey) ?? const [];
    return encoded
        .map(
          (item) =>
              TaskRecord.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> appendTaskRecords(List<TaskRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final cutoff = TimetableDayOverride.dateKey(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    final existing = await loadTaskHistory();
    final kept = [...existing, ...records]
        .where((record) => record.date.compareTo(cutoff) >= 0)
        .toList();
    await prefs.setStringList(
      _timetableHistoryKey,
      kept.map((record) => record.encode()).toList(),
    );
  }
}
