import 'dart:convert';

enum VideoBehavior {
  playOnceThenTone,
  loopVideo,
  muteVideoPlayTone,
  videoAudioOnly;

  static VideoBehavior fromName(String? name) {
    return VideoBehavior.values.firstWhere(
      (behavior) => behavior.name == name,
      orElse: () => VideoBehavior.loopVideo,
    );
  }
}

class AlarmModel {
  const AlarmModel({
    required this.id,
    required this.timeHour,
    required this.timeMinute,
    required this.enabled,
    required this.repeatDays,
    required this.label,
    required this.snoozeMinutes,
    required this.videoBehavior,
    required this.vibrate,
    required this.volumeRampUp,
    required this.createdAt,
    required this.updatedAt,
    this.toneUri,
    this.videoUri,
    this.videoDurationSeconds,
  });

  final String id;
  final int timeHour;
  final int timeMinute;
  final bool enabled;
  final List<int> repeatDays;
  final String label;
  final int snoozeMinutes;
  final String? toneUri;
  final String? videoUri;
  final int? videoDurationSeconds;
  final VideoBehavior videoBehavior;
  final bool vibrate;
  final bool volumeRampUp;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasVideo => videoUri != null && videoUri!.isNotEmpty;

  static int clampSnoozeMinutes(int minutes) => minutes.clamp(1, 5);

  AlarmModel copyWith({
    String? id,
    int? timeHour,
    int? timeMinute,
    bool? enabled,
    List<int>? repeatDays,
    String? label,
    int? snoozeMinutes,
    String? toneUri,
    String? videoUri,
    int? videoDurationSeconds,
    VideoBehavior? videoBehavior,
    bool? vibrate,
    bool? volumeRampUp,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      timeHour: timeHour ?? this.timeHour,
      timeMinute: timeMinute ?? this.timeMinute,
      enabled: enabled ?? this.enabled,
      repeatDays: repeatDays ?? this.repeatDays,
      label: label ?? this.label,
      snoozeMinutes: clampSnoozeMinutes(snoozeMinutes ?? this.snoozeMinutes),
      toneUri: toneUri ?? this.toneUri,
      videoUri: videoUri ?? this.videoUri,
      videoDurationSeconds: videoDurationSeconds ?? this.videoDurationSeconds,
      videoBehavior: videoBehavior ?? this.videoBehavior,
      vibrate: vibrate ?? this.vibrate,
      volumeRampUp: volumeRampUp ?? this.volumeRampUp,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timeHour': timeHour,
      'timeMinute': timeMinute,
      'enabled': enabled,
      'repeatDays': repeatDays,
      'label': label,
      'snoozeMinutes': clampSnoozeMinutes(snoozeMinutes),
      'toneUri': toneUri,
      'videoUri': videoUri,
      'videoDurationSeconds': videoDurationSeconds,
      'videoBehavior': videoBehavior.name,
      'vibrate': vibrate,
      'volumeRampUp': volumeRampUp,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static AlarmModel fromJson(Map<String, dynamic> json) {
    return AlarmModel(
      id: json['id'] as String,
      timeHour: json['timeHour'] as int,
      timeMinute: json['timeMinute'] as int,
      enabled: json['enabled'] as bool? ?? true,
      repeatDays: (json['repeatDays'] as List<dynamic>? ?? const [])
          .map((day) => day as int)
          .toList(),
      label: json['label'] as String? ?? 'Alarm',
      snoozeMinutes: clampSnoozeMinutes(json['snoozeMinutes'] as int? ?? 5),
      toneUri: json['toneUri'] as String?,
      videoUri: json['videoUri'] as String?,
      videoDurationSeconds: json['videoDurationSeconds'] as int?,
      videoBehavior: VideoBehavior.fromName(json['videoBehavior'] as String?),
      vibrate: json['vibrate'] as bool? ?? true,
      volumeRampUp: json['volumeRampUp'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  String encode() => jsonEncode(toJson());
}
