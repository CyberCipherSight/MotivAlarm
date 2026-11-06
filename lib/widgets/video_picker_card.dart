import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/native_alarm_bridge.dart';
import 'native_video_preview.dart';

class VideoPickerCard extends StatefulWidget {
  const VideoPickerCard({
    required this.videoUri,
    required this.durationSeconds,
    required this.onVideoChanged,
    super.key,
  });

  final String? videoUri;
  final int? durationSeconds;
  final void Function(String? uri, int? durationSeconds) onVideoChanged;

  @override
  State<VideoPickerCard> createState() => _VideoPickerCardState();
}

class _VideoPickerCardState extends State<VideoPickerCard> {
  final _bridge = const NativeAlarmBridge();
  double _aspectRatio = 16 / 9;
  bool _playing = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadAspectRatio(widget.videoUri);
  }

  @override
  void didUpdateWidget(covariant VideoPickerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUri != widget.videoUri) {
      _playing = true;
      _loadAspectRatio(widget.videoUri);
    }
  }

  Future<void> _loadAspectRatio(String? uri) async {
    if (uri == null || uri.isEmpty) return;
    try {
      final info = await _bridge.validateVideo(uri);
      if (!mounted || widget.videoUri != uri) return;
      setState(() => _aspectRatio = info.aspectRatio);
    } catch (_) {
      // Existing selection may have been deleted or its access revoked.
      // Keep the current preview dimensions; native playback handles failure.
    }
  }

  Future<void> _pickVideo() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await FilePicker.pickFiles(type: FileType.video);
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final uri = file.identifier?.isNotEmpty == true
          ? file.identifier
          : file.path;
      if (uri == null || uri.isEmpty) return;

      final validation = await _bridge.validateVideo(uri);
      if (!mounted) return;
      if (!validation.valid) {
        _showVideoError(
          validation.errorMessage ?? 'Could not read this video.',
        );
        return;
      }

      await _bridge.persistVideoUriPermission(uri);
      if (!mounted) return;
      widget.onVideoChanged(uri, validation.durationSeconds);
      setState(() {
        _aspectRatio = validation.aspectRatio;
        _playing = true;
      });
    } catch (_) {
      if (mounted) _showVideoError('Could not read this video.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showVideoError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget.videoUri != null && widget.videoUri!.isNotEmpty;
    return Card(
      color: const Color(0xFF151515),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF272727)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_display_rounded, color: Colors.white70),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Alarm video',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasVideo)
                  IconButton(
                    tooltip: 'Remove video',
                    onPressed: () => widget.onVideoChanged(null, null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasVideo)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: _aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      NativeVideoPreview(
                        key: ValueKey(widget.videoUri),
                        uri: widget.videoUri!,
                        muted: false,
                        playing: _playing,
                      ),
                      IconButton.filled(
                        onPressed: () => setState(() => _playing = !_playing),
                        icon: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                height: 140,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF202020),
                ),
                child: const Text(
                  'No video selected',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            if (widget.durationSeconds != null)
              Text(
                'Selected length: ${widget.durationSeconds}s',
                style: const TextStyle(color: Colors.white54),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _pickVideo,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_rounded),
              label: Text(hasVideo ? 'Change Video' : 'Choose Video'),
            ),
          ],
        ),
      ),
    );
  }
}
