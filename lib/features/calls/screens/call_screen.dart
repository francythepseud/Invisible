import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:invisible/core/services/call_log_service.dart';
import 'package:invisible/core/services/call_service.dart';
import 'package:invisible/models/call_log_entry.dart';
import 'package:invisible/utils/constants.dart';
import 'package:uuid/uuid.dart';

/// Schermata chiamata attiva: audio o video, cifrata E2E via mesh VPN.
///
/// Audio: avatar + timer + controlli (mute, speaker, fine).
/// Video: video remoto full-screen + video locale in PiP + controlli.
class CallScreen extends StatefulWidget {
  final String contactName;
  final String? contactId;
  final bool isVideo;
  final bool isOutgoing;

  const CallScreen({
    super.key,
    required this.contactName,
    this.contactId,
    required this.isVideo,
    required this.isOutgoing,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _callService = CallService();

  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  StreamSubscription<MediaStream>? _remoteStreamSub;
  StreamSubscription<CallState>? _callStateSub;

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _isConnecting = true;
  bool _isNavigatingAway = false;

  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Mantieni lo schermo acceso durante la chiamata
    try { await WakelockPlus.enable(); } catch (_) {}

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Collega lo stream locale al renderer
    final local = _callService.localStream;
    if (local != null) _localRenderer.srcObject = local;

    // Collega lo stream remoto se già disponibile (onTrack potrebbe essere scattato
    // prima che CallScreen fosse pushata — race condition su connessioni veloci)
    final remote = _callService.remoteStream;
    if (remote != null) {
      _remoteRenderer.srcObject = remote;
      setState(() => _isConnecting = false);
      _startTimer();
    }

    _remoteStreamSub = _callService.remoteStreamStream.listen((stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _isConnecting = false;
        });
        _startTimer();
      }
    });

    _callStateSub = _callService.callStateStream.listen((state) {
      if (state == CallState.ended && mounted && !_isNavigatingAway) {
        _isNavigatingAway = true;
        Navigator.of(context).pop();
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _saveCallLog();
    _timer?.cancel();
    _remoteStreamSub?.cancel();
    _callStateSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    // Rilascia il wakelock quando si esce dalla chiamata
    try { WakelockPlus.disable(); } catch (_) {}
    super.dispose();
  }

  void _saveCallLog() {
    final status = _seconds > 0 ? CallStatus.completed : CallStatus.missed;
    CallLogService().saveEntry(CallLogEntry(
      id: const Uuid().v4(),
      contactId: widget.contactId,
      contactName: widget.contactName,
      callType: widget.isVideo ? CallType.video : CallType.audio,
      direction: widget.isOutgoing ? CallDirection.outgoing : CallDirection.incoming,
      status: status,
      durationSeconds: _seconds,
      startedAt: DateTime.now().subtract(Duration(seconds: _seconds)),
    ));
  }

  // ─── Controlli ────────────────────────────────────────────────────────────

  void _toggleMute() {
    _callService.toggleMute();
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleCamera() {
    _callService.toggleCamera();
    setState(() => _isCameraOff = !_isCameraOff);
  }

  void _toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    _callService.enableSpeaker(_isSpeakerOn).then((_) {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  void _switchCamera() => _callService.switchCamera();

  void _hangUp() {
    if (_isNavigatingAway) return;
    _isNavigatingAway = true;
    _callService.hangUp();
    if (mounted) Navigator.of(context).pop();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: widget.isVideo ? _buildVideoLayout() : _buildAudioLayout(),
    );
  }

  // ─── Layout audio ─────────────────────────────────────────────────────────

  Widget _buildAudioLayout() {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Info chiamata
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              children: [
                Text(
                  _isConnecting ? 'Connessione...' : _formatDuration(_seconds),
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 40),
                // Avatar
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _avatarColors(widget.contactName),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.contactName.isNotEmpty
                          ? widget.contactName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.contactName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
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
                      'DTLS-SRTP cifrato',
                      style: TextStyle(
                        color: AppConstants.success.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Controlli
          Padding(
            padding: const EdgeInsets.only(bottom: 56),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ControlButton(
                      icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      active: _isMuted,
                      onTap: _toggleMute,
                    ),
                    _ControlButton(
                      icon: _isSpeakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      label: 'Altoparlante',
                      active: _isSpeakerOn,
                      onTap: _toggleSpeaker,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                _EndCallButton(onTap: _hangUp),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Layout video ─────────────────────────────────────────────────────────

  Widget _buildVideoLayout() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video remoto (full screen)
        _isConnecting
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppConstants.primaryBlue),
                    const SizedBox(height: 16),
                    Text(
                      widget.isOutgoing
                          ? 'In attesa di risposta...'
                          : 'Connessione...',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              )
            : RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),

        // Overlay superiore: nome + timer
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.contactName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _isConnecting ? 'Connessione...' : _formatDuration(_seconds),
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          color: AppConstants.success.withValues(alpha: 0.9), size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'E2E',
                        style: TextStyle(
                          color: AppConstants.success.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // PiP video locale (in basso a destra)
        Positioned(
          bottom: 160,
          right: 16,
          child: GestureDetector(
            onTap: _switchCamera,
            child: Container(
              width: 100,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _isCameraOff
                    ? Container(
                        color: AppConstants.surfaceBlack,
                        child: const Icon(Icons.videocam_off_rounded,
                            color: Colors.white54),
                      )
                    : RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
              ),
            ),
          ),
        ),

        // Controlli in basso
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ControlButton(
                  icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  active: _isMuted,
                  small: true,
                  onTap: _toggleMute,
                ),
                _ControlButton(
                  icon: _isCameraOff
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  label: 'Camera',
                  active: _isCameraOff,
                  small: true,
                  onTap: _toggleCamera,
                ),
                _EndCallButton(onTap: _hangUp, small: true),
                _ControlButton(
                  icon: Icons.flip_camera_ios_rounded,
                  label: 'Cambia',
                  small: true,
                  onTap: _switchCamera,
                ),
                _ControlButton(
                  icon: _isSpeakerOn
                      ? Icons.volume_up_rounded
                      : Icons.volume_down_rounded,
                  label: 'Speaker',
                  active: _isSpeakerOn,
                  small: true,
                  onTap: _toggleSpeaker,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
}

// ─── Widget riutilizzabili ─────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool small;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.small = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = small ? 52.0 : 64.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            child: Icon(
              icon,
              color: active ? Colors.white : Colors.white70,
              size: small ? 22 : 26,
            ),
          ),
          if (!small) ...[
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool small;

  const _EndCallButton({required this.onTap, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 56.0 : 72.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFF3B30),
            ),
            child: Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: small ? 24 : 30,
            ),
          ),
          if (!small) ...[
            const SizedBox(height: 8),
            const Text(
              'Fine',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
