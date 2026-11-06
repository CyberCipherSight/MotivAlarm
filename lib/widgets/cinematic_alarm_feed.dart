import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
import 'cinematic_alarm_card.dart';

/// Vertical snap-scrolling video feed, one alarm per row. Every alarm within
/// the visible window plays its video simultaneously (not just the centered
/// one) so a short list reads as "all my alarms, all alive" rather than
/// "only the selected one." Disabled alarms still render their video (so
/// their card shows a real frame, not a blank placeholder) but stay
/// paused — off means off, including its video.
///
/// Playback goes through [CinematicAlarmCard]'s native `VideoView`-based
/// preview rather than `video_player`, so there's no per-alarm orientation
/// check or thumbnail fallback to manage here anymore — see
/// [NativeVideoPreview] for why. The window below exists purely to bound how
/// many native video views are alive at once for long lists, matching how
/// many rows the compact (~28%-viewport) card height can show on screen at
/// a time plus a small scroll buffer.
class CinematicAlarmFeed extends StatefulWidget {
  const CinematicAlarmFeed({
    required this.alarms,
    required this.onOpenEditor,
    required this.onToggle,
    required this.onDelete,
    this.brokenVideoIds = const {},
    super.key,
  });

  final List<AlarmModel> alarms;

  /// Alarms whose video is no longer readable (e.g. after a reinstall
  /// restore) — their cards show a "re-pick" hint instead of a dead player.
  final Set<String> brokenVideoIds;
  final ValueChanged<AlarmModel> onOpenEditor;
  final Future<void> Function(AlarmModel alarm, bool enabled) onToggle;
  final ValueChanged<AlarmModel> onDelete;

  @override
  State<CinematicAlarmFeed> createState() => _CinematicAlarmFeedState();
}

class _CinematicAlarmFeedState extends State<CinematicAlarmFeed> {
  static const _viewportFraction = 0.28;
  static const _windowRadius = 3;

  late final PageController _pageController = PageController(
    viewportFraction: _viewportFraction,
  );
  int _settledIndex = 0;

  @override
  void didUpdateWidget(covariant CinematicAlarmFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alarms.isEmpty) return;
    _settledIndex = _settledIndex.clamp(0, widget.alarms.length - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) => setState(() => _settledIndex = index);

  bool _inWindow(int index) => (index - _settledIndex).abs() <= _windowRadius;

  @override
  Widget build(BuildContext context) {
    final alarms = widget.alarms;
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      padEnds: false,
      itemCount: alarms.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final alarm = alarms[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          // Keyed by alarm id: alarms are sorted by time, so adding/editing
          // one can shift every later alarm's *index* without changing what
          // it represents. Without a stable key here, Flutter would reuse
          // whatever Element (and its already-created native AndroidView)
          // previously sat at this index and just feed it new data —
          // but AndroidView's creationParams (the video URI) are only read
          // once, at creation, so the reused native player kept showing
          // its original video regardless of which alarm now occupied that
          // slot. The key forces a real dispose+recreate when the alarm at
          // a given position actually changes, instead of a silent rebind.
          child: CinematicAlarmCard(
            key: ValueKey(alarm.id),
            alarm: alarm,
            videoBroken: widget.brokenVideoIds.contains(alarm.id),
            showVideo: _inWindow(index),
            onTap: () => widget.onOpenEditor(alarm),
            onToggle: (enabled) => widget.onToggle(alarm, enabled),
            onDelete: () => widget.onDelete(alarm),
          ),
        );
      },
    );
  }
}
