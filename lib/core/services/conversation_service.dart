import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:invisible/core/crypto/crypto_service.dart';
import 'package:invisible/core/crypto/x3dh.dart';
import 'package:invisible/core/crypto/double_ratchet.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/conversation.dart';
import 'package:invisible/models/contact.dart';
import 'package:invisible/models/ratchet_state_model.dart';

/// Servizio per la gestione delle conversazioni
class ConversationService {
  static final ConversationService _instance = ConversationService._internal();
  factory ConversationService() => _instance;
  ConversationService._internal();

  final _profileService = ProfileService();
  final _cryptoService = CryptoService();
  final _x3dh = X3DH();
  final _doubleRatchet = DoubleRatchet();

  /// Ottiene il database corrente
  Database get _db {
    final db = _profileService.currentDatabase;
    if (db == null) {
      throw Exception('No active profile session');
    }
    return db;
  }

  /// Ottiene tutte le conversazioni ordinate per ultimo messaggio
  Future<List<Conversation>> getConversations() async {
    final maps = await _db.query(
      'conversations',
      orderBy: 'last_message_time DESC',
    );
    return maps.map((map) => Conversation.fromMap(map)).toList();
  }

  /// Ottiene una conversazione specifica
  Future<Conversation?> getConversation(String id) async {
    final maps = await _db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Conversation.fromMap(maps.first);
  }

  /// Ottiene o crea una conversazione con un contatto
  Future<Conversation> getOrCreateConversation(Contact contact) async {
    // Cerca conversazione esistente
    final maps = await _db.query(
      'conversations',
      where: 'contact_id = ?',
      whereArgs: [contact.id],
    );

    if (maps.isNotEmpty) {
      return Conversation.fromMap(maps.first);
    }

    // Crea nuova conversazione
    final conversation = Conversation(
      id: _cryptoService.generateId(),
      contactId: contact.id,
      contactName: contact.name,
      contactPublicKey: contact.publicKey,
      unreadCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _db.insert('conversations', conversation.toMap());
    return conversation;
  }

  /// Inizializza sessione crittografica come mittente.
  /// Esegue X3DH con chiavi separate (masterKey come DH identity,
  /// signedPreKey come SPK distinta) poi inizializza Double Ratchet.
  Future<RatchetState> initializeSession({
    required String conversationId,
    required String theirPublicKeyBase64,
    String? theirSignedPreKeyBase64,
  }) async {
    final keysMaps = await _db.query('crypto_keys');
    if (keysMaps.isEmpty) throw Exception('No crypto keys found');
    final keysMap = keysMaps.first;

    // Master key X25519 come long-term DH identity key
    final myIdentityKeyPair = await _generateKeyPairFromBytes(
      base64Decode(keysMap['master_key_private'] as String),
      base64Decode(keysMap['master_key_public'] as String),
    );

    // Identity pubkey del destinatario (X25519 master key)
    final theirIdentityKey = SimplePublicKey(
      base64Decode(theirPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    // Usa la signed pre-key separata del contatto se disponibile,
    // altrimenti fall-back alla master key (compatibilità con vecchi contatti)
    final theirSpkBytes = theirSignedPreKeyBase64 != null
        ? base64Decode(theirSignedPreKeyBase64)
        : base64Decode(theirPublicKeyBase64);
    final theirSignedPreKey = SimplePublicKey(
      theirSpkBytes,
      type: KeyPairType.x25519,
    );

    final x3dhResult = await _x3dh.performAsInitiator(
      myIdentityKey: myIdentityKeyPair,
      theirIdentityKey: theirIdentityKey,
      theirSignedPreKey: theirSignedPreKey,
    );

    final ratchetState = await _doubleRatchet.initializeAsSender(
      sharedSecret: x3dhResult.sharedSecret,
      theirRatchetPublicKey: theirSignedPreKey,
    );

    await _saveRatchetState(conversationId, ratchetState);
    return ratchetState;
  }

  /// Carica stato ratchet dal database
  Future<RatchetState?> loadRatchetState(String conversationId) async {
    final maps = await _db.query(
      'ratchet_states',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    if (maps.isEmpty) return null;

    final model = RatchetStateModel.fromMap(maps.first);
    return await _ratchetStateFromModel(model);
  }

  /// Salva stato ratchet nel database
  Future<void> _saveRatchetState(
    String conversationId,
    RatchetState state,
  ) async {

    final ourPrivateKey = await state.ourRatchetKeyPair.extractPrivateKeyBytes();
    final ourPublicKey = await state.ourRatchetKeyPair.extractPublicKey();

    String? theirPublicKeyBase64;
    if (state.theirRatchetPublicKey != null) {
      final theirKey = state.theirRatchetPublicKey! as SimplePublicKey;
      theirPublicKeyBase64 = base64Encode(theirKey.bytes);
    }

    final model = RatchetStateModel(
      id: _cryptoService.generateId(),
      conversationId: conversationId,
      rootKey: base64Encode(state.rootKey),
      sendingChainKey: state.sendingChainKey != null
          ? base64Encode(state.sendingChainKey!)
          : null,
      receivingChainKey: state.receivingChainKey != null
          ? base64Encode(state.receivingChainKey!)
          : null,
      ourRatchetPrivateKey: base64Encode(Uint8List.fromList(ourPrivateKey)),
      ourRatchetPublicKey: base64Encode(Uint8List.fromList(ourPublicKey.bytes)),
      theirRatchetPublicKey: theirPublicKeyBase64,
      sendCount: state.sendCount,
      receiveCount: state.receiveCount,
      previousSendCount: state.previousSendCount,
      updatedAt: DateTime.now(),
    );

    // Cancella stato precedente
    await _db.delete(
      'ratchet_states',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    // Inserisci nuovo stato
    await _db.insert('ratchet_states', model.toMap());
  }

  /// Aggiorna stato ratchet
  Future<void> updateRatchetState(
    String conversationId,
    RatchetState state,
  ) async {
    await _saveRatchetState(conversationId, state);
  }

  /// Ricostruisce RatchetState dal modello database
  Future<RatchetState> _ratchetStateFromModel(RatchetStateModel model) async {
    final ourPrivateKey = base64Decode(model.ourRatchetPrivateKey);
    final ourPublicKey = base64Decode(model.ourRatchetPublicKey);

    final ourKeyPair = await _generateKeyPairFromBytes(
      ourPrivateKey,
      ourPublicKey,
    );

    PublicKey? theirPublicKey;
    if (model.theirRatchetPublicKey != null) {
      theirPublicKey = SimplePublicKey(
        base64Decode(model.theirRatchetPublicKey!),
        type: KeyPairType.x25519,
      );
    }

    return RatchetState(
      rootKey: base64Decode(model.rootKey),
      sendingChainKey: model.sendingChainKey != null
          ? base64Decode(model.sendingChainKey!)
          : null,
      receivingChainKey: model.receivingChainKey != null
          ? base64Decode(model.receivingChainKey!)
          : null,
      ourRatchetKeyPair: ourKeyPair,
      theirRatchetPublicKey: theirPublicKey,
      sendCount: model.sendCount,
      receiveCount: model.receiveCount,
      previousSendCount: model.previousSendCount,
    );
  }

  /// Helper per generare KeyPair da bytes
  Future<SimpleKeyPairData> _generateKeyPairFromBytes(
    List<int> privateKey,
    List<int> publicKey,
  ) async {
    return SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Aggiorna ultimo messaggio della conversazione
  Future<void> updateLastMessage(
    String conversationId,
    String messageText,
    DateTime timestamp,
  ) async {
    await _db.update(
      'conversations',
      {
        'last_message_text': messageText,
        'last_message_time': timestamp.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Incrementa contatore messaggi non letti
  Future<void> incrementUnreadCount(String conversationId) async {
    await _db.rawUpdate(
      'UPDATE conversations SET unread_count = unread_count + 1 WHERE id = ?',
      [conversationId],
    );
  }

  /// Azzera contatore messaggi non letti
  Future<void> clearUnreadCount(String conversationId) async {
    await _db.update(
      'conversations',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Elimina una conversazione
  Future<void> deleteConversation(String id) async {
    // Elimina messaggi
    await _db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [id],
    );

    // Elimina stato ratchet
    await _db.delete(
      'ratchet_states',
      where: 'conversation_id = ?',
      whereArgs: [id],
    );

    // Elimina conversazione
    await _db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
