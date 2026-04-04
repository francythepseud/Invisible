import 'package:equatable/equatable.dart';

/// Modello Conversazione
/// Rappresenta una conversazione 1-a-1 con un contatto
class Conversation extends Equatable {
  final String id;
  final String contactId;
  final String contactName;
  final String contactPublicKey;
  final String? lastMessageText;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final String? ratchetStateId; // Reference to stored ratchet state
  final DateTime createdAt;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.contactId,
    required this.contactName,
    required this.contactPublicKey,
    this.lastMessageText,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.ratchetStateId,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        contactId,
        contactName,
        contactPublicKey,
        lastMessageText,
        lastMessageTime,
        unreadCount,
        ratchetStateId,
        createdAt,
        updatedAt,
      ];

  /// Crea Conversation da database row
  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      contactId: map['contact_id'] as String,
      contactName: map['contact_name'] as String,
      contactPublicKey: map['contact_public_key'] as String,
      lastMessageText: map['last_message_text'] as String?,
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.parse(map['last_message_time'] as String)
          : null,
      unreadCount: map['unread_count'] as int? ?? 0,
      ratchetStateId: map['ratchet_state_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Converte Conversation a database row
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contact_id': contactId,
      'contact_name': contactName,
      'contact_public_key': contactPublicKey,
      'last_message_text': lastMessageText,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
      'ratchet_state_id': ratchetStateId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Copia con modifiche
  Conversation copyWith({
    String? id,
    String? contactId,
    String? contactName,
    String? contactPublicKey,
    String? lastMessageText,
    DateTime? lastMessageTime,
    int? unreadCount,
    String? ratchetStateId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      contactPublicKey: contactPublicKey ?? this.contactPublicKey,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      ratchetStateId: ratchetStateId ?? this.ratchetStateId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
