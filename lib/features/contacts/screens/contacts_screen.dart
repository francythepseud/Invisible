import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invisible/core/services/contact_service.dart';
import 'package:invisible/core/services/presence_service.dart';
import 'package:invisible/models/contact.dart';
import 'package:invisible/utils/constants.dart';
import 'qr_scanner_screen.dart';
import 'contact_detail_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _contactService = ContactService();
  final _presenceService = PresenceService();
  StreamSubscription<String>? _presenceSub;
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _presenceSub = _presenceService.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final contacts = await _contactService.getContacts();
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore caricamento: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _openQRScanner() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (result == true) {
      await _loadContacts();
    }
  }

  void _showAddContactSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aggiungi Contatto',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
              const SizedBox(height: AppConstants.paddingSmall),
              const Text(
                'Scegli come aggiungere il contatto',
                style: TextStyle(color: AppConstants.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: AppConstants.paddingLarge),
              _SheetOption(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scansiona QR Code',
                subtitle: 'Inquadra il QR del contatto',
                onTap: () {
                  Navigator.pop(ctx);
                  _openQRScanner();
                },
              ),
              const SizedBox(height: AppConstants.paddingMedium),
              _SheetOption(
                icon: Icons.content_paste_rounded,
                title: 'Incolla chiave',
                subtitle: 'Ricevuta via SMS o messaggio',
                onTap: () {
                  Navigator.pop(ctx);
                  _showPasteKeyDialog();
                },
              ),
              const SizedBox(height: AppConstants.paddingMedium),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPasteKeyDialog() async {
    // Leggi clipboard PRIMA di aprire il dialog
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clip?.text ?? '';
    if (!mounted) return;

    // Il dialog fa SOLO lavoro sincrono: raccoglie nome + JSON e li restituisce.
    // Nessun await dentro il dialog → nessun problema con _dependents.isEmpty.
    final data = await showDialog<_PasteKeyData>(
      context: context,
      builder: (ctx) => _PasteKeyDialog(initialKey: clipText),
    );

    if (data == null || !mounted) return;

    // Operazione async nel parent, con context sempre valido
    try {
      await _contactService.addContact(
        data.name,
        data.masterKey,
        identityKey: data.identityKey,
        signedPreKey: data.signedPreKey,
        signedPreKeySig: data.signedPreKeySig,
      );
      if (mounted) await _loadContacts();
    } catch (e) {
      if (mounted) {
        final msg = '$e'.replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppConstants.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceBlack,
        elevation: 0,
        title: const Text(
          'Contatti',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            onPressed: _showAddContactSheet,
            tooltip: 'Aggiungi contatto',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? _buildEmptyState()
              : _buildContactsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingXLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 50,
                color: AppConstants.primaryBlue,
              ),
            ),
            const SizedBox(height: AppConstants.paddingLarge),
            const Text(
              'Nessun contatto',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.paddingSmall),
            const Text(
              'Scansiona il QR Code di un contatto\nper aggiungerlo in modo sicuro',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppConstants.textTertiary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppConstants.paddingXLarge),
            ElevatedButton.icon(
              onPressed: _openQRScanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text(
                'Scansiona QR Code',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    return RefreshIndicator(
      onRefresh: _loadContacts,
      color: AppConstants.primaryBlue,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _contacts.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          color: AppConstants.divider,
          indent: 72,
        ),
        itemBuilder: (context, index) => _buildContactTile(_contacts[index]),
      ),
    );
  }

  Widget _buildContactTile(Contact contact) {
    final initial =
        contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?';
    final colors = _avatarGradient(initial);
    final online = _presenceService.isOnline(contact);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (online)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: AppConstants.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppConstants.backgroundBlack,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        contact.name,
        style: const TextStyle(
          color: AppConstants.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        online ? 'Online' : 'Aggiunto ${_relativeDate(contact.createdAt)}',
        style: TextStyle(
          color: online ? AppConstants.success : AppConstants.textTertiary,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppConstants.textTertiary,
      ),
      onTap: () async {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => ContactDetailScreen(contact: contact),
          ),
        );
        if (result == true) await _loadContacts();
      },
    );
  }

  List<Color> _avatarGradient(String initial) {
    const gradients = [
      [Color(0xFF2196F3), Color(0xFF0D47A1)],
      [Color(0xFF9C27B0), Color(0xFF4A148C)],
      [Color(0xFF00BCD4), Color(0xFF006064)],
      [Color(0xFF4CAF50), Color(0xFF1B5E20)],
      [Color(0xFFFF5722), Color(0xFFBF360C)],
      [Color(0xFFE91E63), Color(0xFF880E4F)],
      [Color(0xFF607D8B), Color(0xFF263238)],
    ];
    return gradients[initial.codeUnitAt(0) % gradients.length];
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'oggi';
    if (diff.inDays == 1) return 'ieri';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        decoration: BoxDecoration(
          color: AppConstants.cardBlack,
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          border: Border.all(color: AppConstants.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              ),
              child: Icon(icon, color: AppConstants.primaryBlue, size: 22),
            ),
            const SizedBox(width: AppConstants.paddingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppConstants.textPrimary, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: AppConstants.textTertiary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppConstants.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Dati restituiti dal dialog (solo sync, no async) ────────────────────────

class _PasteKeyData {
  final String name;
  final String masterKey;
  final String? identityKey;
  final String? signedPreKey;
  final String? signedPreKeySig;

  const _PasteKeyData({
    required this.name,
    required this.masterKey,
    this.identityKey,
    this.signedPreKey,
    this.signedPreKeySig,
  });
}

// ─── Dialog che raccoglie nome + chiave (tutto sincrono, nessun await) ────────

class _PasteKeyDialog extends StatefulWidget {
  final String initialKey;
  const _PasteKeyDialog({required this.initialKey});

  @override
  State<_PasteKeyDialog> createState() => _PasteKeyDialogState();
}

class _PasteKeyDialogState extends State<_PasteKeyDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _keyCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _keyCtrl = TextEditingController(text: widget.initialKey);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final raw = _keyCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Inserisci un nome');
      return;
    }
    if (raw.isEmpty) {
      setState(() => _error = 'Incolla la chiave nel campo sottostante');
      return;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      setState(() => _error = 'Formato non valido — deve essere il JSON ricevuto via QR/SMS');
      return;
    }

    if ((json['v'] as int? ?? 0) < 1 || json['mk'] == null) {
      setState(() => _error = 'Chiave incompleta — manca il campo "mk"');
      return;
    }

    // Tutto OK: restituiamo i dati al parent (nessun await qui)
    Navigator.pop(
      context,
      _PasteKeyData(
        name: name,
        masterKey: json['mk'] as String,
        identityKey: json['ik'] as String?,
        signedPreKey: json['spk'] as String?,
        signedPreKeySig: json['sig'] as String?,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppConstants.surfaceBlack,
      title: const Text('Incolla chiave contatto'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome contatto',
              hintText: 'Come vuoi chiamarlo?',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
          ),
          const SizedBox(height: AppConstants.paddingMedium),
          TextField(
            controller: _keyCtrl,
            decoration: InputDecoration(
              labelText: 'Chiave (JSON)',
              hintText: 'Incolla qui la chiave ricevuta',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _keyCtrl,
                builder: (_, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        tooltip: 'Cancella',
                        onPressed: () {
                          _keyCtrl.clear();
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
              ),
            ),
            maxLines: 3,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline, color: AppConstants.error, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppConstants.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Aggiungi'),
        ),
      ],
    );
  }
}
