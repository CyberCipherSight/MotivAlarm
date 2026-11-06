import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
import '../services/backup_service.dart';
import '../services/native_alarm_bridge.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _storage = StorageService();
  final _backup = BackupService();
  final _bridge = const NativeAlarmBridge();
  int _defaultSnooze = 5;
  bool _vibration = true;
  int _ringTimeout = 5;
  DateTime? _lastExport;
  bool _backupBusy = false;
  bool _overlayGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh the overlay-permission state when returning from Settings.
    if (state == AppLifecycleState.resumed) _refreshOverlay();
  }

  Future<void> _refreshOverlay() async {
    final granted = await _bridge.canDrawOverlays();
    if (mounted) setState(() => _overlayGranted = granted);
  }

  Future<void> _load() async {
    final settings = await _storage.loadSettings();
    final lastExport = await _backup.lastExportDate();
    final ringTimeout = await _bridge.getRingTimeoutMinutes();
    await _refreshOverlay();
    if (!mounted) return;
    setState(() {
      _defaultSnooze = AlarmModel.clampSnoozeMinutes(
        settings['defaultSnooze'] as int? ?? 5,
      );
      _vibration = settings['vibration'] as bool? ?? true;
      _ringTimeout = ringTimeout;
      _lastExport = lastExport;
    });
  }

  Future<void> _export() async {
    setState(() => _backupBusy = true);
    try {
      final saved = await _backup.exportBackup();
      if (!mounted) return;
      if (saved) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Backup saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the backup.')),
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _import() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text(
          'Import backup?',
          style: TextStyle(color: Colors.white, fontSize: 19),
        ),
        content: const Text(
          'This replaces your current alarms, timetable, session presets and '
          'history with the backup’s contents.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4D9BFF),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _backupBusy = true);
    try {
      final result = await _backup.importBackup();
      if (!mounted || result == null) return;
      await _showImportResult(result);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file.')),
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _showImportResult(ImportResult result) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text(
          'Backup restored',
          style: TextStyle(color: Colors.white, fontSize: 19),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result.alarmCount} alarms, ${result.taskCount} timetable '
              'tasks and ${result.presetCount} session presets are back, and '
              'their alarms are re-scheduled.',
              style: const TextStyle(color: Colors.white70),
            ),
            if (result.brokenVideoNames.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Videos need re-picking for: '
                '${result.brokenVideoNames.join(', ')}.\n\n'
                'Video access doesn’t survive reinstalling — open each '
                'one and choose its video again. Until then they ring with '
                'the backup tone.',
                style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4D9BFF),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await _storage.saveSettings({
      'defaultSnooze': AlarmModel.clampSnoozeMinutes(_defaultSnooze),
      'vibration': _vibration,
    });
    await _bridge.setRingTimeoutMinutes(_ringTimeout);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _openSupportLink(String url) async {
    try {
      await _bridge.openUrl(url);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SettingsPanel(
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _defaultSnooze,
                  dropdownColor: const Color(0xFF202020),
                  decoration: const InputDecoration(
                    labelText: 'Default snooze duration',
                    border: OutlineInputBorder(),
                  ),
                  items: const [1, 2, 3, 4, 5]
                      .map(
                        (minutes) => DropdownMenuItem(
                          value: minutes,
                          child: Text('$minutes minutes'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => _defaultSnooze = AlarmModel.clampSnoozeMinutes(
                      value ?? 5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _ringTimeout,
                  dropdownColor: const Color(0xFF202020),
                  decoration: const InputDecoration(
                    labelText: 'Pause alarm if unanswered after',
                    helperText:
                        'It rings again quietly when you unlock your phone',
                    helperStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 minute')),
                    DropdownMenuItem(value: 3, child: Text('3 minutes')),
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 10, child: Text('10 minutes')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes')),
                    DropdownMenuItem(value: 0, child: Text('Never pause')),
                  ],
                  onChanged: (value) =>
                      setState(() => _ringTimeout = value ?? 5),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Vibration',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: _vibration,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFF4D9BFF),
                  onChanged: (value) => setState(() => _vibration = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SettingsPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Backup',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _lastExport == null
                      ? 'Alarms also back up automatically with your '
                            'phone’s Google backup. For a file you '
                            'control, export one here.'
                      : 'Last export: '
                            '${_lastExport!.day}/${_lastExport!.month}/${_lastExport!.year} '
                            'at ${formatAlarmTime(_lastExport!.hour, _lastExport!.minute)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _backupBusy ? null : _export,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4D9BFF),
                          side: const BorderSide(color: Color(0xFF444444)),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('Export'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _backupBusy ? null : _import,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4D9BFF),
                          side: const BorderSide(color: Color(0xFF444444)),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Import'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SettingsPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Advanced reliability (optional)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Extra steps that help on Xiaomi/MIUI and other phones '
                  'that aggressively limit apps. Alarms work without them '
                  'on most devices.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _overlayGranted
                        ? Icons.check_circle_rounded
                        : Icons.layers_rounded,
                    color: _overlayGranted
                        ? const Color(0xFF4ADE80)
                        : Colors.white70,
                  ),
                  title: const Text(
                    'Display over other apps',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _overlayGranted
                        ? 'Allowed'
                        : 'Helps the alarm appear over anything on screen',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                  onTap: () => _bridge.openOverlaySettings(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save Settings'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4D9BFF),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enjoying the app? Your support is optional and appreciated.',
            textAlign: TextAlign.end,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _openSupportLink(
                    'https://github.com/CyberCipherSight/MotivAlarm',
                  ),
                  icon: const Icon(Icons.star_border_rounded, size: 16),
                  label: const Text('Star on GitHub'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                ),
                TextButton.icon(
                  onPressed: () => _openSupportLink(
                    'https://play.google.com/store/apps/details?id=com.cybersight.AlarmForAction',
                  ),
                  icon: const Icon(Icons.rate_review_outlined, size: 16),
                  label: const Text('Review on Google Play'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4D9BFF),
          surface: Color(0xFF202020),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.white60),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF444444)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4D9BFF)),
          ),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}
