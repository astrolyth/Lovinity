import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';

const _maxLength = Duration(minutes: 2);

String _clock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Records a voice note in a sheet; resolves to the file and its length, or
/// null when cancelled or the microphone is refused.
Future<(File, Duration)?> recordVoiceNote(BuildContext context) =>
    showLovSheet<(File, Duration)>(
      context,
      title: 'Voice note',
      builder: (_) => const _Recorder(),
    );

class _Recorder extends StatefulWidget {
  const _Recorder();

  @override
  State<_Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<_Recorder> {
  final _recorder = AudioRecorder();
  final _watch = Stopwatch();
  Timer? _tick;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Allow the microphone in Settings to record.');
      return;
    }
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: _path!,
    );
    HapticFeedback.mediumImpact();
    _watch.start();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_watch.elapsed >= _maxLength) _send();
      if (mounted) setState(() {});
    });
  }

  Future<void> _send() async {
    _tick?.cancel();
    _watch.stop();
    final path = await _recorder.stop();
    if (!mounted) return;
    Navigator.of(context).pop(
      path == null ? null : (File(path), _watch.elapsed),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    // Cancelled (swiped away or Cancel): drop the half-made file.
    unawaited(_recorder.cancel().whenComplete(_recorder.dispose));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(_error!, style: TextStyle(color: p.muted)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Icon(Icons.mic_rounded, size: 56, color: p.accent),
        const SizedBox(height: 10),
        Text(
          _clock(_watch.elapsed),
          style: lovDisplay(context, size: 32),
          semanticsLabel: 'Recording, ${_watch.elapsed.inSeconds} seconds',
        ),
        const SizedBox(height: 4),
        Text(
          'Up to ${_maxLength.inMinutes} minutes',
          style: TextStyle(fontSize: 12, color: p.faint),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: LovQuietButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LovPrimaryButton(
                label: 'Send',
                icon: Icons.arrow_upward_rounded,
                onPressed: _watch.elapsed.inMilliseconds < 500 ? null : _send,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A voice note in a chat bubble: play/pause, progress and length.
/// [path] is null until the encrypted file has been downloaded.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.path,
    required this.durationMs,
    required this.color,
    required this.onDownload,
    this.downloading = false,
  });
  final String? path;
  final int? durationMs;
  final Color color;
  final VoidCallback onDownload;
  final bool downloading;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  VideoPlayerController? _player;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final path = widget.path;
    if (path == null) return widget.onDownload();
    var player = _player;
    if (player == null) {
      player = _player = VideoPlayerController.file(File(path));
      await player.initialize();
      player.addListener(() {
        if (mounted) setState(() {});
      });
    }
    final v = player.value;
    if (v.isPlaying) {
      await player.pause();
    } else {
      if (v.position >= v.duration) await player.seekTo(Duration.zero);
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _player?.value;
    final total =
        v?.duration ?? Duration(milliseconds: widget.durationMs ?? 0);
    final pos = v?.position ?? Duration.zero;
    final playing = v?.isPlaying ?? false;
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          IconButton(
            tooltip: widget.path == null
                ? 'Download voice note'
                : playing
                ? 'Pause'
                : 'Play',
            onPressed: widget.downloading ? null : _toggle,
            icon: widget.downloading
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.color,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: widget.color,
                  ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: total.inMilliseconds == 0
                  ? 0
                  : pos.inMilliseconds / total.inMilliseconds,
              color: widget.color,
              backgroundColor: widget.color.withValues(alpha: .25),
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _clock(playing || pos > Duration.zero ? pos : total),
            style: TextStyle(fontSize: 12, color: widget.color),
          ),
        ],
      ),
    );
  }
}
