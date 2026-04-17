import 'dart:async';
import 'package:flutter/material.dart';
import 'package:invisible/core/services/conversation_service.dart';
import 'package:invisible/core/services/contact_service.dart';
import 'package:invisible/core/services/session_service.dart';
import 'package:invisible/models/conversation.dart';
import 'package:invisible/models/contact.dart';
import 'package:invisible/features/chat/screens/chat_screen.dart';
import 'package:invisible/utils/constants.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _conversationService = ConversationService();
  final _contactService = ContactService();

  List<Conversation> _conversations = [];
  bool _isLoading = true;
  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    // Aggiorna i badge in real-time quando arrivano messaggi
    _msgSubscription = SessionService().anyMessageStream.listen((_) {
      _loadConversations();
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final conversations = await _conversationService.getConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startNewConversation() async {
    final contacts = await _contactService.getContacts();

    if (!mounted) return;

    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aggiungi prima un contatto'),
          backgroundColor: AppConstants.warning,
        ),
      );
      return;
    }

    final selectedContact = await showModalBottomSheet<Contact>(
      context: context,
      backgroundColor: AppConstants.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildContactSelector(contacts),
    );

    if (selectedContact != null && mounted) {
      final conversation = await _conversationService.getOrCreateConversation(
        selectedContact,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversation: conversation),
          ),
        ).then((_) => _loadConversations());
      }
    }
  }

  Widget _buildContactSelector(List<Contact> contacts) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppConstants.textTertiary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              const Text(
                'Nuova chat',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final initial = contact.name.isNotEmpty
                  ? contact.name[0].toUpperCase()
                  : '?';
              return ListTile(
                leading: _buildAvatar(initial, contact.name),
                title: Text(
                  contact.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppConstants.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Cifrato end-to-end',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppConstants.success,
                  ),
                ),
                onTap: () => Navigator.pop(context, contact),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceBlack,
        elevation: 0,
        title: const Text(
          'Chat',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  color: AppConstants.primaryBlue,
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      return _buildConversationTile(_conversations[index]);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewConversation,
        backgroundColor: AppConstants.primaryBlue,
        child: const Icon(Icons.chat_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppConstants.primaryBlue.withValues(alpha: 0.3),
                    AppConstants.primaryBlue.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: AppConstants.primaryBlue.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Nessuna chat',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tocca + per iniziare una conversazione cifrata',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    final name = conversation.contactName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hasUnread = conversation.unreadCount > 0;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversation: conversation),
          ),
        ).then((_) => _loadConversations());
      },
      onLongPress: () => _showConversationOptions(conversation),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildAvatar(initial, name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppConstants.textPrimary,
                          ),
                        ),
                      ),
                      if (conversation.lastMessageTime != null)
                        Text(
                          _formatDate(conversation.lastMessageTime!),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread
                                ? AppConstants.primaryBlue
                                : AppConstants.textTertiary,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_rounded,
                        size: 11,
                        color: AppConstants.success,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          conversation.lastMessageText ?? 'Chat cifrata',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: hasUnread
                                ? AppConstants.textPrimary
                                : AppConstants.textSecondary,
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            conversation.unreadCount > 99
                                ? '99+'
                                : conversation.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String initial, String name) {
    final colors = _avatarColors(initial);
    return Container(
      width: 50,
      height: 50,
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
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static const _gradients = [
    [Color(0xFF2196F3), Color(0xFF0D47A1)],
    [Color(0xFF9C27B0), Color(0xFF4A148C)],
    [Color(0xFF00BCD4), Color(0xFF006064)],
    [Color(0xFF4CAF50), Color(0xFF1B5E20)],
    [Color(0xFFFF5722), Color(0xFFBF360C)],
    [Color(0xFFE91E63), Color(0xFF880E4F)],
    [Color(0xFF607D8B), Color(0xFF263238)],
    [Color(0xFFFF9800), Color(0xFFE65100)],
  ];

  List<Color> _avatarColors(String initial) {
    final idx = initial.codeUnitAt(0) % _gradients.length;
    return _gradients[idx];
  }

  void _showConversationOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppConstants.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppConstants.error),
              title: const Text('Elimina chat',
                  style: TextStyle(color: AppConstants.error)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppConstants.surfaceBlack,
                    title: const Text('Elimina chat'),
                    content: Text(
                      'Eliminare la conversazione con ${conversation.contactName}? '
                      'Tutti i messaggi verranno cancellati.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Annulla'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                            foregroundColor: AppConstants.error),
                        child: const Text('Elimina'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _conversationService.deleteConversation(conversation.id);
                  _loadConversations();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Ieri';
    } else if (diff.inDays < 7) {
      const days = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
      return days[date.weekday - 1];
    } else {
      return '${date.day}/${date.month}';
    }
  }
}
