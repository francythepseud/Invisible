import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:invisible/core/services/call_service.dart';
import 'package:invisible/core/services/call_log_service.dart';
import 'package:invisible/models/call_log_entry.dart';
import 'package:invisible/utils/constants.dart';
import 'package:uuid/uuid.dart';

/// Schermata a tutto schermo mostrata quando arriva una chiamata in entrata.
/// Suona la ringtone + vibra in loop finché l'utente risponde o rifiuta.
class IncomingCallScreen extends StatefulWidget {
  final IncomingCallInfo callInfo;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallScreen({
    super.key,
    required this.callInfo,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  AudioPlayer? _player;
  bool _ringtoneStopped = false;
  Timer? _vibrationTimer;
  StreamSubscription<CallState>? _callStateSub;

  @override
  void initState() {
    super.initState();
    _startRingtone();
    // Chiudi automaticamente se il chiamante riaggancia prima che rispondiamo
    _callStateSub = CallService().callStateStream.listen((state) {
      if (state == CallState.ended || state == CallState.idle) {
        _stopRingtone();
        // Salva come chiamata persa
        CallLogService().saveEntry(CallLogEntry(
          id: const Uuid().v4(),
          contactName: widget.callInfo.callerName,
          callType: widget.callInfo.isVideo ? CallType.video : CallType.audio,
          direction: CallDirection.incoming,
          status: CallStatus.missed,
          durationSeconds: 0,
          startedAt: DateTime.now(),
        ));
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    _stopRingtone();
    super.dispose();
  }

  Future<void> _startRingtone() async {
    _player = AudioPlayer();
    try {
      // Configura sessione audio per la ringtone.
      // iOS: playAndRecord obbligatorio per suonare con silent switch attivo;
      //   mixWithOthers permette a WebRTC di sovrascrivere la sessione senza conflitti.
      // Android: gain (non transient) così quando il ringtone termina AudioFocus
      //   viene rilasciato esplicitamente e WebRTC può reclamare il focus audio.
      await _player!.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
      await _player!.setVolume(1.0);
      await _player!.setReleaseMode(ReleaseMode.loop);
      // Salva su file temporaneo (BytesSource non è supportato su iOS)
      final tmpDir = await getTemporaryDirectory();
      final ringFile = File('${tmpDir.path}/incoming_ring.wav');
      await ringFile.writeAsBytes(_generateRingtoneWav());
      await _player!.play(DeviceFileSource(ringFile.path));
    } catch (e) {
      debugPrint('[CALL] Ringtone error: $e');
    }

    // Vibrazione ritmica ogni 1.5 secondi
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _stopRingtone() {
    if (_ringtoneStopped) return;
    _ringtoneStopped = true;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    try { _player?.stop(); } catch (_) {}
    try { _player?.dispose(); } catch (_) {}
    _player = null;
  }

  void _onAccept() {
    _stopRingtone();
    widget.onAccept();
  }

  void _onReject() {
    _stopRingtone();
    widget.onReject();
  }

  /// Genera un WAV PCM mono 44100Hz con pattern telefono (1s tono + 0.5s silenzio).
  /// Dual-tone 480Hz + 440Hz — suono tipico squillo telefonico.
  static Uint8List _generateRingtoneWav() {
    const sampleRate = 44100;
    const totalSamples = sampleRate * 3 ~/ 2; // 1.5 secondi (1s tono + 0.5s silenzio)
    const amplitude = 0.45;

    final data = ByteData(totalSamples * 2);
    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double value;
      if (t < 1.0) {
        // Dual-tone ring: 480Hz + 440Hz con fade-in/out morbido
        final envelope = (t < 0.02)
            ? t / 0.02
            : (t > 0.95)
                ? (1.0 - t) / 0.05
                : 1.0;
        value = (sin(2 * pi * 480 * t) + sin(2 * pi * 440 * t)) *
            amplitude *
            envelope;
      } else {
        value = 0.0; // silenzio nei 0.5s rimanenti
      }
      final sample = (value.clamp(-1.0, 1.0) * 32767).round().clamp(-32768, 32767);
      data.setInt16(i * 2, sample, Endian.little);
    }

    final audioBytes = data.buffer.asUint8List();
    final dataSize = audioBytes.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF chunk
    header.setUint8(0, 0x52); header.setUint8(1, 0x49);
    header.setUint8(2, 0x46); header.setUint8(3, 0x46); // "RIFF"
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41);
    header.setUint8(10, 0x56); header.setUint8(11, 0x45); // "WAVE"
    // fmt chunk
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74); header.setUint8(15, 0x20); // "fmt "
    header.setUint32(16, 16, Endian.little);   // chunk size
    header.setUint16(20, 1, Endian.little);    // PCM
    header.setUint16(22, 1, Endian.little);    // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little);    // block align
    header.setUint16(34, 16, Endian.little);   // bits per sample
    // data chunk
    header.setUint8(36, 0x64); header.setUint8(37, 0x61);
    header.setUint8(38, 0x74); header.setUint8(39, 0x61); // "data"
    header.setUint32(40, dataSize, Endian.little);

    final result = Uint8List(44 + dataSize);
    result.setAll(0, header.buffer.asUint8List());
    result.setAll(44, audioBytes);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 60),
            // ─── Chiamante ───────────────────────────────────────────────────
            Column(
              children: [
                // Avatar con pulse animato
                _PulsingAvatar(name: widget.callInfo.callerName),
                const SizedBox(height: 24),
                Text(
                  widget.callInfo.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.callInfo.isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: AppConstants.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.callInfo.isVideo
                          ? 'Videochiamata cifrata in arrivo...'
                          : 'Chiamata cifrata in arrivo...',
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      color: AppConstants.success.withValues(alpha: 0.8),
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'DTLS-SRTP • Rete Mesh',
                      style: TextStyle(
                        color: AppConstants.success.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // ─── Bottoni ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFFF3B30),
                    label: 'Rifiuta',
                    onTap: _onReject,
                  ),
                  _CallButton(
                    icon: widget.callInfo.isVideo
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: const Color(0xFF34C759),
                    label: 'Accetta',
                    onTap: _onAccept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Avatar con animazione pulse ─────────────────────────────────────────────

class _PulsingAvatar extends StatefulWidget {
  final String name;
  const _PulsingAvatar({required this.name});

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> _avatarColors(String name) {
    final gradients = [
      [const Color(0xFF2196F3), const Color(0xFF0D47A1)],
      [const Color(0xFF9C27B0), const Color(0xFF4A148C)],
      [const Color(0xFF00BCD4), const Color(0xFF006064)],
      [const Color(0xFF4CAF50), const Color(0xFF1B5E20)],
      [const Color(0xFFFF5722), const Color(0xFFBF360C)],
      [const Color(0xFFE91E63), const Color(0xFF880E4F)],
    ];
    final idx = name.isNotEmpty ? name.codeUnitAt(0) % gradients.length : 0;
    return gradients[idx];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: _pulse.value,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _avatarColors(widget.name),
            ),
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryBlue.withValues(alpha: 0.35 * _pulse.value),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bottone chiamata ─────────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            color: AppConstants.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
