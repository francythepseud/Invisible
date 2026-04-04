
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invisible/core/network/invisible_client.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/core/services/session_service.dart';
import 'package:invisible/features/home/home_screen.dart';
import 'package:invisible/features/auth/screens/login_screen.dart';
import 'package:invisible/utils/constants.dart';

/// Schermata mostrata quando l'app non è ancora attivata dall'admin.
class NotActivatedScreen extends StatefulWidget {
  const NotActivatedScreen({super.key});

  @override
  State<NotActivatedScreen> createState() => _NotActivatedScreenState();
}

class _NotActivatedScreenState extends State<NotActivatedScreen> {
  String? _activationCode;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  Future<void> _retry() async {
    setState(() => _checking = true);
    // Forza una connessione fresca al relay per ri-verificare la whitelist
    await InvisibleClient().disconnect();
    InvisibleClient().connect(AppConstants.relayWsUrl).catchError((_) {});
    bool activated = false;
    try {
      await InvisibleClient().statusStream
          .firstWhere((s) => s == RelayStatus.connected)
          .timeout(const Duration(seconds: 10));
      activated = true;
    } catch (_) {
      activated = false;
    }
    if (!mounted) return;
    if (activated) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Non ancora attivato'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: const Text('Elimina profilo', style: TextStyle(color: AppConstants.textPrimary)),
        content: const Text(
          'Vuoi eliminare il profilo e tornare alla schermata di login?',
          style: TextStyle(color: AppConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await SessionService().endSession();
    } catch (_) {}
    try {
      await ProfileService().deleteCurrentProfile();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _loadCode() async {
    final keys = await ProfileService().getCurrentCryptoKeys();
    if (keys == null) return;
    final k = keys.identityKeyPublic;
    setState(() {
      _activationCode = k.length > 32 ? k.substring(k.length - 32) : k;
    });
  }

  void _copyCode() {
    if (_activationCode == null) return;
    Clipboard.setData(ClipboardData(text: _activationCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Codice copiato negli appunti'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.paddingLarge),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.primaryBlue.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppConstants.primaryBlue.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primaryBlue.withValues(alpha: 0.2),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_clock_outlined,
                    size: 48,
                    color: AppConstants.primaryBlue,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'App non attivata',
                  style: TextStyle(
                    color: AppConstants.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Subtitle
                const Text(
                  'Il tuo account non è ancora stato abilitato.\nCondividi il codice qui sotto con l\'amministratore per ricevere l\'accesso.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // Activation code card
                if (_activationCode != null) ...[
                  const Text(
                    'CODICE ATTIVAZIONE',
                    style: TextStyle(
                      color: AppConstants.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.paddingMedium,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.surfaceBlack,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                      border: Border.all(
                        color: AppConstants.primaryBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _activationCode!,
                            style: const TextStyle(
                              color: AppConstants.primaryBlue,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _copyCode,
                          child: const Icon(
                            Icons.copy,
                            size: 18,
                            color: AppConstants.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _checking ? null : _retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                      ),
                    ),
                    child: _checking
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verifica attivazione', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _checking ? null : _deleteProfile,
                  child: const Text(
                    'Elimina profilo',
                    style: TextStyle(color: AppConstants.textTertiary, fontSize: 13),
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
