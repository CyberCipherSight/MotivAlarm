import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../widgets/local_audio_picker_card.dart';
import '../widgets/repeat_day_selector.dart';
import '../widgets/time_picker_card.dart';
import '../widgets/video_picker_card.dart';

class EditAlarmScreen extends StatefulWidget {
  const EditAlarmScreen({this.alarm, super.key});

  final AlarmModel? alarm;

  @override
  State<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends State<EditAlarmScreen> {
  static const _labelMaxLength = 12;

  final _service = AlarmService();
  late final TextEditingController _labelController;
  late int _hour;
  late int _minute;
  late List<int> _repeatDays;
  late bool _videoSoundOn;
  late bool _backupToneOn;
  late String _soundMode;
  late bool _vibrate;
  late bool _volumeRampUp;
  String? _toneUri;
  String? _videoUri;
  int? _videoDurationSeconds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    _labelController = TextEditingController(text: alarm?.label ?? '');
    final now = TimeOfDay.now();
    _hour = alarm?.timeHour ?? now.hour;
    _minute = alarm?.timeMinute ?? now.minute;
    _repeatDays = [...?alarm?.repeatDays];
    _toneUri = alarm?.toneUri;
    _videoUri = alarm?.videoUri;
    _videoDurationSeconds = alarm?.videoDurationSeconds;
    _vibrate = alarm?.vibrate ?? true;
    _volumeRampUp = alarm?.volumeRampUp ?? false;

    final behavior = alarm?.videoBehavior ?? VideoBehavior.videoAudioOnly;
    _videoSoundOn = behavior != VideoBehavior.muteVideoPlayTone;
    _backupToneOn =
        behavior == VideoBehavior.muteVideoPlayTone ||
        behavior == VideoBehavior.loopVideo ||
        behavior == VideoBehavior.playOnceThenTone;
    if (_toneUri == 'silent') _backupToneOn = false;
    _soundMode = (_toneUri != null && _toneUri!.isNotEmpty && _toneUri != 'silent')
        ? 'custom'
        : 'default';
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = widget.alarm;
    final alarm = _buildAlarm(
      id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      enabled: true,
    );
    await _service.saveAlarm(alarm);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  Future<void> _preview() async {
    final now = DateTime.now();
    final alarm = _buildAlarm(
      id: 'preview-${now.microsecondsSinceEpoch}',
      createdAt: now,
      updatedAt: now,
      enabled: false,
    );
    await _service.previewAlarm(alarm);
  }

  AlarmModel _buildAlarm({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    required bool enabled,
  }) {
    return AlarmModel(
      id: id,
      timeHour: _hour,
      timeMinute: _minute,
      enabled: enabled,
      repeatDays: _repeatDays,
      label: _labelController.text.trim(),
      snoozeMinutes: widget.alarm?.snoozeMinutes ?? 5,
      toneUri: _resolveToneUri(),
      videoUri: _videoUri,
      videoDurationSeconds: _videoDurationSeconds,
      videoBehavior: _resolveVideoBehavior(),
      vibrate: _vibrate,
      volumeRampUp: _volumeRampUp,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  VideoBehavior _resolveVideoBehavior() {
    if (_videoSoundOn && _backupToneOn) return VideoBehavior.loopVideo;
    if (_videoSoundOn && !_backupToneOn) return VideoBehavior.videoAudioOnly;
    return VideoBehavior.muteVideoPlayTone;
  }

  String? _resolveToneUri() {
    if (!_backupToneOn) return 'silent';
    return _soundMode == 'custom' ? _toneUri : null;
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = _videoUri != null && _videoUri!.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          widget.alarm == null ? 'New Video Alarm' : 'Edit Video Alarm',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: const Color(0xFF4D9BFF),
        foregroundColor: Colors.white,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.bolt_rounded),
        label: const Text(
          'Set Vibe',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4D9BFF),
            surface: Color(0xFF171717),
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            TimePickerCard(
              hour: _hour,
              minute: _minute,
              onTimeChanged: (time) {
                setState(() {
                  _hour = time.hour;
                  _minute = time.minute;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              maxLength: _labelMaxLength,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'e.g. Gym, Wake up',
                labelStyle: TextStyle(color: Colors.white60),
                hintStyle: TextStyle(color: Colors.white24),
                counterStyle: TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 16),
            RepeatDaySelector(
              selectedDays: _repeatDays,
              onChanged: (days) => setState(() => _repeatDays = days),
            ),
            const SizedBox(height: 28),
            VideoPickerCard(
              videoUri: _videoUri,
              durationSeconds: _videoDurationSeconds,
              onVideoChanged: (uri, duration) {
                setState(() {
                  _videoUri = uri;
                  _videoDurationSeconds = duration;
                });
              },
            ),
            const SizedBox(height: 18),
            _SimplePanel(
              child: Column(
                children: [
                  if (hasVideo) ...[
                    _AudioToggleRow(
                      label: 'Video Sound',
                      value: _videoSoundOn,
                      onChanged: (value) =>
                          setState(() => _videoSoundOn = value),
                    ),
                    const Divider(color: Color(0xFF272727), height: 1),
                  ],
                  _AudioToggleRow(
                    label: 'Backup Alarm Tone',
                    value: _backupToneOn,
                    onChanged: (value) =>
                        setState(() => _backupToneOn = value),
                  ),
                  if (_backupToneOn) ...[
                    const SizedBox(height: 14),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'default',
                          icon: Icon(Icons.notifications_none_rounded),
                          label: Text('Default'),
                        ),
                        ButtonSegment(
                          value: 'custom',
                          icon: Icon(Icons.music_note_rounded),
                          label: Text('Music'),
                        ),
                      ],
                      selected: {_soundMode},
                      onSelectionChanged: (selected) =>
                          setState(() => _soundMode = selected.first),
                    ),
                    if (_soundMode == 'custom') ...[
                      const SizedBox(height: 12),
                      LocalAudioPickerCard(
                        audioUri: _toneUri,
                        onAudioChanged: (uri) =>
                            setState(() => _toneUri = uri),
                      ),
                    ],
                  ],
                  const Divider(color: Color(0xFF272727), height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Vibration',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _vibrate,
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF4D9BFF),
                    onChanged: (value) => setState(() => _vibrate = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Volume ramp-up',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _volumeRampUp,
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF4D9BFF),
                    onChanged: (value) =>
                        setState(() => _volumeRampUp = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _preview,
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Preview Alarm'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF555555)),
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioToggleRow extends StatelessWidget {
  const _AudioToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: const Color(0xFF4D9BFF),
      onChanged: onChanged,
    );
  }
}

class _SimplePanel extends StatelessWidget {
  const _SimplePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF272727)),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
