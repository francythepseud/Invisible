import 'package:equatable/equatable.dart';

/// Stato del messaggio
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

/// Tipo di messaggio
enum MessageType {
  text,
  image,
  video,
  audio,
  file,
}

/// Modello Messaggio
class Message extends Equatable {
  final String id;
  final String conversationId;
  final String senderId;
  final String ciphertext;
  final String messageHeader;
  final DateTime timestamp;
  final MessageStatus status;
  final MessageType type;
  final String? localPath;
  final bool isOutgoing;
  final String? decryptedText; // stored locally for display

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.ciphertext,
    required this.messageHeader,
    required this.timestamp,
    required this.status,
    this.type = MessageType.text,
    this.localPath,
    required this.isOutgoing,
    this.decryptedText,
  });

  @override
  List<Object?> get props => [
        id,
        conversationId,
        senderId,
        ciphertext,
        messageHeader,
        timestamp,
        status,
        type,
        localPath,
        isOutgoing,
        decryptedText,
      ];

  /// Crea Message da database row.
  /// [decryptedText] non è mai caricato dal DB (runtime-only, non persistito).
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      ciphertext: map['ciphertext'] as String,
      messageHeader: map['message_header'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.sent,
      ),
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      localPath: map['local_path'] as String?,
      isOutgoing: map['is_outgoing'] == 1,
      decryptedText: map['decrypted_text'] as String?,
    );
  }

  /// Converte Message a database row.
  /// [decryptedText] è escluso: il plaintext non viene mai scritto su disco.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'ciphertext': ciphertext,
      'message_header': messageHeader,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'type': type.name,
      'local_path': localPath,
      'is_outgoing': isOutgoing ? 1 : 0,
      'decrypted_text': decryptedText,
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? ciphertext,
    String? messageHeader,
    DateTime? timestamp,
    MessageStatus? status,
    MessageType? type,
    String? localPath,
    bool? isOutgoing,
    String? decryptedText,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      ciphertext: ciphertext ?? this.ciphertext,
      messageHeader: messageHeader ?? this.messageHeader,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      decryptedText: decryptedText ?? this.decryptedText,
    );
  }
}
