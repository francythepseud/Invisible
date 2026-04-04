import 'package:flutter/material.dart';
import 'package:invisible/core/services/call_service.dart';
import 'package:invisible/utils/constants.dart';

/// Schermata a tutto schermo mostrata quando arriva una chiamata in entrata.
/// Mostra avatar del chiamante, nome, tipo (audio/video) e i tasti Accetta/Rifiuta.
class IncomingCallScreen extends StatelessWidget {
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
                // Avatar
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _avatarColors(callInfo.callerName),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primaryBlue.withValues(alpha: 0.3),
                        blurRadius: 32,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      callInfo.callerName.isNotEmpty
                          ? callInfo.callerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  callInfo.callerName,
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
                      callInfo.isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: AppConstants.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      callInfo.isVideo
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
                // Indicatore E2E
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
                  // Rifiuta
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFFF3B30),
                    label: 'Rifiuta',
                    onTap: onReject,
                  ),
                  // Accetta
                  _CallButton(
                    icon: callInfo.isVideo
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: const Color(0xFF34C759),
                    label: 'Accetta',
                    onTap: onAccept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
