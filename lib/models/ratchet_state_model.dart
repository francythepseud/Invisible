import 'dart:convert';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Modello serializzabile per RatchetState
/// Usato per salvare lo stato del Double Ratchet nel database
class RatchetStateModel extends Equatable {
  final String id;
  final String conversationId;
  final String rootKey; // Base64 encoded
  final String? sendingChainKey; // Base64 encoded
  final String? receivingChainKey; // Base64 encoded
  final String ourRatchetPrivateKey; // Base64 encoded
  final String ourRatchetPublicKey; // Base64 encoded
  final String? theirRatchetPublicKey; // Base64 encoded
  final int sendCount;
  final int receiveCount;
  final int previousSendCount;
  final DateTime updatedAt;

  const RatchetStateModel({
    required this.id,
    required this.conversationId,
    required this.rootKey,
    this.sendingChainKey,
    this.receivingChainKey,
    required this.ourRatchetPrivateKey,
    required this.ourRatchetPublicKey,
    this.theirRatchetPublicKey,
    required this.sendCount,
    required this.receiveCount,
    required this.previousSendCount,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        conversationId,
        rootKey,
        sendingChainKey,
        receivingChainKey,
        ourRatchetPrivateKey,
        ourRatchetPublicKey,
        theirRatchetPublicKey,
        sendCount,
        receiveCount,
        previousSendCount,
        updatedAt,
      ];

  /// Crea RatchetStateModel da database row
  factory RatchetStateModel.fromMap(Map<String, dynamic> map) {
    return RatchetStateModel(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      rootKey: map['root_key'] as String,
      sendingChainKey: map['sending_chain_key'] as String?,
      receivingChainKey: map['receiving_chain_key'] as String?,
      ourRatchetPrivateKey: map['our_ratchet_private_key'] as String,
      ourRatchetPublicKey: map['our_ratchet_public_key'] as String,
      theirRatchetPublicKey: map['their_ratchet_public_key'] as String?,
      sendCount: map['send_count'] as int,
      receiveCount: map['receive_count'] as int,
      previousSendCount: map['previous_send_count'] as int,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Converte RatchetStateModel a database row
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'root_key': rootKey,
      'sending_chain_key': sendingChainKey,
      'receiving_chain_key': receivingChainKey,
      'our_ratchet_private_key': ourRatchetPrivateKey,
      'our_ratchet_public_key': ourRatchetPublicKey,
      'their_ratchet_public_key': theirRatchetPublicKey,
      'send_count': sendCount,
      'receive_count': receiveCount,
      'previous_send_count': previousSendCount,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Copia con modifiche
  RatchetStateModel copyWith({
    String? id,
    String? conversationId,
    String? rootKey,
    String? sendingChainKey,
    String? receivingChainKey,
    String? ourRatchetPrivateKey,
    String? ourRatchetPublicKey,
    String? theirRatchetPublicKey,
    int? sendCount,
    int? receiveCount,
    int? previousSendCount,
    DateTime? updatedAt,
  }) {
    return RatchetStateModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      rootKey: rootKey ?? this.rootKey,
      sendingChainKey: sendingChainKey ?? this.sendingChainKey,
      receivingChainKey: receivingChainKey ?? this.receivingChainKey,
      ourRatchetPrivateKey: ourRatchetPrivateKey ?? this.ourRatchetPrivateKey,
      ourRatchetPublicKey: ourRatchetPublicKey ?? this.ourRatchetPublicKey,
      theirRatchetPublicKey:
          theirRatchetPublicKey ?? this.theirRatchetPublicKey,
      sendCount: sendCount ?? this.sendCount,
      receiveCount: receiveCount ?? this.receiveCount,
      previousSendCount: previousSendCount ?? this.previousSendCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Helper: converte Uint8List a Base64
  static String bytesToBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }

  /// Helper: converte Base64 a Uint8List
  static Uint8List base64ToBytes(String base64String) {
    return base64Decode(base64String);
  }
}
