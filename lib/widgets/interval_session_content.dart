import 'dart:async';

import 'package:flutter/material.dart';

import '../models/interval_session_models.dart';
import '../services/native_alarm_bridge.dart';
import '../services/storage_service.dart';
import 'timer_content.dart' show NumberColumn;

const _accent = Color(0xFF4D9BFF);
const _chipBg = Color(0xFF242424);
const _border = Color(0xFF3A3A3A);
const _mutedText = Color(0xFFBDBDBD);

/// Setup view for interval sessions: three basic inputs (sets, work, break),
/// per-phase fine-tuning behind an Advanced expander (progressive disclosure),
/// and saved presets. Starting hands the phase list to the native
/// IntervalSessionService and opens the full-screen running view.
class IntervalSessionContent extends StatefulWidget {
  const IntervalSessionContent({super.key});

  @override
  State<IntervalSessionContent> createState() => _IntervalSessionContentState();
}

class _IntervalSessionContentState extends State<IntervalSessionContent> {
  final _bridge = const NativeAlarmBridge();
  final _storage = StorageService();

  int _sets = 5;
  int _setSeconds = 45;
  int _breakSeconds = 15;
  List<int>? _customPhaseSeconds;
  List<SessionPreset> _presets = [];
  String? _selectedPresetId;
  bool _sessionActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final presets = await _storage.loadSessionPresets();
    final state = await _bridge.getIntervalSessionState();
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _sessionActive = state['active'] == true;
    });
  }

  SessionPreset get _currentConfig => SessionPreset(
    id: _selectedPresetId ?? '',
    name: '',
    sets: _sets,
    setSeconds: _setSeconds,
    breakSeconds: _breakSeconds,
    customPhaseSeconds: _customPhaseSeconds,
  );

  Future<void> _start() async {
    final phases = _currentConfig.buildPhases();
    await _bridge.startIntervalSession(encodePhasesJson(phases));
    if (!mounted) return;
    await _openRunScreen();
  }

  Future<void> _openRunScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const IntervalSessionRunScreen(),
        fullscreenDialog: true,
      ),
    );
    if (mounted) _load();
  }

  void _applyPreset(SessionPreset preset) {
    setState(() {
      _selectedPresetId = preset.id;
      _sets = preset.sets;
      _setSeconds = preset.setSeconds;
      _breakSeconds = preset.breakSeconds;
      _customPhaseSeconds = preset.customPhaseSeconds?.toList();
    });
  }

  // Any basic-input change invalidates per-phase overrides (they were built
  // for the old phase list) and detaches from the selected preset.
  void _updateBasic(VoidCallback update) {
    setState(() {
      update();
      _customPhaseSeconds = null;
      _selectedPresetId = null;
    });
  }

  Future<void> _savePreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text(
          'Save preset',
          style: TextStyle(color: Colors.white, fontSize: 19),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Gym, Study sprint',
            hintStyle: TextStyle(color: Colors.white38),
            counterStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final preset = SessionPreset(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      sets: _sets,
      setSeconds: _setSeconds,
      breakSeconds: _breakSeconds,
      customPhaseSeconds: _customPhaseSeconds?.toList(),
    );
    final updated = [..._presets, preset];
    await _storage.saveSessionPresets(updated);
    if (!mounted) return;
    setState(() {
      _presets = updated;
      _selectedPresetId = preset.id;
    });
  }

  Future<void> _deletePreset(SessionPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: Text(
          'Delete "${preset.name}"?',
          style: const TextStyle(color: Colors.white, fontSize: 19),
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
    final updated = _presets.where((p) => p.id != preset.id).toList();
    await _storage.saveSessionPresets(updated);
    if (!mounted) return;
    setState(() {
      _presets = updated;
      if (_selectedPresetId == preset.id) _selectedPresetId = null;
    });
  }

  Future<void> _editPhaseDuration(int index) async {
    final phases = _currentConfig.buildPhases();
    final result = await _pickDuration(context, phases[index].seconds);
    if (result == null) return;
    setState(() {
      _customPhaseSeconds ??= phases.map((p) => p.seconds).toList();
      _customPhaseSeconds![index] = result;
      _selectedPresetId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final phases = _currentConfig.buildPhases();
    final totalSeconds = phases.fold<int>(0, (sum, p) => sum + p.seconds);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 132),
      children: [
        if (_sessionActive) ...[
          FilledButton.tonalIcon(
            onPressed: _openRunScreen,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B3A5C),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
            ),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text(
              'Session in progress — open',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (_presets.isNotEmpty) ...[
          const Text(
            'Presets',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final preset in _presets)
                GestureDetector(
                  onLongPress: () => _deletePreset(preset),
                  child: ChoiceChip(
                    label: Text(preset.name),
                    selected: _selectedPresetId == preset.id,
                    onSelected: (_) => _applyPreset(preset),
                    selectedColor: _accent,
                    backgroundColor: _chipBg,
                    side: BorderSide(
                      color: _selectedPresetId == preset.id ? _accent : _border,
                    ),
                    labelStyle: TextStyle(
                      color: _selectedPresetId == preset.id
                          ? Colors.white
                          : _mutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 26),
        ],
        _StepperRow(
          label: 'Sets',
          valueText: '$_sets',
          onMinus: _sets > 1 ? () => _updateBasic(() => _sets -= 1) : null,
          onPlus: _sets < 30 ? () => _updateBasic(() => _sets += 1) : null,
        ),
        const SizedBox(height: 14),
        _StepperRow(
          label: 'Work',
          valueText: _formatSeconds(_setSeconds),
          onMinus: _setSeconds > 5
              ? () => _updateBasic(
                  () => _setSeconds = (_setSeconds - 5).clamp(5, 3595),
                )
              : null,
          onPlus: _setSeconds < 3595
              ? () => _updateBasic(
                  () => _setSeconds = (_setSeconds + 5).clamp(5, 3595),
                )
              : null,
          onTapValue: () async {
            final result = await _pickDuration(context, _setSeconds);
            if (result != null) _updateBasic(() => _setSeconds = result);
          },
        ),
        const SizedBox(height: 14),
        _StepperRow(
          label: 'Break',
          valueText: _formatSeconds(_breakSeconds),
          onMinus: _breakSeconds > 5
              ? () => _updateBasic(
                  () => _breakSeconds = (_breakSeconds - 5).clamp(5, 3595),
                )
              : null,
          onPlus: _breakSeconds < 3595
              ? () => _updateBasic(
                  () => _breakSeconds = (_breakSeconds + 5).clamp(5, 3595),
                )
              : null,
          onTapValue: () async {
            final result = await _pickDuration(context, _breakSeconds);
            if (result != null) _updateBasic(() => _breakSeconds = result);
          },
        ),
        const SizedBox(height: 10),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Advanced — fine-tune each set & break',
              style: TextStyle(
                color: _mutedText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            iconColor: _mutedText,
            collapsedIconColor: _mutedText,
            children: [
              for (var i = 0; i < phases.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    phases[i].label,
                    style: TextStyle(
                      color: phases[i].isBreak ? _mutedText : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: TextButton.icon(
                    onPressed: () => _editPhaseDuration(i),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    style: TextButton.styleFrom(foregroundColor: _accent),
                    label: Text(
                      _formatSeconds(phases[i].seconds),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              if (_customPhaseSeconds != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _customPhaseSeconds = null),
                    child: const Text('Reset to basic durations'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Total: ${_formatSeconds(totalSeconds)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _sessionActive ? null : _start,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF151515),
            minimumSize: const Size.fromHeight(64),
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 32),
          label: const Text(
            'Start Session',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _savePreset,
          style: TextButton.styleFrom(foregroundColor: _mutedText),
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: const Text('Save as preset'),
        ),
      ],
    );
  }
}

String _formatSeconds(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Minutes/seconds picker sheet, returning total seconds.
Future<int?> _pickDuration(BuildContext context, int initialSeconds) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: const Color(0xFF171717),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _DurationSheet(initialSeconds: initialSeconds),
  );
}

class _DurationSheet extends StatefulWidget {
  const _DurationSheet({required this.initialSeconds});

  final int initialSeconds;

  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  late int _minutes = (widget.initialSeconds ~/ 60).clamp(0, 59);
  late int _seconds = widget.initialSeconds % 60;

  @override
  Widget build(BuildContext context) {
    final total = _minutes * 60 + _seconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Duration',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              NumberColumn(
                label: 'min',
                value: _minutes,
                max: 59,
                onChanged: (value) => setState(() => _minutes = value),
              ),
              NumberColumn(
                label: 'sec',
                value: _seconds,
                max: 59,
                onChanged: (value) => setState(() => _seconds = value),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: total == 0
                ? null
                : () => Navigator.of(context).pop(total),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Set Duration',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
    this.onTapValue,
  });

  final String label;
  final String valueText;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onTapValue;

  @override
  Widget build(BuildContext context) {
    return Row(
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
        IconButton.filled(
          onPressed: onMinus,
          style: IconButton.styleFrom(
            backgroundColor: _chipBg,
            disabledBackgroundColor: const Color(0xFF151515),
            foregroundColor: Colors.white,
            fixedSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.remove_rounded),
          tooltip: 'Decrease $label',
        ),
        GestureDetector(
          onTap: onTapValue,
          child: Container(
            width: 86,
            height: 48,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _chipBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Semantics(
              label: '$label $valueText',
              button: onTapValue != null,
              child: Text(
                valueText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        IconButton.filled(
          onPressed: onPlus,
          style: IconButton.styleFrom(
            backgroundColor: _chipBg,
            disabledBackgroundColor: const Color(0xFF151515),
            foregroundColor: Colors.white,
            fixedSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Increase $label',
        ),
      ],
    );
  }
}

/// Full-screen running view. Pure mirror of the native service's state:
/// a local 1 Hz ticker keeps the display moving, but the service is
/// authoritative — the screen re-syncs on lifecycle resume, periodically,
/// and at every local phase boundary. Glanceable from across a room:
/// huge phase label + countdown, work = accent blue, break = muted grey.
class IntervalSessionRunScreen extends StatefulWidget {
  const IntervalSessionRunScreen({super.key});

  @override
  State<IntervalSessionRunScreen> createState() =>
      _IntervalSessionRunScreenState();
}

class _IntervalSessionRunScreenState extends State<IntervalSessionRunScreen>
    with WidgetsBindingObserver {
  final _bridge = const NativeAlarmBridge();

  Timer? _ticker;
  bool _loaded = false;
  bool _running = false;
  bool _finished = false;
  int _phaseIndex = 0;
  int _phaseCount = 1;
  int _remaining = 0;
  bool _isBreak = false;
  String _phaseLabel = '';
  int _ticksSinceSync = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _tick() {
    if (!_running || _finished) return;
    _ticksSinceSync += 1;
    if (_remaining <= 1 || _ticksSinceSync >= 5) {
      _sync();
      return;
    }
    setState(() => _remaining -= 1);
  }

  Future<void> _sync() async {
    _ticksSinceSync = 0;
    final state = await _bridge.getIntervalSessionState();
    if (!mounted) return;
    final active = state['active'] == true;
    final finished = state['finished'] == true;
    if (!active && !finished && _loaded) {
      // Ended elsewhere (notification button) — leave quietly.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _loaded = true;
      _running = state['running'] == true;
      _finished = finished;
      _phaseIndex = state['phaseIndex'] as int? ?? 0;
      _phaseCount = state['phaseCount'] as int? ?? 1;
      _remaining = state['remainingSeconds'] as int? ?? 0;
      _isBreak = state['isBreak'] == true;
      _phaseLabel = state['phaseLabel'] as String? ?? '';
    });
  }

  Future<void> _togglePause() async {
    if (_running) {
      await _bridge.pauseIntervalSession();
    } else {
      await _bridge.resumeIntervalSession();
    }
    _sync();
  }

  Future<void> _end() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text(
          'End session?',
          style: TextStyle(color: Colors.white, fontSize: 19),
        ),
        content: const Text(
          'Your progress in this session will be lost.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _bridge.endIntervalSession();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final phaseColor = _isBreak ? const Color(0xFF8A8A8A) : _accent;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _finished ? _buildComplete() : _buildRunning(phaseColor),
      ),
    );
  }

  Widget _buildRunning(Color phaseColor) {
    final progress = _phaseCount == 0 ? 0.0 : (_phaseIndex + 1) / _phaseCount;
    return Column(
      children: [
        const SizedBox(height: 18),
        Text(
          'PHASE ${_phaseIndex + 1} OF $_phaseCount',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF242424),
              color: phaseColor,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _phaseLabel.isEmpty ? '—' : _phaseLabel,
                  style: TextStyle(
                    color: phaseColor,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatSeconds(_remaining),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 112,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                if (!_running) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'PAUSED',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            children: [
              SizedBox(
                width: 168,
                height: 72,
                child: FilledButton(
                  onPressed: _loaded ? _togglePause : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: Icon(
                    _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _end,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  minimumSize: const Size(120, 48),
                ),
                child: const Text(
                  'End session',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComplete() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: _accent, size: 96),
          const SizedBox(height: 20),
          const Text(
            'Session complete',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nice work. See you next time.',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(180, 56),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
