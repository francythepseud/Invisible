import 'package:flutter/material.dart';
import 'package:invisible/core/services/conversation_service.dart';
import 'package:invisible/core/services/contact_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final conversations = await _conversationService.getConversations();
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startNewConversation() async {
    // Mostra lista contatti per selezionare
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
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingMedium),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seleziona contatto',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppConstants.paddingMedium),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppConstants.primaryBlue,
                    child: Text(
                      contact.name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(contact.name),
                  onTap: () => Navigator.pop(context, contact),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Cerca chat
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadConversations,
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
        child: const Icon(Icons.chat, color: Colors.white),
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
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: AppConstants.textTertiary,
            ),
            const SizedBox(height: AppConstants.paddingLarge),
            Text(
              'Nessuna chat',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppConstants.paddingSmall),
            Text(
              'Tocca + per iniziare una nuova conversazione crittografata',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppConstants.primaryBlue,
        radius: 24,
        child: Text(
          conversation.contactName[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.contactName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (conversation.lastMessageTime != null)
            Text(
              _formatDate(conversation.lastMessageTime!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      subtitle: Row(
        children: [
          const Icon(
            Icons.lock,
            size: 12,
            color: AppConstants.success,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              conversation.lastMessageText ?? 'Chat crittografata',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: conversation.unreadCount > 0
                    ? AppConstants.textPrimary
                    : AppConstants.textSecondary,
              ),
            ),
          ),
          if (conversation.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                conversation.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversation: conversation),
          ),
        ).then((_) => _loadConversations());
      },
      onLongPress: () {
        _showConversationOptions(conversation);
      },
    );
  }

  void _showConversationOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: AppConstants.error),
              title: const Text('Elimina chat'),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
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
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.error,
                        ),
                        child: const Text('Elimina'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await _conversationService.deleteConversation(
                    conversation.id,
                  );
                  _loadConversations();
                }
              },
            ),
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
