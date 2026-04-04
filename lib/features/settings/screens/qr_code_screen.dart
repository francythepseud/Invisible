import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/utils/constants.dart';

class QRCodeScreen extends StatefulWidget {
  const QRCodeScreen({super.key});

  @override
  State<QRCodeScreen> createState() => _QRCodeScreenState();
}

class _QRCodeScreenState extends State<QRCodeScreen> {
  final _profileService = ProfileService();
  String? _qrData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _buildQrData();
  }

  Future<void> _buildQrData() async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) {
      setState(() => _loading = false);
      return;
    }
    // Payload QR: chiavi pubbliche per X3DH + firma SPK
    // v   = versione protocollo
    // mk  = master key X25519 (DH identity key)
    // ik  = identity key Ed25519 (firma/auth)
    // spk = signed pre-key X25519 (chiave DH separata per X3DH)
    // sig = firma Ed25519 della spk (prova di proprietà)
    final payload = jsonEncode({
      'v': 1,
      'mk': keys.masterKeyPublic,
      'ik': keys.identityKeyPublic,
      'spk': keys.signedPreKeyPublic,
      'sig': keys.signedPreKeySignature,
    });
    setState(() {
      _qrData = payload;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profileService.currentProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Il Mio QR Code'),
        actions: [
          if (_qrData != null) ...[
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'Condividi chiave',
              onPressed: () {
                Share.share(
                  _qrData!,
                  subject: 'Invisible — Chiave di contatto',
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copia chiave',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _qrData!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chiave copiata negli appunti'),
                    backgroundColor: AppConstants.success,
                  ),
                );
              },
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profile == null || _qrData == null
              ? const Center(child: Text('Profilo non disponibile'))
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppConstants.paddingLarge),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          profile.username,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: AppConstants.paddingSmall),
                        Text(
                          'Fai scansionare per aggiungere il tuo contatto',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppConstants.paddingXLarge),

                        Container(
                          padding: const EdgeInsets.all(AppConstants.paddingLarge),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
                            boxShadow: [
                              BoxShadow(
                                color: AppConstants.primaryBlue.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: _qrData!,
                            version: QrVersions.auto,
                            size: 260,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                          ),
                        ),

                        const SizedBox(height: AppConstants.paddingXLarge),

                        Container(
                          padding: const EdgeInsets.all(AppConstants.paddingMedium),
                          decoration: BoxDecoration(
                            color: AppConstants.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                            border: Border.all(
                              color: AppConstants.primaryBlue.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.shield_outlined,
                                  color: AppConstants.primaryBlue),
                              const SizedBox(width: AppConstants.paddingMedium),
                              Expanded(
                                child: Text(
                                  'Puoi condividere questa chiave via SMS, WhatsApp o email — contiene solo le tue chiavi pubbliche crittografiche. Nessuna informazione privata.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
