import 'package:flutter/material.dart';

import '../models/interval_session_models.dart';
import '../models/timetable_models.dart';
import '../services/native_alarm_bridge.dart';
import '../services/storage_service.dart';
import '../services/timetable_service.dart';
import '../utils/formatters.dart';
import 'interval_session_content.dart' show IntervalSessionRunScreen;
import 'video_picker_card.dart';

const _accent = Color(0xFF4D9BFF);
const _surface = Color(0xFF161616);
const _border = Color(0xFF2A2A2A);
const _mutedText = Color(0xFFBDBDBD);

/// The Timetable tab: a single daily routine rendered as a vertical list of
/// time blocks. Blocks are separated by spacing rather than heavy borders
/// (Gestalt proximity); only the currently active block gets an accent edge
/// (Von Restorff — one emphasized element). Recovery actions ("I woke up
/// now", behind-schedule multi-select) appear only when relevant.
class TimetableContent extends StatefulWidget {
  const TimetableContent({super.key});

  @override
  State<TimetableContent> createState() => _TimetableContentState();
}

class _TimetableContentState extends State<TimetableContent> {
  final _service = TimetableService();

  List<TimetableTask> _tasks = const [];
  TimetableDayOverride _override = TimetableDayOverride.emptyForToday();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _service.loadTasks();
    final override = await _service.loadOverride();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _override = override;
      _loading = false;
    });
  }

  bool _isDone(TimetableTask task) => _override.doneTaskIds.contains(task.id);
  bool _isSkipped(TimetableTask task) =>
      _override.skippedTaskIds.contains(task.id);

  DateTime _effectiveStart(TimetableTask task) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
      task.startHour,
      task.startMinute,
    );
    if (_isDone(task) || _isSkipped(task)) return start;
    return start.add(Duration(minutes: _override.shiftMinutes));
  }

  bool _isActive(TimetableTask task) {
    if (_isDone(task) || _isSkipped(task)) return false;
    final now = DateTime.now();
    final start = _effectiveStart(task);
    return !now.isBefore(start) &&
        now.isBefore(start.add(Duration(minutes: task.durationMinutes)));
  }

  List<TimetableTask> get _remaining => _tasks
      .where(
        (task) =>
            !_isDone(task) &&
            !_isSkipped(task) &&
            DateTime.now().isBefore(
              _effectiveStart(
                task,
              ).add(Duration(minutes: task.durationMinutes)),
            ),
      )
      .toList();

  bool get _showWokeUpNow {
    if (_tasks.isEmpty || _override.shiftMinutes != 0) return false;
    if (_remaining.isEmpty) return false;
    final first = _tasks.first;
    final now = DateTime.now();
    final plannedStart = DateTime(
      now.year,
      now.month,
      now.day,
      first.startHour,
      first.startMinute,
    );
    // Only offer the shift while the day is genuinely off to a late start:
    // past the first task's planned start, but before it was completed.
    return now.isAfter(plannedStart) && !_isDone(first) && !_isSkipped(first);
  }

  bool get _showBehindSchedule {
    final now = DateTime.now();
    return _remaining.length >= 2 &&
        _remaining.any((task) => now.isAfter(_effectiveStart(task)));
  }

  Future<void> _wokeUpNow() async {
    final updated = await _service.shiftDay(_tasks);
    if (!mounted) return;
    setState(() => _override = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Today shifted by ${_formatShift(updated.shiftMinutes)} — back to '
          'normal tomorrow.',
        ),
      ),
    );
  }

  String _formatShift(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  Future<void> _openBehindSchedule() async {
    final remaining = _remaining;
    final kept = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _BehindScheduleSheet(remaining: remaining),
    );
    if (kept == null) return;
    final updated = await _service.skipExcept(remaining, kept);
    if (!mounted) return;
    setState(() => _override = updated);
  }

  Future<void> _markDone(TimetableTask task) async {
    await _service.markDone(task);
    await _load();
  }

  Future<void> _openEditor([TimetableTask? task]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _TaskEditorScreen(task: task)),
    );
    if (changed == true) await _load();
  }

  Future<void> _launchSession(TimetableTask task) async {
    final presets = await StorageService().loadSessionPresets();
    final preset = presets
        .where((p) => p.id == task.sessionPresetId)
        .firstOrNull;
    if (!mounted) return;
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This session preset no longer exists — edit the task.'),
        ),
      );
      return;
    }
    await const NativeAlarmBridge().startIntervalSession(
      encodePhasesJson(preset.buildPhases()),
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const IntervalSessionRunScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openHistory() async {
    final history = await _service.loadHistory();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HistoryScreen(records: history),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 132),
      children: [
        Row(
          children: [
            if (_override.shiftMinutes > 0)
              Expanded(
                child: Text(
                  'Shifted +${_formatShift(_override.shiftMinutes)} today',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              const Spacer(),
            IconButton(
              tooltip: 'History',
              onPressed: _openHistory,
              icon: const Icon(
                Icons.history_rounded,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        if (_showWokeUpNow) ...[
          FilledButton.icon(
            onPressed: _wokeUpNow,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(58),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.wb_sunny_rounded),
            label: const Text(
              'I woke up now — shift my day',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_showBehindSchedule) ...[
          TextButton.icon(
            onPressed: _openBehindSchedule,
            style: TextButton.styleFrom(foregroundColor: _mutedText),
            icon: const Icon(Icons.checklist_rounded, size: 18),
            label: const Text('Behind schedule? Choose what to keep'),
          ),
          const SizedBox(height: 4),
        ],
        if (_tasks.isEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            decoration: BoxDecoration(
              color: const Color(0xFF202020),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: const Column(
              children: [
                Icon(Icons.view_agenda_rounded, color: _accent, size: 44),
                SizedBox(height: 14),
                Text(
                  'No routine yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Build your day as time blocks.\nAttach a video alarm to the '
                  'ones that matter.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 15),
                ),
              ],
            ),
          )
        else
          for (final task in _tasks) ...[
            _TaskBlock(
              task: task,
              startTime: _effectiveStart(task),
              done: _isDone(task),
              skipped: _isSkipped(task),
              active: _isActive(task),
              onTap: () => _openEditor(task),
              onDone: () => _markDone(task),
              onLaunchSession: task.isSessionTask
                  ? () => _launchSession(task)
                  : null,
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _openEditor(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: Color(0xFF333333)),
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Add task',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _TaskBlock extends StatelessWidget {
  const _TaskBlock({
    required this.task,
    required this.startTime,
    required this.done,
    required this.skipped,
    required this.active,
    required this.onTap,
    required this.onDone,
    this.onLaunchSession,
  });

  final TimetableTask task;
  final DateTime startTime;
  final bool done;
  final bool skipped;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDone;
  final VoidCallback? onLaunchSession;

  @override
  Widget build(BuildContext context) {
    final end = startTime.add(Duration(minutes: task.durationMinutes));
    final muted = done || skipped;
    return Opacity(
      opacity: muted ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF10233B) : _surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? _accent : _border,
              width: active ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatAlarmTime(startTime.hour, startTime.minute)}'
                      ' – ${formatAlarmTime(end.hour, end.minute)}',
                      style: TextStyle(
                        color: active ? _accent : Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (task.alarmEnabled) ...[
                          Icon(
                            task.hasVideo
                                ? Icons.smart_display_rounded
                                : Icons.alarm_rounded,
                            color: Colors.white38,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (task.isSessionTask) ...[
                          const Icon(
                            Icons.fitness_center_rounded,
                            color: Colors.white38,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (skipped)
                          const Text(
                            'Skipped today',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onLaunchSession != null && !muted)
                IconButton(
                  tooltip: 'Start session',
                  onPressed: onLaunchSession,
                  icon: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: _accent,
                    size: 34,
                  ),
                ),
              IconButton(
                tooltip: done ? 'Done' : 'Mark done',
                onPressed: muted ? null : onDone,
                icon: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: done ? _accent : Colors.white38,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select of remaining tasks to KEEP; the rest are skipped for today.
/// Framed as choosing what to do (a decision) rather than what to abandon.
class _BehindScheduleSheet extends StatefulWidget {
  const _BehindScheduleSheet({required this.remaining});

  final List<TimetableTask> remaining;

  @override
  State<_BehindScheduleSheet> createState() => _BehindScheduleSheetState();
}

class _BehindScheduleSheetState extends State<_BehindScheduleSheet> {
  late final Set<String> _kept = widget.remaining.map((t) => t.id).toSet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'What do you still want to do today?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Unchecked tasks are skipped for today only.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final task in widget.remaining)
                  CheckboxListTile(
                    value: _kept.contains(task.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _kept.add(task.id);
                      } else {
                        _kept.remove(task.id);
                      }
                    }),
                    activeColor: _accent,
                    checkColor: Colors.white,
                    title: Text(
                      task.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      formatAlarmTime(task.startHour, task.startMinute),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _kept.length == widget.remaining.length
                ? () => Navigator.of(context).pop()
                : () => Navigator.of(context).pop(_kept),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _kept.length == widget.remaining.length
                  ? 'Keep everything'
                  : 'Keep ${_kept.length} of ${widget.remaining.length}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskEditorScreen extends StatefulWidget {
  const _TaskEditorScreen({this.task});

  final TimetableTask? task;

  @override
  State<_TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<_TaskEditorScreen> {
  final _service = TimetableService();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.task?.name ?? '',
  );

  late int _startHour = widget.task?.startHour ?? 8;
  late int _startMinute = widget.task?.startMinute ?? 0;
  late int _durationMinutes = widget.task?.durationMinutes ?? 30;
  late bool _alarmEnabled = widget.task?.alarmEnabled ?? false;
  late String? _videoUri = widget.task?.videoUri;
  late int? _videoDurationSeconds = widget.task?.videoDurationSeconds;
  late String? _sessionPresetId = widget.task?.sessionPresetId;
  List<SessionPreset> _presets = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    StorageService().loadSessionPresets().then((presets) {
      if (mounted) setState(() => _presets = presets);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _startHour, minute: _startMinute),
    );
    if (picked == null) return;
    setState(() {
      _startHour = picked.hour;
      _startMinute = picked.minute;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give the task a name.')));
      return;
    }
    setState(() => _saving = true);
    final task = TimetableTask(
      id: widget.task?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      startHour: _startHour,
      startMinute: _startMinute,
      durationMinutes: _durationMinutes,
      alarmEnabled: _alarmEnabled,
      videoUri: _alarmEnabled ? _videoUri : null,
      videoDurationSeconds: _alarmEnabled ? _videoDurationSeconds : null,
      sessionPresetId: _sessionPresetId,
    );
    await _service.saveTask(task);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: Text(
          'Delete "${widget.task!.name}"?',
          style: const TextStyle(color: Colors.white, fontSize: 19),
        ),
        content: const Text(
          'Its alarm will be cancelled too.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteTask(widget.task!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.task == null ? 'New task' : 'Edit task'),
        actions: [
          if (widget.task != null)
            IconButton(
              tooltip: 'Delete task',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 120),
        children: [
          TextField(
            controller: _nameController,
            maxLength: 20,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Task name',
              labelStyle: TextStyle(color: Colors.white54),
              counterStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF333333)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _EditorRow(
            label: 'Starts at',
            child: TextButton(
              onPressed: _pickTime,
              child: Text(
                formatAlarmTime(_startHour, _startMinute),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          _EditorRow(
            label: 'Duration',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _durationMinutes > 5
                      ? () => setState(
                          () => _durationMinutes =
                              (_durationMinutes - 5).clamp(5, 480),
                        )
                      : null,
                  icon: const Icon(
                    Icons.remove_rounded,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(
                  width: 78,
                  child: Text(
                    _durationMinutes >= 60
                        ? '${_durationMinutes ~/ 60}h '
                              '${_durationMinutes % 60 > 0 ? '${_durationMinutes % 60}m' : ''}'
                        : '$_durationMinutes min',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _durationMinutes < 480
                      ? () => setState(
                          () => _durationMinutes =
                              (_durationMinutes + 5).clamp(5, 480),
                        )
                      : null,
                  icon: const Icon(Icons.add_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Video alarm at start',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Full-screen motivational video, even when locked',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            value: _alarmEnabled,
            onChanged: (value) => setState(() => _alarmEnabled = value),
            activeThumbColor: Colors.white,
            activeTrackColor: _accent,
          ),
          if (_alarmEnabled) ...[
            const SizedBox(height: 8),
            VideoPickerCard(
              videoUri: _videoUri,
              durationSeconds: _videoDurationSeconds,
              onVideoChanged: (uri, duration) => setState(() {
                _videoUri = uri;
                _videoDurationSeconds = duration;
              }),
            ),
          ],
          const SizedBox(height: 16),
          if (_presets.isNotEmpty) ...[
            const Text(
              'Interval session',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Link a saved session — start it right from this task.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _sessionPresetId == null,
                  onSelected: (_) =>
                      setState(() => _sessionPresetId = null),
                  selectedColor: _accent,
                  backgroundColor: const Color(0xFF242424),
                  labelStyle: TextStyle(
                    color: _sessionPresetId == null
                        ? Colors.white
                        : _mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final preset in _presets)
                  ChoiceChip(
                    label: Text(preset.name),
                    selected: _sessionPresetId == preset.id,
                    onSelected: (_) =>
                        setState(() => _sessionPresetId = preset.id),
                    selectedColor: _accent,
                    backgroundColor: const Color(0xFF242424),
                    labelStyle: TextStyle(
                      color: _sessionPresetId == preset.id
                          ? Colors.white
                          : _mutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(58),
              shape: const StadiumBorder(),
            ),
            child: Text(
              widget.task == null ? 'Add to Routine' : 'Save Task',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Last-30-days completion history, grouped by day. Deliberately plain —
/// a record, not a scoreboard (no streaks or badges by design).
class _HistoryScreen extends StatelessWidget {
  const _HistoryScreen({required this.records});

  final List<TaskRecord> records;

  @override
  Widget build(BuildContext context) {
    final byDate = <String, List<TaskRecord>>{};
    for (final record in records) {
      byDate.putIfAbsent(record.date, () => []).add(record);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('History'),
      ),
      body: dates.isEmpty
          ? const Center(
              child: Text(
                'Nothing recorded yet.\nCompleted and skipped tasks show up '
                'here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 15),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
              children: [
                for (final date in dates) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 8),
                    child: Text(
                      date,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (final record in byDate[date]!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            switch (record.status) {
                              'done' => Icons.check_circle_rounded,
                              'skipped' => Icons.remove_circle_outline_rounded,
                              _ => Icons.schedule_rounded,
                            },
                            color: switch (record.status) {
                              'done' => _accent,
                              'skipped' => Colors.white38,
                              _ => Colors.white54,
                            },
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              record.taskName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            record.status,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
