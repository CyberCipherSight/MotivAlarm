import 'package:flutter/services.dart';

import '../models/alarm_model.dart';
import '../models/permission_status_model.dart';
import '../models/video_info_model.dart';
import '../utils/constants.dart';

class NativeAlarmBridge {
  const NativeAlarmBridge();

  static const MethodChannel _channel = MethodChannel(AppConstants.channelName);

  Future<void> scheduleAlarm(AlarmModel alarm) {
    return _channel.invokeMethod<void>('scheduleAlarm', alarm.toJson());
  }

  Future<void> cancelAlarm(String alarmId) {
    return _channel.invokeMethod<void>('cancelAlarm', {'alarmId': alarmId});
  }

  Future<void> updateAlarm(AlarmModel alarm) {
    return _channel.invokeMethod<void>('updateAlarm', alarm.toJson());
  }

  /// Schedules [alarm] at an explicit moment instead of its computed next
  /// occurrence — the Timetable's today-only shift/skip. After it fires,
  /// the native receiver's normal repeat logic takes over again.
  Future<void> scheduleAlarmAt(AlarmModel alarm, int triggerAtMillis) {
    return _channel.invokeMethod<void>('updateAlarm', {
      ...alarm.toJson(),
      'triggerAtMillis': triggerAtMillis,
    });
  }

  Future<void> snoozeAlarm(String alarmId, int minutes) {
    return _channel.invokeMethod<void>('snoozeAlarm', {
      'alarmId': alarmId,
      'minutes': minutes,
    });
  }

  Future<void> stopAlarm(String alarmId) {
    return _channel.invokeMethod<void>('stopAlarm', {'alarmId': alarmId});
  }

  Future<int?> getNextAlarmTime() {
    return _channel.invokeMethod<int>('getNextAlarmTime');
  }

  /// Launches the real native ringing screen for [alarm] without scheduling
  /// anything, so Preview Alarm is pixel-identical to a real alarm firing.
  Future<void> previewAlarm(AlarmModel alarm) {
    return _channel.invokeMethod<void>('previewAlarm', alarm.toJson());
  }

  Future<List<PermissionStatusModel>> getPermissionStatuses() async {
    final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'getPermissionStatuses',
    );
    return (result ?? const [])
        .map(
          (item) =>
              PermissionStatusModel.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<bool> canScheduleExactAlarms() async {
    return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? false;
  }

  Future<bool> hasNotificationPermission() async {
    return await _channel.invokeMethod<bool>('hasNotificationPermission') ??
        false;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    return await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  Future<void> openFullScreenIntentSettings() {
    return _channel.invokeMethod<void>('openFullScreenIntentSettings');
  }

  Future<void> openBackgroundRestrictionSettings() {
    return _channel.invokeMethod<void>('openBackgroundRestrictionSettings');
  }

  Future<void> openUrl(String url) {
    return _channel.invokeMethod<void>('openUrl', {'url': url});
  }

  Future<int> getVideoDuration(String uri) async {
    return await _channel.invokeMethod<int>('getVideoDuration', {'uri': uri}) ??
        0;
  }

  Future<VideoInfoModel> validateVideo(String uri) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'validateVideo',
      {'uri': uri},
    );
    return VideoInfoModel.fromJson(
      result ?? {'uri': uri, 'durationSeconds': 0, 'valid': false},
    );
  }

  Future<void> persistVideoUriPermission(String uri) {
    return _channel.invokeMethod<void>('persistVideoUriPermission', {
      'uri': uri,
    });
  }

  Future<void> persistMediaUriPermission(String uri) {
    return _channel.invokeMethod<void>('persistMediaUriPermission', {
      'uri': uri,
    });
  }

  Future<void> previewAudio(String uri) {
    return _channel.invokeMethod<void>('previewAudio', {'uri': uri});
  }

  Future<void> previewDefaultAlarmTone() {
    return _channel.invokeMethod<void>('previewDefaultAlarmTone');
  }

  Future<void> stopAudioPreview() {
    return _channel.invokeMethod<void>('stopAudioPreview');
  }

  /// Repeating beep + vibration for quick-timer completion, distinct from
  /// the real alarm tone. Call [stopTimerAlert] to silence it.
  Future<void> startTimerAlert() {
    return _channel.invokeMethod<void>('startTimerAlert');
  }

  Future<void> stopTimerAlert() {
    return _channel.invokeMethod<void>('stopTimerAlert');
  }

  Future<bool> isBootReceiverEnabled() async {
    return await _channel.invokeMethod<bool>('isBootReceiverEnabled') ?? false;
  }

  /// How long an unattended alarm rings before it pauses and waits for the
  /// user to pick up their phone. 0 = never pause.
  Future<int> getRingTimeoutMinutes() async {
    return await _channel.invokeMethod<int>('getRingTimeoutMinutes') ?? 5;
  }

  Future<void> setRingTimeoutMinutes(int minutes) {
    return _channel.invokeMethod<void>('setRingTimeoutMinutes', {
      'minutes': minutes,
    });
  }

  /// Optional "Display over other apps" — improves lock-screen launch
  /// reliability on OEM skins (notably MIUI). User-grantable in Settings.
  Future<bool> canDrawOverlays() async {
    return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
  }

  Future<void> openOverlaySettings() {
    return _channel.invokeMethod<void>('openOverlaySettings');
  }

  /// Ids the native pipeline has auto-disabled (one-shot alarms that already
  /// fired). Used to reconcile the Flutter-side list with reality.
  Future<List<String>> getInactiveAlarmIds() async {
    final result = await _channel.invokeListMethod<String>(
      'getInactiveAlarmIds',
    );
    return result ?? const [];
  }

  /// Starts the native interval-session foreground service, which owns the
  /// countdown and cues so the session survives screen-off/backgrounding.
  /// [phasesJson] is a JSON array of `{label, seconds, isBreak}` maps.
  Future<void> startIntervalSession(String phasesJson) {
    return _channel.invokeMethod<void>('startIntervalSession', {
      'phasesJson': phasesJson,
    });
  }

  Future<void> pauseIntervalSession() {
    return _channel.invokeMethod<void>('pauseIntervalSession');
  }

  Future<void> resumeIntervalSession() {
    return _channel.invokeMethod<void>('resumeIntervalSession');
  }

  Future<void> endIntervalSession() {
    return _channel.invokeMethod<void>('endIntervalSession');
  }

  /// Authoritative session state from the native service; the Flutter UI
  /// only mirrors this for display and re-syncs from it on resume.
  Future<Map<String, dynamic>> getIntervalSessionState() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getIntervalSessionState',
    );
    return result ?? const {'active': false, 'running': false};
  }
}
