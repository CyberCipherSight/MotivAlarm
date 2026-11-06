import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_alarm_bridge.dart';
import 'storage_service.dart';

class ImportResult {
  const ImportResult({
    required this.alarmCount,
    required this.taskCount,
    required this.presetCount,
    required this.brokenVideoNames,
  });

  final int alarmCount;
  final int taskCount;
  final int presetCount;

  /// Labels of alarms/tasks whose video URI is no longer readable —
  /// picked-video permissions don't survive reinstall, so these need
  /// re-picking. Sound stays safe meanwhile (native tone fallback).
  final List<String> brokenVideoNames;
}

/// Manual export/import of all app data as one JSON file via the system
/// file picker (Storage Access Framework) — fully local, no accounts, no
/// network, consistent with the published privacy policy. Also hosts the
/// post-restore self-heal used on app start after Android Auto Backup.
class BackupService {
  BackupService({StorageService? storage, NativeAlarmBridge? bridge})
    : _storage = storage ?? StorageService(),
      _bridge = bridge ?? const NativeAlarmBridge();

  final StorageService _storage;
  final NativeAlarmBridge _bridge;

  static const _version = 1;
  static const _lastExportKey = 'motivalarm.lastExport';
  static const _alarmsKey = 'motivalarm.alarms';
  static const _settingsKey = 'motivalarm.settings';
  static const _sessionPresetsKey = 'motivalarm.sessionPresets';
  static const _timetableKey = 'motivalarm.timetable';
  static const _timetableHistoryKey = 'motivalarm.timetableHistory';

  Future<DateTime?> lastExportDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastExportKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Returns true if the user picked a location and the file was written.
  Future<bool> exportBackup() async {
    final prefs = await SharedPreferences.getInstance();
    List<Object?> decodeList(String key) =>
        (prefs.getStringList(key) ?? const [])
            .map((item) => jsonDecode(item))
            .toList();

    final payload = <String, Object?>{
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'alarms': decodeList(_alarmsKey),
      'settings': prefs.getString(_settingsKey) != null
          ? jsonDecode(prefs.getString(_settingsKey)!)
          : <String, Object?>{},
      'sessionPresets': decodeList(_sessionPresetsKey),
      'timetable': decodeList(_timetableKey),
      'timetableHistory': decodeList(_timetableHistoryKey),
    };

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save AlarmForAction backup',
      fileName: 'alarmforaction-backup-$stamp.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
      ),
    );
    if (path == null) return false;
    await prefs.setString(_lastExportKey, now.toIso8601String());
    return true;
  }

  /// Lets the user pick a backup file, replaces all app data with its
  /// contents, re-registers every alarm, and reports what came back.
  /// Returns null if the user cancelled. Throws [FormatException] on an
  /// unreadable/unsupported file.
  Future<ImportResult?> importBackup() async {
    final picked = await FilePicker.pickFiles(withData: true);
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return null;

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Not a valid backup file.');
    }
    if (payload['version'] != _version) {
      throw const FormatException(
        'This backup was made by an incompatible app version.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    Future<void> writeList(String key, Object? value) => prefs.setStringList(
      key,
      (value as List? ?? const []).map((item) => jsonEncode(item)).toList(),
    );

    await writeList(_alarmsKey, payload['alarms']);
    await writeList(_sessionPresetsKey, payload['sessionPresets']);
    await writeList(_timetableKey, payload['timetable']);
    await writeList(_timetableHistoryKey, payload['timetableHistory']);
    await prefs.setString(
      _settingsKey,
      jsonEncode(payload['settings'] ?? <String, Object?>{}),
    );

    final alarms = await _storage.loadAlarms();
    final tasks = await _storage.loadTimetable();
    final presets = await _storage.loadSessionPresets();
    await rescheduleAll();
    final broken = await findBrokenVideos();
    return ImportResult(
      alarmCount: alarms.length,
      taskCount: tasks.length,
      presetCount: presets.length,
      brokenVideoNames: broken,
    );
  }

  /// Re-registers every enabled alarm and timetable alarm with the native
  /// pipeline. Scheduling is idempotent, so this is safe to run on every
  /// app start — which is what makes a fresh install restored by Android
  /// Auto Backup ring without the user touching anything.
  Future<void> rescheduleAll() async {
    // One-shots the native pipeline already fired and disabled must stay
    // off — re-registering them here would silently re-arm them for
    // tomorrow. (After a fresh restore the native store is empty, so this
    // set is empty and everything from the backup gets scheduled.)
    final Set<String> nativelyDisabled;
    try {
      nativelyDisabled = (await _bridge.getInactiveAlarmIds()).toSet();
    } catch (_) {
      return;
    }
    final alarms = await _storage.loadAlarms();
    for (final alarm in alarms.where(
      (alarm) =>
          alarm.enabled &&
          !(alarm.repeatDays.isEmpty && nativelyDisabled.contains(alarm.id)),
    )) {
      await _bridge.updateAlarm(alarm);
    }
    final tasks = await _storage.loadTimetable();
    for (final task in tasks.where((task) => task.alarmEnabled)) {
      await _bridge.updateAlarm(task.toAlarm());
    }
  }

  /// Labels of alarms and timetable tasks whose video can no longer be
  /// read (URI permissions don't survive reinstall).
  Future<List<String>> findBrokenVideos() async {
    final broken = <String>[];
    Future<bool> unreadable(String uri) async {
      try {
        return !(await _bridge.validateVideo(uri)).valid;
      } catch (_) {
        return true;
      }
    }

    final alarms = await _storage.loadAlarms();
    for (final alarm in alarms.where((alarm) => alarm.hasVideo)) {
      if (await unreadable(alarm.videoUri!)) {
        broken.add(alarm.label.isEmpty ? 'Alarm' : alarm.label);
      }
    }
    final tasks = await _storage.loadTimetable();
    for (final task in tasks.where((task) => task.hasVideo)) {
      if (await unreadable(task.videoUri!)) broken.add(task.name);
    }
    return broken;
  }
}
