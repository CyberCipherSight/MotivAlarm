import 'dart:convert';

import 'alarm_model.dart';

/// One block in the single daily routine. Deliberately minimal: name, start,
/// duration, optional video alarm, optional link to a saved interval-session
/// preset. No categories, sub-tasks, or per-day variants.
class TimetableTask {
  const TimetableTask({
    required this.id,
    required this.name,
    required this.startHour,
    required this.startMinute,
    required this.durationMinutes,
    required this.alarmEnabled,
    this.videoUri,
    this.videoDurationSeconds,
    this.sessionPresetId,
  });

  final String id;
  final String name;
  final int startHour;
  final int startMinute;
  final int durationMinutes;
  final bool alarmEnabled;
  final String? videoUri;
  final int? videoDurationSeconds;
  final String? sessionPresetId;

  bool get hasVideo => videoUri != null && videoUri!.isNotEmpty;
  bool get isSessionTask => sessionPresetId != null;

  int get startMinutesOfDay => startHour * 60 + startMinute;

  /// The alarm identity in the native pipeline. Namespaced so a task alarm
  /// can never collide with a normal video alarm's request codes, and so
  /// task alarms are distinguishable in the native store.
  String get alarmId => 'tt_$id';

  /// Expands the task into a daily-repeating alarm that rides the existing
  /// pipeline untouched: full-screen video over the lock screen, boot
  /// rescheduling, snooze — all for free.
  AlarmModel toAlarm() {
    final now = DateTime.now();
    return AlarmModel(
      id: alarmId,
      timeHour: startHour,
      timeMinute: startMinute,
      enabled: alarmEnabled,
      repeatDays: const [1, 2, 3, 4, 5, 6, 7],
      label: name,
      snoozeMinutes: 5,
      videoUri: videoUri,
      videoDurationSeconds: videoDurationSeconds,
      videoBehavior: hasVideo
          ? VideoBehavior.videoAudioOnly
          : VideoBehavior.muteVideoPlayTone,
      vibrate: true,
      volumeRampUp: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  TimetableTask copyWith({
    String? name,
    int? startHour,
    int? startMinute,
    int? durationMinutes,
    bool? alarmEnabled,
    String? Function()? videoUri,
    int? Function()? videoDurationSeconds,
    String? Function()? sessionPresetId,
  }) {
    return TimetableTask(
      id: id,
      name: name ?? this.name,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      videoUri: videoUri != null ? videoUri() : this.videoUri,
      videoDurationSeconds: videoDurationSeconds != null
          ? videoDurationSeconds()
          : this.videoDurationSeconds,
      sessionPresetId: sessionPresetId != null
          ? sessionPresetId()
          : this.sessionPresetId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startHour': startHour,
    'startMinute': startMinute,
    'durationMinutes': durationMinutes,
    'alarmEnabled': alarmEnabled,
    'videoUri': videoUri,
    'videoDurationSeconds': videoDurationSeconds,
    'sessionPresetId': sessionPresetId,
  };

  factory TimetableTask.fromJson(Map<String, dynamic> json) => TimetableTask(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    startHour: json['startHour'] as int? ?? 0,
    startMinute: json['startMinute'] as int? ?? 0,
    durationMinutes: json['durationMinutes'] as int? ?? 30,
    alarmEnabled: json['alarmEnabled'] as bool? ?? false,
    videoUri: json['videoUri'] as String?,
    videoDurationSeconds: json['videoDurationSeconds'] as int?,
    sessionPresetId: json['sessionPresetId'] as String?,
  );

  String encode() => jsonEncode(toJson());
}

/// Today-only adjustments: an "I woke up now" shift and/or skipped tasks.
/// Keyed by date and simply ignored (never migrated) when the date isn't
/// today — the reset-at-midnight rule falls out of that for free.
class TimetableDayOverride {
  const TimetableDayOverride({
    required this.date,
    this.shiftMinutes = 0,
    this.skippedTaskIds = const [],
    this.doneTaskIds = const [],
  });

  /// yyyy-MM-dd
  final String date;
  final int shiftMinutes;
  final List<String> skippedTaskIds;
  final List<String> doneTaskIds;

  bool get isToday => date == dateKey(DateTime.now());

  static String dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static TimetableDayOverride emptyForToday() =>
      TimetableDayOverride(date: dateKey(DateTime.now()));

  TimetableDayOverride copyWith({
    int? shiftMinutes,
    List<String>? skippedTaskIds,
    List<String>? doneTaskIds,
  }) {
    return TimetableDayOverride(
      date: date,
      shiftMinutes: shiftMinutes ?? this.shiftMinutes,
      skippedTaskIds: skippedTaskIds ?? this.skippedTaskIds,
      doneTaskIds: doneTaskIds ?? this.doneTaskIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'shiftMinutes': shiftMinutes,
    'skippedTaskIds': skippedTaskIds,
    'doneTaskIds': doneTaskIds,
  };

  factory TimetableDayOverride.fromJson(Map<String, dynamic> json) =>
      TimetableDayOverride(
        date: json['date'] as String? ?? '',
        shiftMinutes: json['shiftMinutes'] as int? ?? 0,
        skippedTaskIds: (json['skippedTaskIds'] as List? ?? const [])
            .cast<String>(),
        doneTaskIds: (json['doneTaskIds'] as List? ?? const []).cast<String>(),
      );

  String encode() => jsonEncode(toJson());
}

/// One line of completion history: on [date], [taskName] was done/skipped/
/// shifted. Task name is denormalized so history stays readable after a
/// task is renamed or deleted.
class TaskRecord {
  const TaskRecord({
    required this.date,
    required this.taskId,
    required this.taskName,
    required this.status,
  });

  final String date;
  final String taskId;
  final String taskName;

  /// 'done' | 'skipped' | 'shifted'
  final String status;

  Map<String, dynamic> toJson() => {
    'date': date,
    'taskId': taskId,
    'taskName': taskName,
    'status': status,
  };

  factory TaskRecord.fromJson(Map<String, dynamic> json) => TaskRecord(
    date: json['date'] as String? ?? '',
    taskId: json['taskId'] as String? ?? '',
    taskName: json['taskName'] as String? ?? '',
    status: json['status'] as String? ?? '',
  );

  String encode() => jsonEncode(toJson());
}
