import '../models/alarm_model.dart';
import 'native_alarm_bridge.dart';
import 'storage_service.dart';

class AlarmService {
  AlarmService({StorageService? storage, NativeAlarmBridge? bridge})
    : _storage = storage ?? StorageService(),
      _bridge = bridge ?? const NativeAlarmBridge();

  final StorageService _storage;
  final NativeAlarmBridge _bridge;

  /// Loads alarms, reconciling one-shots the native pipeline auto-disabled
  /// after firing — without this, a fired one-shot alarm still shows as
  /// enabled in the list even though it will never ring again.
  Future<List<AlarmModel>> loadAlarms() async {
    final alarms = await _storage.loadAlarms();
    final List<String> inactiveIds;
    try {
      inactiveIds = await _bridge.getInactiveAlarmIds();
    } catch (_) {
      return alarms;
    }
    final inactive = inactiveIds.toSet();
    var changed = false;
    final reconciled = alarms.map((alarm) {
      if (alarm.enabled &&
          alarm.repeatDays.isEmpty &&
          inactive.contains(alarm.id)) {
        changed = true;
        return alarm.copyWith(enabled: false);
      }
      return alarm;
    }).toList();
    if (changed) await _storage.saveAlarms(reconciled);
    return reconciled;
  }

  Future<void> saveAlarm(AlarmModel alarm) async {
    final alarms = await _storage.loadAlarms();
    final index = alarms.indexWhere((item) => item.id == alarm.id);
    final updated = alarm.copyWith(updatedAt: DateTime.now());
    if (index >= 0) {
      alarms[index] = updated;
    } else {
      alarms.add(updated);
    }
    await _storage.saveAlarms(alarms);
    if (updated.enabled) {
      await _bridge.updateAlarm(updated);
    } else {
      await _bridge.cancelAlarm(updated.id);
    }
  }

  Future<void> setEnabled(AlarmModel alarm, bool enabled) async {
    await saveAlarm(alarm.copyWith(enabled: enabled));
  }

  Future<void> deleteAlarm(String alarmId) async {
    final alarms = await _storage.loadAlarms();
    alarms.removeWhere((alarm) => alarm.id == alarmId);
    await _storage.saveAlarms(alarms);
    await _bridge.cancelAlarm(alarmId);
  }

  Future<void> previewAlarm(AlarmModel alarm) => _bridge.previewAlarm(alarm);
}
