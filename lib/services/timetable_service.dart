import '../models/timetable_models.dart';
import 'native_alarm_bridge.dart';
import 'storage_service.dart';

/// CRUD + alarm side-effects for the daily timetable, mirroring how
/// [AlarmService] pairs persistence with scheduling. Task alarms ride the
/// existing native pipeline as daily-repeating alarms (id `tt_<taskId>`);
/// the today-only shift/skip features work by rescheduling those alarms at
/// an explicit trigger time — after that one firing, the receiver's normal
/// repeat logic puts them back on their original daily schedule by itself.
class TimetableService {
  TimetableService({StorageService? storage, NativeAlarmBridge? bridge})
    : _storage = storage ?? StorageService(),
      _bridge = bridge ?? const NativeAlarmBridge();

  final StorageService _storage;
  final NativeAlarmBridge _bridge;

  Future<List<TimetableTask>> loadTasks() => _storage.loadTimetable();
  Future<TimetableDayOverride> loadOverride() => _storage.loadDayOverride();
  Future<List<TaskRecord>> loadHistory() => _storage.loadTaskHistory();

  Future<void> saveTask(TimetableTask task) async {
    final tasks = await _storage.loadTimetable();
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.add(task);
    }
    await _storage.saveTimetable(tasks);
    await _syncTaskAlarm(task);
  }

  Future<void> deleteTask(String taskId) async {
    final tasks = await _storage.loadTimetable();
    final task = tasks.where((t) => t.id == taskId).firstOrNull;
    tasks.removeWhere((t) => t.id == taskId);
    await _storage.saveTimetable(tasks);
    if (task != null) await _bridge.cancelAlarm(task.alarmId);
  }

  Future<void> _syncTaskAlarm(TimetableTask task) async {
    if (task.alarmEnabled) {
      await _bridge.updateAlarm(task.toAlarm());
    } else {
      await _bridge.cancelAlarm(task.alarmId);
    }
  }

  Future<void> markDone(TimetableTask task) async {
    final override = await _storage.loadDayOverride();
    if (override.doneTaskIds.contains(task.id)) return;
    await _storage.saveDayOverride(
      override.copyWith(doneTaskIds: [...override.doneTaskIds, task.id]),
    );
    await _storage.appendTaskRecords([
      TaskRecord(
        date: override.date,
        taskId: task.id,
        taskName: task.name,
        status: 'done',
      ),
    ]);
  }

  /// "I woke up now": shifts every not-yet-done, not-skipped task by
  /// (now − first task's planned start) for the rest of today only. Alarms
  /// are re-aimed at the shifted time today; when each fires, the native
  /// repeat logic reschedules it at its original time tomorrow.
  Future<TimetableDayOverride> shiftDay(List<TimetableTask> tasks) async {
    final override = await _storage.loadDayOverride();
    if (tasks.isEmpty || override.shiftMinutes != 0) return override;

    final now = DateTime.now();
    final first = tasks.first;
    final plannedStart = DateTime(
      now.year,
      now.month,
      now.day,
      first.startHour,
      first.startMinute,
    );
    final shiftMinutes = now.difference(plannedStart).inMinutes + 1;
    if (shiftMinutes <= 0) return override;

    final affected = tasks
        .where(
          (task) =>
              !override.doneTaskIds.contains(task.id) &&
              !override.skippedTaskIds.contains(task.id),
        )
        .toList();
    for (final task in affected.where((t) => t.alarmEnabled)) {
      final shifted = DateTime(
        now.year,
        now.month,
        now.day,
        task.startHour,
        task.startMinute,
      ).add(Duration(minutes: shiftMinutes));
      await _bridge.scheduleAlarmAt(
        task.toAlarm(),
        shifted.millisecondsSinceEpoch,
      );
    }

    final updated = override.copyWith(shiftMinutes: shiftMinutes);
    await _storage.saveDayOverride(updated);
    await _storage.appendTaskRecords([
      for (final task in affected)
        TaskRecord(
          date: override.date,
          taskId: task.id,
          taskName: task.name,
          status: 'shifted',
        ),
    ]);
    return updated;
  }

  /// Behind-schedule mode: [keepTaskIds] stay on today's plan, everything
  /// else still remaining is skipped for today — alarms re-aimed at
  /// tomorrow's original time, task kept (greyed), nothing deleted.
  Future<TimetableDayOverride> skipExcept(
    List<TimetableTask> remaining,
    Set<String> keepTaskIds,
  ) async {
    final override = await _storage.loadDayOverride();
    final skipped = remaining
        .where((task) => !keepTaskIds.contains(task.id))
        .toList();
    if (skipped.isEmpty) return override;

    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    for (final task in skipped.where((t) => t.alarmEnabled)) {
      final nextStart = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        task.startHour,
        task.startMinute,
      );
      await _bridge.scheduleAlarmAt(
        task.toAlarm(),
        nextStart.millisecondsSinceEpoch,
      );
    }

    final updated = override.copyWith(
      skippedTaskIds: {
        ...override.skippedTaskIds,
        ...skipped.map((t) => t.id),
      }.toList(),
    );
    await _storage.saveDayOverride(updated);
    await _storage.appendTaskRecords([
      for (final task in skipped)
        TaskRecord(
          date: override.date,
          taskId: task.id,
          taskName: task.name,
          status: 'skipped',
        ),
    ]);
    return updated;
  }
}
