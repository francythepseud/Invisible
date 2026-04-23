import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:invisible/core/services/contact_service.dart';
import 'package:invisible/utils/constants.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final _contactService = ContactService();
  final _nameController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _isProcessing = true);
    _showAddContactDialog(raw);
  }

  /// Parsa il payload QR (JSON v2/v1 o legacy stringa plain)
  _QRPayload? _parseQR(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final v = json['v'] as int? ?? 0;
      if (v >= 1) {
        return _QRPayload(
          masterKey: json['mk'] as String,
          identityKey: json['ik'] as String?,
          signedPreKey: json['spk'] as String?,
          signedPreKeySig: json['sig'] as String?,
          opkPub: json['opk'] as String?,
          opkId: json['opki'] as int?,
        );
      }
    } catch (_) {
      // Formato legacy: la stringa intera è la chiave pubblica
      return _QRPayload(masterKey: raw);
    }
    return null;
  }

  Future<void> _showAddContactDialog(String raw) async {
    final payload = _parseQR(raw);
    if (payload == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR Code non valido'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
      setState(() => _isProcessing = false);
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi Contatto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined,
                    color: AppConstants.primaryBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    payload.identityKey != null && payload.signedPreKeySig != null
                        ? 'QR verificato con firma crittografica'
                        : 'QR scansionato (formato legacy)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppConstants.primaryBlue,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingLarge),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome contatto',
                hintText: 'Inserisci un nome',
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Inserisci un nome'),
                    backgroundColor: AppConstants.error,
                  ),
                );
                return;
              }
              try {
                await _contactService.addContact(
                  _nameController.text.trim(),
                  payload.masterKey,
                  identityKey: payload.identityKey,
                  signedPreKey: payload.signedPreKey,
                  signedPreKeySig: payload.signedPreKeySig,
                  opkPub: payload.opkPub,
                  opkId: payload.opkId,
                );
                if (context.mounted) Navigator.of(context).pop(true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: AppConstants.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scansiona QR Code')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppConstants.primaryBlue, width: 3),
                borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(AppConstants.paddingLarge),
              color: AppConstants.primaryBlack.withValues(alpha: 0.8),
              child: Text(
                'Inquadra il QR Code del contatto',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QRPayload {
  final String masterKey;
  final String? identityKey;
  final String? signedPreKey;
  final String? signedPreKeySig;
  final String? opkPub;
  final int? opkId;

  _QRPayload({
    required this.masterKey,
    this.identityKey,
    this.signedPreKey,
    this.signedPreKeySig,
    this.opkPub,
    this.opkId,
  });
}
