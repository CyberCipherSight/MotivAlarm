import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
import '../utils/formatters.dart';
import 'native_video_preview.dart';

/// A single row in the alarm feed. The video lives in its own square
/// thumbnail region rather than behind the text — full-bleed video competed
/// with the time/label for attention, so the two are now visually separated:
/// thumbnail on one side, plain dark panel with legible text on the other.
/// Every row plays its video simultaneously (no "only the centered one"
/// dimming) — the only thing that dims a card is the alarm itself being
/// switched off, which also pauses its video. [showVideo] is false for rows
/// outside the parent feed's pooling window (bounds how many native video
/// views are alive at once for long lists).
class CinematicAlarmCard extends StatelessWidget {
  const CinematicAlarmCard({
    required this.alarm,
    required this.showVideo,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
    this.videoBroken = false,
    super.key,
  });

  final AlarmModel alarm;
  final bool showVideo;

  /// True when the alarm's video URI is no longer readable (permissions
  /// don't survive reinstall) — the thumbnail becomes a "re-pick" hint and
  /// the alarm rings with the backup tone until fixed.
  final bool videoBroken;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: alarm.enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: _Background(
                    alarm: alarm,
                    showVideo: showVideo && !videoBroken,
                    videoBroken: videoBroken,
                  ),
                ),
                Expanded(
                  child: _InfoPanel(
                    alarm: alarm,
                    onToggle: onToggle,
                    onDelete: onDelete,
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

class _Background extends StatelessWidget {
  const _Background({
    required this.alarm,
    required this.showVideo,
    this.videoBroken = false,
  });

  final AlarmModel alarm;
  final bool showVideo;
  final bool videoBroken;

  @override
  Widget build(BuildContext context) {
    if (videoBroken) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF2A1215)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_rounded,
                color: Color(0xFFF87171),
                size: 26,
              ),
              SizedBox(height: 6),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Re-pick video',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF87171),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (showVideo && alarm.hasVideo) {
      return ColoredBox(
        color: Colors.black,
        // Keyed by the video's own URI (on top of the card-level key by
        // alarm id) so swapping the video on an *existing* alarm — same
        // id, new uri — also forces the native player to be recreated
        // rather than silently kept showing the old clip.
        child: NativeVideoPreview(
          key: ValueKey(alarm.videoUri),
          uri: alarm.videoUri!,
          playing: alarm.enabled,
        ),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2735), Color(0xFF0B1018)],
        ),
      ),
      child: Center(
        child: Icon(
          alarm.hasVideo
              ? Icons.movie_creation_rounded
              : Icons.video_camera_back_rounded,
          color: const Color(0xFF2F80ED).withValues(alpha: 0.55),
          size: 28,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.alarm,
    required this.onToggle,
    required this.onDelete,
  });

  final AlarmModel alarm;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final time = formatAlarmTime(alarm.timeHour, alarm.timeMinute);
    final repeat = formatRepeatDays(alarm.repeatDays);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${alarm.label.isEmpty ? 'Alarm' : alarm.label} · $repeat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: alarm.enabled,
              onChanged: onToggle,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF2F80ED),
              inactiveThumbColor: const Color(0xFF9C9C9C),
              inactiveTrackColor: const Color(0xFF444444),
            ),
          ),
          // Deliberate gap so a routine toggle tap can't clip the
          // destructive delete action right next to it.
          const SizedBox(width: 14),
          _RoundIconButton(icon: Icons.delete_outline_rounded, onTap: onDelete),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white60, size: 24),
        ),
      ),
    );
  }
}
