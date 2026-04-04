import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invisible/models/contact.dart';
import 'package:invisible/core/services/contact_service.dart';
import 'package:invisible/core/services/conversation_service.dart';
import 'package:invisible/core/services/call_service.dart';
import 'package:invisible/features/chat/screens/chat_screen.dart';
import 'package:invisible/features/calls/screens/call_screen.dart';
import 'package:invisible/utils/constants.dart';

class ContactDetailScreen extends StatefulWidget {
  final Contact contact;
  const ContactDetailScreen({super.key, required this.contact});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  final _contactService = ContactService();
  final _conversationService = ConversationService();
  final _callService = CallService();
  bool _isOpeningChat = false;
  bool _isCalling = false;
  bool _showKeys = false;

  List<Color> _avatarColors(String initial) {
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

  Future<void> _startCall({required bool isVideo}) async {
    if (_isCalling) return;
    setState(() => _isCalling = true);
    try {
      final ok = await _callService.initiateCall(widget.contact, isVideo: isVideo);
      if (!mounted) return;
      if (ok) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CallScreen(
            contactName: widget.contact.name,
            isVideo: isVideo,
            isOutgoing: true,
          ),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossibile avviare la chiamata'),
          backgroundColor: AppConstants.error,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Errore: $e'),
        backgroundColor: AppConstants.error,
      ));
    } finally {
      if (mounted) setState(() => _isCalling = false);
    }
  }

  Future<void> _openChat() async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      final conversation = await _conversationService.getOrCreateConversation(widget.contact);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Errore: $e'),
        backgroundColor: AppConstants.error,
      ));
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _deleteContact() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina contatto'),
        content: Text('Eliminare ${widget.contact.name}? Tutte le conversazioni saranno rimosse.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: AppConstants.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _contactService.deleteContact(widget.contact.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Errore: $e'),
        backgroundColor: AppConstants.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.contact.name;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final colors = _avatarColors(initial);
    final addedDate = '${widget.contact.createdAt.day}/${widget.contact.createdAt.month}/${widget.contact.createdAt.year}';

    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        backgroundColor: AppConstants.backgroundBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Contatto'),
        actions: [
          TextButton(
            onPressed: _deleteContact,
            child: const Text('Elimina', style: TextStyle(color: AppConstants.error, fontSize: 15)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Avatar + nome ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors[0].withValues(alpha: 0.25), Colors.transparent],
                      ),
                      border: Border.all(
                        color: colors[0].withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors[0].withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(6),
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
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Aggiunto il $addedDate',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppConstants.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottoni azione stile iPhone ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _ActionBtn(
                    icon: _isOpeningChat
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryBlue),
                          )
                        : const Icon(Icons.message_rounded, color: AppConstants.primaryBlue, size: 24),
                    label: 'Messaggio',
                    color: AppConstants.primaryBlue,
                    onTap: (_isOpeningChat || _isCalling) ? null : _openChat,
                  ),
                  const SizedBox(width: 10),
                  _ActionBtn(
                    icon: const Icon(Icons.call_rounded, color: Color(0xFF34C759), size: 24),
                    label: 'Chiama',
                    color: const Color(0xFF34C759),
                    onTap: (_isOpeningChat || _isCalling) ? null : () => _startCall(isVideo: false),
                  ),
                  const SizedBox(width: 10),
                  _ActionBtn(
                    icon: const Icon(Icons.videocam_rounded, color: Color(0xFFBB86FC), size: 24),
                    label: 'Video',
                    color: const Color(0xFFBB86FC),
                    onTap: (_isOpeningChat || _isCalling) ? null : () => _startCall(isVideo: true),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Sezione sicurezza ────────────────────────────────────────────
            _SectionHeader(label: 'SICUREZZA'),
            _InfoCard(children: [
              _KeyRow(
                icon: Icons.shield_rounded,
                label: 'Crittografia end-to-end',
                value: 'Signal Protocol (X3DH + Double Ratchet)',
                iconColor: AppConstants.success,
              ),
              if (widget.contact.signedPreKeySig != null) ...[
                const _Divider(),
                _KeyRow(
                  icon: Icons.verified_rounded,
                  label: 'Firma SPK verificata',
                  value: 'Chiave autenticata con Ed25519',
                  iconColor: AppConstants.success,
                ),
              ],
            ]),

            const SizedBox(height: 16),

            // ── Sezione chiavi (collassabile) ────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _showKeys = !_showKeys),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const Text(
                      'CHIAVI CRITTOGRAFICHE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.textTertiary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '(pubbliche)',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppConstants.textTertiary.withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showKeys ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: AppConstants.textTertiary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_showKeys)
              _InfoCard(children: [
                _KeyRow(
                  icon: Icons.vpn_key_rounded,
                  label: 'Master Key (X25519)',
                  value: widget.contact.publicKey,
                  copyable: true,
                  onCopy: () => _copy(widget.contact.publicKey, 'Master Key'),
                ),
                if (widget.contact.identityKey != null) ...[
                  const _Divider(),
                  _KeyRow(
                    icon: Icons.fingerprint_rounded,
                    label: 'Identity Key (Ed25519)',
                    value: widget.contact.identityKey!,
                    copyable: true,
                    onCopy: () => _copy(widget.contact.identityKey!, 'Identity Key'),
                  ),
                ],
                if (widget.contact.signedPreKey != null) ...[
                  const _Divider(),
                  _KeyRow(
                    icon: Icons.lock_rounded,
                    label: 'Signed Pre-Key (X25519)',
                    value: widget.contact.signedPreKey!,
                    copyable: true,
                    verified: widget.contact.signedPreKeySig != null,
                    onCopy: () => _copy(widget.contact.signedPreKey!, 'Signed Pre-Key'),
                  ),
                ],
              ]),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copiata'),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// ── Bottone azione glassmorphism + glow ──────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
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

// ── Card con sfondo leggermente elevato ─────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceBlack,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }
}

// ── Header sezione ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppConstants.textTertiary,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

// ── Divider sottile ──────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 0.5, color: AppConstants.divider, indent: 48);
  }
}

// ── Riga chiave ──────────────────────────────────────────────────────────────

class _KeyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final bool copyable;
  final bool verified;
  final VoidCallback? onCopy;

  const _KeyRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = AppConstants.textTertiary,
    this.copyable = false,
    this.verified = false,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final truncated = value.length > 32
        ? '${value.substring(0, 16)}…${value.substring(value.length - 8)}'
        : value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppConstants.textTertiary,
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, size: 12, color: AppConstants.success),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  truncated,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppConstants.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: onCopy,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.copy_rounded, size: 17, color: AppConstants.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}
