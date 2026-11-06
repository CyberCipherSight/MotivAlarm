import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/alarm_model.dart';
import '../services/native_alarm_bridge.dart';
import '../utils/formatters.dart';

class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({required this.alarm, super.key});

  final AlarmModel alarm;

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  final _bridge = const NativeAlarmBridge();
  VideoPlayerController? _controller;
  Timer? _clockTimer;
  Timer? _videoLimitTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    final uri = widget.alarm.videoUri;
    if (uri != null && uri.isNotEmpty) {
      final parsed = Uri.tryParse(uri);
      _controller =
          (parsed?.scheme == 'content'
                ? VideoPlayerController.contentUri(parsed!)
                : VideoPlayerController.file(File(uri)))
            ..initialize().then((_) {
              if (!mounted) return;
              _controller!
                ..setLooping(false)
                ..setVolume(
                  widget.alarm.videoBehavior == VideoBehavior.muteVideoPlayTone
                      ? 0
                      : 1,
                )
                ..play();
              _startVideoLimitTimer();
              setState(() {});
            });
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _videoLimitTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startVideoLimitTimer() {
    _videoLimitTimer?.cancel();
    _videoLimitTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
      final limitSeconds = (widget.alarm.videoDurationSeconds ?? 60).clamp(
        1,
        60,
      );
      if (controller.value.position.inSeconds < limitSeconds) return;
      if (widget.alarm.videoBehavior == VideoBehavior.playOnceThenTone) {
        controller.pause();
      } else {
        controller.seekTo(Duration.zero);
        controller.play();
      }
    });
  }

  Future<void> _stop() async {
    await _bridge.stopAlarm(widget.alarm.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    await _bridge.snoozeAlarm(widget.alarm.id, widget.alarm.snoozeMinutes);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.black26, Colors.black87],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      formatAlarmTime(_now.hour, _now.minute),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.alarm.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    _SlideActionControl(
                      label:
                          'Slide fully to snooze ${widget.alarm.snoozeMinutes} min',
                      knobLabel: 'Snooze',
                      threshold: .96,
                      onComplete: () => _snooze(),
                    ),
                    const SizedBox(height: 12),
                    _SlideActionControl(
                      label: 'Slide to stop',
                      knobLabel: 'Stop',
                      threshold: .9,
                      onComplete: () => _stop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideActionControl extends StatefulWidget {
  const _SlideActionControl({
    required this.label,
    required this.knobLabel,
    required this.threshold,
    required this.onComplete,
  });

  final String label;
  final String knobLabel;
  final double threshold;
  final VoidCallback onComplete;

  @override
  State<_SlideActionControl> createState() => _SlideActionControlState();
}

class _SlideActionControlState extends State<_SlideActionControl> {
  double _drag = 0;
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const knobWidth = 116.0;
        final maxDrag = (constraints.maxWidth - knobWidth - 8).clamp(
          1.0,
          double.infinity,
        );
        return GestureDetector(
          onHorizontalDragUpdate: _completed
              ? null
              : (details) {
                  setState(() {
                    _drag = (_drag + details.delta.dx).clamp(0, maxDrag);
                  });
                },
          onHorizontalDragEnd: _completed
              ? null
              : (_) {
                  if (_drag / maxDrag >= widget.threshold) {
                    _completed = true;
                    widget.onComplete();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
          child: Container(
            height: 68,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOut,
                  left: _drag,
                  top: 0,
                  bottom: 0,
                  width: knobWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text(
                        widget.knobLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
