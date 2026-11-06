import 'dart:async';

import 'package:flutter/material.dart';

import '../services/native_alarm_bridge.dart';
import 'interval_session_content.dart';

/// The Timer tab: a mode toggle between the simple countdown timer and
/// interval sessions (structured set/break cycles). One binary choice up
/// top (Hick's Law) instead of burying intervals in a menu.
class TimerContent extends StatefulWidget {
  const TimerContent({super.key});

  @override
  State<TimerContent> createState() => _TimerContentState();
}

class _TimerContentState extends State<TimerContent> {
  bool _intervalsMode = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ModeChip(
                label: 'Timer',
                selected: !_intervalsMode,
                onTap: () => setState(() => _intervalsMode = false),
              ),
              const SizedBox(width: 10),
              _ModeChip(
                label: 'Intervals',
                selected: _intervalsMode,
                onTap: () => setState(() => _intervalsMode = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: _intervalsMode
              ? const IntervalSessionContent()
              : const _CountdownTimer(),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF4D9BFF),
      backgroundColor: const Color(0xFF242424),
      side: BorderSide(
        color: selected ? const Color(0xFF4D9BFF) : const Color(0xFF3A3A3A),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFFBDBDBD),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CountdownTimer extends StatefulWidget {
  const _CountdownTimer();

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  static const _presets = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 20),
  ];

  final _bridge = const NativeAlarmBridge();
  Duration _selected = const Duration(minutes: 5);
  Duration _remaining = const Duration(minutes: 5);
  Timer? _timer;
  bool _running = false;
  bool _alerting = false;

  @override
  void dispose() {
    _timer?.cancel();
    if (_alerting) _bridge.stopTimerAlert();
    super.dispose();
  }

  void _startPause() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining.inSeconds <= 1) {
        _timer?.cancel();
        _alerting = true;
        _bridge.startTimerAlert();
        setState(() {
          _remaining = Duration.zero;
          _running = false;
        });
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
    setState(() {});
  }

  void _reset() {
    _timer?.cancel();
    if (_alerting) {
      _alerting = false;
      _bridge.stopTimerAlert();
    }
    setState(() {
      _running = false;
      _remaining = _selected;
    });
  }

  void _setDuration(Duration duration) {
    if (_running || duration == Duration.zero) return;
    setState(() {
      _selected = duration;
      _remaining = duration;
    });
  }

  Future<void> _openCustomTimerPicker() async {
    if (_running) return;
    final result = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _CustomTimerSheet(initial: _selected),
    );
    if (result != null) _setDuration(result);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _selected.inSeconds == 0
        ? 0.0
        : _remaining.inSeconds / _selected.inSeconds;
    final isCustom = !_presets.contains(_selected);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 132),
      children: [
        Center(
          child: SizedBox.square(
            dimension: 292,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: progress, end: progress),
              duration: const Duration(milliseconds: 250),
              builder: (context, value, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 8,
                        backgroundColor: const Color(0xFF242424),
                        color: const Color(0xFF4D9BFF),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    child!,
                  ],
                );
              },
              child: Center(
                child: Text(
                  _formatTimer(_remaining),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 34),
        const Text(
          'Quick timers',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in _presets)
              _DurationChip(
                label: _presetLabel(preset),
                selected: _selected == preset,
                onTap: () => _setDuration(preset),
              ),
            _DurationChip(
              label: isCustom ? _presetLabel(_selected) : 'Custom',
              icon: Icons.tune_rounded,
              selected: isCustom,
              onTap: _openCustomTimerPicker,
            ),
          ],
        ),
        const SizedBox(height: 38),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              onPressed: _remaining == _selected ? null : _reset,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF202020),
                disabledBackgroundColor: const Color(0xFF151515),
                foregroundColor: Colors.white,
                disabledForegroundColor: const Color(0xFF3B3B3B),
                fixedSize: const Size(70, 70),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 34),
            ),
            const SizedBox(width: 28),
            SizedBox(
              width: 154,
              height: 70,
              child: FilledButton(
                onPressed: _remaining == Duration.zero ? _reset : _startPause,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4D9BFF),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: Icon(
                  _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 42,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _presetLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    if (seconds > 0 && minutes == 0) return '${seconds}s';
    if (seconds > 0) return '${minutes}m ${seconds}s';
    return '$minutes min';
  }

  String _formatTimer(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _CustomTimerSheet extends StatefulWidget {
  const _CustomTimerSheet({required this.initial});

  final Duration initial;

  @override
  State<_CustomTimerSheet> createState() => _CustomTimerSheetState();
}

class _CustomTimerSheetState extends State<_CustomTimerSheet> {
  late int _hours;
  late int _minutes;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _hours = widget.initial.inHours.clamp(0, 23);
    _minutes = widget.initial.inMinutes.remainder(60);
    _seconds = widget.initial.inSeconds.remainder(60);
  }

  Duration get _duration =>
      Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

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
            'Custom timer',
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
                label: 'hours',
                value: _hours,
                max: 23,
                onChanged: (value) => setState(() => _hours = value),
              ),
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
            onPressed: _duration == Duration.zero
                ? null
                : () => Navigator.of(context).pop(_duration),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4D9BFF),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Set Timer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class NumberColumn extends StatelessWidget {
  const NumberColumn({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    super.key,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => onChanged(value >= max ? 0 : value + 1),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          color: Colors.white70,
          tooltip: 'Increase $label',
        ),
        Container(
          width: 64,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Semantics(
            label: '$value $label',
            child: Text(
              value.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => onChanged(value <= 0 ? max : value - 1),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          color: Colors.white70,
          tooltip: 'Decrease $label',
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon != null ? Icon(icon, size: 18) : null,
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF4D9BFF),
      backgroundColor: const Color(0xFF242424),
      side: BorderSide(
        color: selected ? const Color(0xFF4D9BFF) : const Color(0xFF3A3A3A),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFFBDBDBD),
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}
