import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invisible/core/crypto/safety_numbers.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/contact.dart';
import 'package:invisible/utils/constants.dart';

/// Schermata Safety Numbers — verifica dell'identità del contatto.
///
/// Mostra un fingerprint a 60 cifre (12 gruppi da 5) derivato dalle chiavi
/// pubbliche di entrambi i partecipanti. Se il numero è identico su entrambi
/// i dispositivi, la comunicazione è autentica e non intercettata.
class SafetyNumbersScreen extends StatefulWidget {
  final Contact contact;

  const SafetyNumbersScreen({super.key, required this.contact});

  @override
  State<SafetyNumbersScreen> createState() => _SafetyNumbersScreenState();
}

class _SafetyNumbersScreenState extends State<SafetyNumbersScreen> {
  final _profileService = ProfileService();
  String? _safetyNumber;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null || widget.contact.identityKey == null) {
      setState(() => _loading = false);
      return;
    }
    final sn = SafetyNumbers.generate(
      myIdentityKeyBase64: keys.identityKeyPublic,
      theirIdentityKeyBase64: widget.contact.identityKey!,
    );
    setState(() {
      _safetyNumber = sn;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Verifica identità — ${widget.contact.name}'),
        actions: [
          if (_safetyNumber != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copia Safety Number',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _safetyNumber!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Safety Number copiato'),
                    backgroundColor: AppConstants.success,
                  ),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _safetyNumber == null
              ? _buildUnavailable(context)
              : _buildContent(context),
    );
  }

  Widget _buildUnavailable(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_rounded,
                color: AppConstants.warning, size: 48),
            const SizedBox(height: AppConstants.paddingMedium),
            Text(
              'Safety Number non disponibile',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.paddingSmall),
            Text(
              'Il contatto non ha ancora condiviso la sua chiave identità. '
              'Chiedi di aggiornare il QR Code.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppConstants.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final groups = _safetyNumber!.split(' ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.paddingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Spiegazione
          Container(
            padding: const EdgeInsets.all(AppConstants.paddingMedium),
            decoration: BoxDecoration(
              color: AppConstants.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              border: Border.all(
                  color: AppConstants.primaryBlue.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined,
                    color: AppConstants.primaryBlue, size: 20),
                const SizedBox(width: AppConstants.paddingSmall),
                Expanded(
                  child: Text(
                    'Confronta questo numero con quello di ${widget.contact.name} '
                    'tramite un canale sicuro (di persona, telefonata vocale). '
                    'Se i numeri coincidono, la comunicazione è autentica.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppConstants.paddingXLarge),

          // Griglia Safety Number
          Container(
            padding: const EdgeInsets.all(AppConstants.paddingLarge),
            decoration: BoxDecoration(
              color: AppConstants.surfaceBlack,
              borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
              border: Border.all(color: AppConstants.divider),
            ),
            child: Column(
              children: [
                Text(
                  widget.contact.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppConstants.textSecondary,
                      ),
                ),
                const SizedBox(height: AppConstants.paddingLarge),
                _buildNumberGrid(context, groups),
              ],
            ),
          ),

          const SizedBox(height: AppConstants.paddingXLarge),

          // Pulsante "Ho verificato"
          ElevatedButton.icon(
            icon: const Icon(Icons.verified_user_rounded),
            label: const Text('Ho verificato — identità confermata'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Identità di ${widget.contact.name} verificata ✓'),
                  backgroundColor: AppConstants.success,
                ),
              );
              Navigator.of(context).pop();
            },
          ),

          const SizedBox(height: AppConstants.paddingMedium),

          // Pulsante "Non coincide"
          OutlinedButton.icon(
            icon: const Icon(Icons.warning_rounded,
                color: AppConstants.error),
            label: const Text('I numeri non coincidono',
                style: TextStyle(color: AppConstants.error)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppConstants.error),
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
            ),
            onPressed: () => _showMismatchWarning(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberGrid(BuildContext context, List<String> groups) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppConstants.paddingMedium,
      runSpacing: AppConstants.paddingMedium,
      children: groups.map((g) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.paddingMedium,
            vertical: AppConstants.paddingSmall,
          ),
          decoration: BoxDecoration(
            color: AppConstants.cardBlack,
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(
                color: AppConstants.primaryBlue.withValues(alpha: 0.4)),
          ),
          child: Text(
            g,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                  color: AppConstants.primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
          ),
        );
      }).toList(),
    );
  }

  void _showMismatchWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attenzione — MITM possibile'),
        content: Text(
          'Se i Safety Numbers non coincidono, qualcuno potrebbe star '
          'intercettando la tua comunicazione con ${widget.contact.name}. '
          'Smetti di inviare messaggi sensibili e verifica il contatto da capo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Capito'),
          ),
        ],
      ),
    );
  }
}
