import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/native_alarm_bridge.dart';

class LocalAudioPickerCard extends StatefulWidget {
  const LocalAudioPickerCard({
    required this.audioUri,
    required this.onAudioChanged,
    super.key,
  });

  final String? audioUri;
  final ValueChanged<String?> onAudioChanged;

  @override
  State<LocalAudioPickerCard> createState() => _LocalAudioPickerCardState();
}

class _LocalAudioPickerCardState extends State<LocalAudioPickerCard> {
  final _bridge = const NativeAlarmBridge();
  bool _previewing = false;
  bool _busy = false;

  bool get _hasAudio => widget.audioUri != null && widget.audioUri!.isNotEmpty;

  @override
  void dispose() {
    _bridge.stopAudioPreview().catchError((_) {});
    super.dispose();
  }

  Future<void> _pickAudio() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.pickFiles(type: FileType.audio);
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final uri = file.identifier?.isNotEmpty == true
          ? file.identifier
          : file.path;
      if (uri == null || uri.isEmpty) return;
      await _bridge.persistMediaUriPermission(uri);
      await _bridge.stopAudioPreview();
      if (!mounted) return;
      setState(() => _previewing = false);
      widget.onAudioChanged(uri);
    } catch (_) {
      if (mounted) _showAudioError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePreview() async {
    if (!_hasAudio || _busy) return;
    setState(() => _busy = true);
    try {
      if (_previewing) {
        await _bridge.stopAudioPreview();
      } else {
        await _bridge.previewAudio(widget.audioUri!);
      }
      if (mounted) setState(() => _previewing = !_previewing);
    } catch (_) {
      if (mounted) {
        setState(() => _previewing = false);
        _showAudioError();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAudio() async {
    try {
      await _bridge.stopAudioPreview();
    } catch (_) {
      // A failed/released preview must not prevent removing its selection.
    }
    if (!mounted) return;
    setState(() => _previewing = false);
    widget.onAudioChanged(null);
  }

  void _showAudioError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not read this audio. Please choose another file.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2B2B2B)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq_rounded, color: Colors.white70),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Local alarm music',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_hasAudio)
                  IconButton(
                    tooltip: 'Remove audio',
                    onPressed: _busy ? null : _clearAudio,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _hasAudio
                  ? 'Custom audio selected'
                  : 'Use default alarm sound or choose a local audio file.',
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickAudio,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open_rounded),
                    label: Text(_hasAudio ? 'Change Music' : 'Choose Music'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: _previewing ? 'Stop preview' : 'Preview audio',
                  onPressed: _busy || !_hasAudio ? null : _togglePreview,
                  icon: Icon(
                    _previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
