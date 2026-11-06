import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../services/native_alarm_bridge.dart';
import '../utils/formatters.dart';
import '../widgets/cinematic_alarm_feed.dart';
import '../widgets/stopwatch_content.dart';
import '../widgets/timer_content.dart';
import '../widgets/timetable_content.dart';
import 'edit_alarm_screen.dart';
import 'permission_setup_screen.dart';
import 'settings_screen.dart';

class AlarmListScreen extends StatefulWidget {
  const AlarmListScreen({super.key});

  static const routeName = '/alarms';

  @override
  State<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen>
    with WidgetsBindingObserver {
  final _service = AlarmService();
  final _alarmListKey = GlobalKey();
  final _addAlarmKey = GlobalKey();
  final _menuKey = GlobalKey();

  // Permissions whose loss silently breaks the ring experience (the
  // full-screen one in particular gets auto-revoked by some OEM "cleanup"
  // tools, notably MIUI). Re-checked on every app resume so a revocation
  // surfaces as a banner the next time the user opens the app, instead of
  // being discovered when an alarm fails to take over the screen.
  static const _criticalPermissionKeys = {
    'exactAlarm',
    'notification',
    'fullScreen',
  };

  List<AlarmModel> _alarms = const [];
  Set<String> _brokenVideoIds = const {};
  bool _loading = true;
  int _selectedTab = 0;
  int _missingCriticalPermissions = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkCriticalPermissions();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkCriticalPermissions();
  }

  Future<void> _checkCriticalPermissions() async {
    try {
      final statuses = await const NativeAlarmBridge().getPermissionStatuses();
      final missing = statuses
          .where(
            (status) =>
                _criticalPermissionKeys.contains(status.key) &&
                !status.granted,
          )
          .length;
      if (mounted) setState(() => _missingCriticalPermissions = missing);
    } catch (_) {
      // Bridge unavailable (e.g. hot restart edge) — keep the last state.
    }
  }

  Future<void> _openPermissionSetup() async {
    await Navigator.of(context).pushNamed(PermissionSetupScreen.routeName);
    await _checkCriticalPermissions();
  }

  Future<void> _load() async {
    final alarms = await _service.loadAlarms();
    if (!mounted) return;
    setState(() {
      _alarms = alarms;
      _loading = false;
    });
    _checkVideos(alarms);
  }

  /// Flags alarms whose video is no longer readable (URI grants don't
  /// survive reinstall/restore) so their card can say so instead of
  /// showing a silent black thumbnail. Runs after render; cheap metadata
  /// probe per video.
  Future<void> _checkVideos(List<AlarmModel> alarms) async {
    const bridge = NativeAlarmBridge();
    final broken = <String>{};
    for (final alarm in alarms.where((alarm) => alarm.hasVideo)) {
      try {
        if (!(await bridge.validateVideo(alarm.videoUri!)).valid) {
          broken.add(alarm.id);
        }
      } catch (_) {
        broken.add(alarm.id);
      }
    }
    if (mounted && !setEquals(broken, _brokenVideoIds)) {
      setState(() => _brokenVideoIds = broken);
    }
  }

  DateTime? get _nextAlarmTime {
    final enabled = _alarms.where((alarm) => alarm.enabled);
    if (enabled.isEmpty) return null;
    return enabled.map(_nextTriggerFor).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime _nextTriggerFor(AlarmModel alarm) {
    final now = DateTime.now();
    if (alarm.repeatDays.isEmpty) {
      var candidate = DateTime(
        now.year,
        now.month,
        now.day,
        alarm.timeHour,
        alarm.timeMinute,
      );
      if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 1));
      return candidate;
    }
    DateTime? next;
    for (final day in alarm.repeatDays) {
      final daysAhead = (day - now.weekday + 7) % 7;
      var candidate = DateTime(
        now.year,
        now.month,
        now.day,
        alarm.timeHour,
        alarm.timeMinute,
      ).add(Duration(days: daysAhead));
      if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 7));
      if (next == null || candidate.isBefore(next)) next = candidate;
    }
    return next ?? now;
  }

  String _formatRemaining(Duration duration) {
    final totalMinutes = (duration.inSeconds / 60).ceil().clamp(1, 7 * 24 * 60);
    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final minutes = totalMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  Future<void> _openEditor([AlarmModel? alarm]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EditAlarmScreen(alarm: alarm)),
    );
    await _load();
  }

  Future<void> _toggle(AlarmModel alarm, bool enabled) async {
    await _service.setEnabled(alarm, enabled);
    await _load();
  }

  Future<void> _delete(AlarmModel alarm) async {
    await _service.deleteAlarm(alarm.id);
    await _load();
  }

  Future<bool> _confirmAndDelete(AlarmModel alarm) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text(
          'Delete video alarm?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          alarm.label.isEmpty ? 'Video Alarm' : alarm.label,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) await _delete(alarm);
    return false;
  }

  Future<void> _handleMenuAction(_AlarmMenuAction action) async {
    switch (action) {
      case _AlarmMenuAction.permissions:
        await Navigator.of(context).pushNamed(PermissionSetupScreen.routeName);
      case _AlarmMenuAction.settings:
        await Navigator.of(context).pushNamed(SettingsScreen.routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AlarmHeader(
              title: _titleForTab(_selectedTab),
              menuKey: _menuKey,
              onSelected: _handleMenuAction,
            ),
            if (_missingCriticalPermissions > 0)
              _PermissionWarningBanner(
                count: _missingCriticalPermissions,
                onTap: _openPermissionSetup,
              ),
            if (_selectedTab == 0 && _nextAlarmTime != null)
              _NextAlarmBanner(
                remaining: _formatRemaining(_nextAlarmTime!.difference(DateTime.now())),
                time: formatAlarmTime(_nextAlarmTime!.hour, _nextAlarmTime!.minute),
              ),
            Expanded(child: _buildSelectedContent()),
          ],
        ),
      ),
      bottomNavigationBar: _ClockBottomNavigationBar(
        selectedIndex: _selectedTab,
        onSelected: (index) => setState(() => _selectedTab = index),
      ),
      floatingActionButton: _selectedTab == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: SizedBox(
                key: _addAlarmKey,
                width: 76,
                height: 76,
                child: FloatingActionButton(
                  heroTag: 'add-alarm',
                  tooltip: 'Add video alarm',
                  elevation: 0,
                  highlightElevation: 0,
                  backgroundColor: const Color(0xFF242426),
                  foregroundColor: const Color(0xFF2F80ED),
                  shape: const CircleBorder(),
                  onPressed: () => _openEditor(),
                  child: const Icon(Icons.add_rounded, size: 50),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildSelectedContent() {
    switch (_selectedTab) {
      case 1:
        return const StopwatchContent();
      case 2:
        return const TimerContent();
      case 3:
        return const TimetableContent();
      default:
        return KeyedSubtree(
          key: _alarmListKey,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2F80ED)),
                )
              : _alarms.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: _EmptyAlarmHint(),
                )
              : CinematicAlarmFeed(
                  alarms: _alarms,
                  brokenVideoIds: _brokenVideoIds,
                  onOpenEditor: _openEditor,
                  onToggle: _toggle,
                  onDelete: _confirmAndDelete,
                ),
        );
    }
  }

  String _titleForTab(int index) {
    return switch (index) {
      1 => 'Stopwatch',
      2 => 'Timer',
      3 => 'Timetable',
      _ => 'Video Alarm',
    };
  }
}

enum _AlarmMenuAction { permissions, settings }

class _AlarmHeader extends StatelessWidget {
  const _AlarmHeader({
    required this.title,
    required this.menuKey,
    required this.onSelected,
  });

  final String title;
  final GlobalKey menuKey;
  final ValueChanged<_AlarmMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 38, 18, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: 0,
              ),
            ),
          ),
          PopupMenuButton<_AlarmMenuAction>(
            key: menuKey,
            tooltip: 'More options',
            color: const Color(0xFF202020),
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Colors.white70,
              size: 30,
            ),
            onSelected: onSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _AlarmMenuAction.permissions,
                child: _MenuRow(
                  icon: Icons.verified_user_rounded,
                  label: 'Permissions',
                ),
              ),
              PopupMenuItem(
                value: _AlarmMenuAction.settings,
                child: _MenuRow(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown whenever a ring-critical permission (exact alarm, notifications,
/// full-screen intent) has been revoked — some OEM cleanup tools flip the
/// full-screen permission off on their own, and without it the alarm
/// degrades to a silent-looking notification.
class _PermissionWarningBanner extends StatelessWidget {
  const _PermissionWarningBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Material(
        color: const Color(0xFF3A1D1D),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF7F1D1D)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFF87171),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 1
                        ? 'A permission alarms rely on was turned off — tap to fix'
                        : '$count permissions alarms rely on are off — tap to fix',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextAlarmBanner extends StatelessWidget {
  const _NextAlarmBanner({required this.remaining, required this.time});

  final String remaining;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 18, 0),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFF4D9BFF), size: 16),
          const SizedBox(width: 6),
          Text(
            'Next alarm in $remaining · $time',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

class _EmptyAlarmHint extends StatelessWidget {
  const _EmptyAlarmHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.video_camera_back_rounded,
            color: Color(0xFF4D9BFF),
            size: 44,
          ),
          SizedBox(height: 14),
          Text(
            'No video alarms yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Tap + to add one',
            style: TextStyle(
              color: Color(0xFFAAAAAA),
              fontSize: 15,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockBottomNavigationBar extends StatelessWidget {
  const _ClockBottomNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding + 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF272727),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: const Color(0xFF707070), width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 22,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              _ClockNavItem(
                icon: Icons.alarm_rounded,
                label: 'Video Alarm',
                selected: selectedIndex == 0,
                onTap: () => onSelected(0),
              ),
              _ClockNavItem(
                icon: Icons.timer_rounded,
                label: 'Stopwatch',
                selected: selectedIndex == 1,
                onTap: () => onSelected(1),
              ),
              _ClockNavItem(
                icon: Icons.hourglass_bottom_rounded,
                label: 'Timer',
                selected: selectedIndex == 2,
                onTap: () => onSelected(2),
              ),
              _ClockNavItem(
                icon: Icons.view_agenda_rounded,
                label: 'Timetable',
                selected: selectedIndex == 3,
                onTap: () => onSelected(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockNavItem extends StatelessWidget {
  const _ClockNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF8A8A8A);
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkResponse(
          onTap: onTap,
          radius: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 31),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: selected ? 48 : 0,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
