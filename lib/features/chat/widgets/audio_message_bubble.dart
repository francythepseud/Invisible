import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:invisible/utils/constants.dart';

/// Bolla per messaggi vocali: play/pause + slider + durata.
/// Ogni bolla ha il suo [AudioPlayer] indipendente.
class AudioMessageBubble extends StatefulWidget {
  final String localPath;
  final bool isOutgoing;

  const AudioMessageBubble({
    super.key,
    required this.localPath,
    required this.isOutgoing,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    try {
      _player = AudioPlayer();
      _player!.durationStream.listen((d) {
        if (mounted && !_disposed) setState(() => _duration = d ?? Duration.zero);
      });
      _player!.positionStream.listen((pos) {
        if (mounted && !_disposed) setState(() => _position = pos);
      });
      _player!.playerStateStream.listen((state) {
        if (mounted && !_disposed && state.processingState == ProcessingState.completed) {
          setState(() { _isPlaying = false; _position = Duration.zero; });
        }
      });
      _preload();
    } catch (e) {
      debugPrint('[AUDIO] initPlayer error: $e');
    }
  }

  Future<void> _preload() async {
    if (_disposed || _player == null) return;
    try {
      if (File(widget.localPath).existsSync()) {
        await _player!.setFilePath(widget.localPath);
      }
    } catch (e) {
      debugPrint('[AUDIO] preload error: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_player == null || _disposed) return;
    if (!File(widget.localPath).existsSync()) return;
    try {
      if (_isPlaying) {
        await _player!.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        if (_duration > Duration.zero && _position >= _duration) {
          await _player!.seek(Duration.zero);
        }
        if (_player!.processingState == ProcessingState.idle ||
            _player!.processingState == ProcessingState.completed) {
          await _player!.setFilePath(widget.localPath);
        }
        await _player!.play();
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('[AUDIO] playback error: $e');
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final out = widget.isOutgoing;
    final btnColor  = out ? Colors.white : AppConstants.primaryBlue;
    final subColor  = out ? Colors.white60 : AppConstants.textTertiary;
    final trackOn   = out ? Colors.white : AppConstants.primaryBlue;
    final trackOff  = out ? Colors.white30 : AppConstants.divider;

    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsante play/pause
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: btnColor.withValues(alpha: 0.18),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: btnColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Slider + durata
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: trackOn,
                    inactiveTrackColor: trackOff,
                    thumbColor: trackOn,
                    overlayColor: trackOn.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (v) async {
                      if (_player == null || _disposed) return;
                      final seek = Duration(
                        milliseconds:
                            (v * _duration.inMilliseconds).round(),
                      );
                      try { await _player!.seek(seek); } catch (_) {}
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _isPlaying || _position > Duration.zero
                        ? _fmt(_position)
                        : _fmt(_duration),
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
