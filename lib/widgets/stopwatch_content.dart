import 'dart:async';

import 'package:flutter/material.dart';

class StopwatchContent extends StatefulWidget {
  const StopwatchContent({super.key});

  @override
  State<StopwatchContent> createState() => _StopwatchContentState();
}

class _StopwatchContentState extends State<StopwatchContent> {
  final Stopwatch _stopwatch = Stopwatch();
  final List<_LapEntry> _laps = [];
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  Duration _lastLapElapsed = Duration.zero;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    _stopwatch.start();
    _ticker ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (mounted) setState(() => _elapsed = _stopwatch.elapsed);
    });
    setState(() {});
  }

  void _pause() {
    _stopwatch.stop();
    setState(() => _elapsed = _stopwatch.elapsed);
  }

  void _reset() {
    _stopwatch
      ..stop()
      ..reset();
    setState(() {
      _elapsed = Duration.zero;
      _lastLapElapsed = Duration.zero;
      _laps.clear();
    });
  }

  void _lap() {
    if (!_stopwatch.isRunning) return;
    final total = _stopwatch.elapsed;
    final lap = total - _lastLapElapsed;
    setState(() {
      _lastLapElapsed = total;
      _laps.insert(
        0,
        _LapEntry(index: _laps.length + 1, lap: lap, total: total),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _stopwatch.isRunning;
    // Only the lap list scrolls — the time display, header, and controls
    // stay fixed in place instead of being pushed around by growing laps.
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 292,
              height: 292,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF222222),
                border: Border.all(color: const Color(0xFF4D9BFF), width: 8),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  _formatStopwatch(_elapsed),
                  key: ValueKey(_elapsed.inMilliseconds ~/ 100),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          const _LapHeader(),
          const Divider(color: Color(0xFF242424), height: 28),
          Expanded(
            child: _laps.isEmpty
                ? const Center(
                    child: Text(
                      'No laps yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF777777), fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    itemCount: _laps.length,
                    itemBuilder: (context, index) {
                      final lap = _laps[index];
                      return _LapRow(
                        index: lap.index,
                        lap: _formatStopwatch(lap.lap, showHours: false),
                        total: _formatStopwatch(lap.total, showHours: false),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundControlButton(
                icon: Icons.refresh_rounded,
                onPressed: _elapsed == Duration.zero ? null : _reset,
              ),
              _PrimaryControlButton(
                icon: isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onPressed: isRunning ? _pause : _start,
              ),
              _RoundControlButton(
                icon: Icons.flag_rounded,
                onPressed: isRunning ? _lap : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatStopwatch(Duration duration, {bool showHours = true}) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final hundredths = (duration.inMilliseconds.remainder(1000) / 10).floor();
    if (!showHours || hours == 0) {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}.'
          '${hundredths.toString().padLeft(2, '0')}';
    }
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _LapEntry {
  const _LapEntry({
    required this.index,
    required this.lap,
    required this.total,
  });

  final int index;
  final Duration lap;
  final Duration total;
}

class _LapHeader extends StatelessWidget {
  const _LapHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _HeaderText('Lap')),
        Expanded(child: _HeaderText('Lap Time')),
        Expanded(child: _HeaderText('Overall Time', alignEnd: true)),
      ],
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text, {this.alignEnd = false});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: const TextStyle(
        color: Color(0xFFAAAAAA),
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

class _LapRow extends StatelessWidget {
  const _LapRow({required this.index, required this.lap, required this.total});

  final int index;
  final String lap;
  final String total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '#$index',
              style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 20),
            ),
          ),
          Expanded(
            child: Text(
              '+$lap',
              style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 20),
            ),
          ),
          Expanded(
            child: Text(
              total,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryControlButton extends StatelessWidget {
  const _PrimaryControlButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      height: 70,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF4D9BFF),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
        child: Icon(icon, size: 42),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF202020),
        disabledBackgroundColor: const Color(0xFF151515),
        foregroundColor: Colors.white,
        disabledForegroundColor: const Color(0xFF3B3B3B),
        fixedSize: const Size(70, 70),
      ),
      icon: Icon(icon, size: 34),
    );
  }
}
