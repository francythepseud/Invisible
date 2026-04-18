import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:invisible/core/crypto/crypto_service.dart';
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
  final _doubleRatchet = DoubleRatchet();

  /// Ottiene il database corrente
  Database get _db {
    final db = _profileService.currentDatabase;
    if (db == null) {
      throw Exception('No active profile session');
    }
    return db;
  }

  /// Ottiene tutte le conversazioni ordinate per ultimo messaggio.
  /// Pulisce automaticamente eventuali residui di read receipt nei metadati.
  Future<List<Conversation>> getConversations() async {
    final maps = await _db.query(
      'conversations',
      orderBy: 'last_message_time DESC',
    );
    // Pulizia dati storici: se lastMessageText è una receipt, ripristina
    for (final map in maps) {
      final lastText = map['last_message_text'] as String?;
      if (lastText != null && lastText.contains('"t":"rr"')) {
        final convId = map['id'] as String;
        await refreshLastMessage(convId);
      }
    }
    // Rileggi dopo le eventuali correzioni
    final cleaned = await _db.query(
      'conversations',
      orderBy: 'last_message_time DESC',
    );
    return cleaned.map((map) => Conversation.fromMap(map)).toList();
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
  /// Usa ECDH statico simmetrico (senza chiavi effimere) così entrambi i lati
  /// possono derivare lo stesso sharedSecret indipendentemente.
  Future<RatchetState> initializeSession({
    required String conversationId,
    required String theirPublicKeyBase64,
    String? theirSignedPreKeyBase64,
  }) async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) throw Exception('No crypto keys found');

    // Master key X25519 come long-term DH identity key
    final myIdentityKeyPair = await _generateKeyPairFromBytes(
      base64Decode(keys.masterKeyPrivate),
      base64Decode(keys.masterKeyPublic),
    );

    // SPK locale (chiave DH separata)
    final mySpkKeyPair = await _generateKeyPairFromBytes(
      base64Decode(keys.signedPreKeyPrivate),
      base64Decode(keys.signedPreKeyPublic),
    );

    // Identity pubkey del destinatario (X25519 master key)
    final theirIdentityKey = SimplePublicKey(
      base64Decode(theirPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final theirSpkBytes = theirSignedPreKeyBase64 != null
        ? base64Decode(theirSignedPreKeyBase64)
        : base64Decode(theirPublicKeyBase64);
    final theirSignedPreKey = SimplePublicKey(
      theirSpkBytes,
      type: KeyPairType.x25519,
    );

    // Shared secret simmetrico: entrambi i lati possono derivarlo indipendentemente
    // perché DH è commutativo: DH(A_priv, B_pub) == DH(B_priv, A_pub)
    final sharedSecret = await _computeSymmetricSharedSecret(
      myIdentityKeyPair: myIdentityKeyPair,
      mySpkKeyPair: mySpkKeyPair,
      theirIdentityKey: theirIdentityKey,
      theirSpk: theirSignedPreKey,
    );

    final ratchetState = await _doubleRatchet.initializeAsSender(
      sharedSecret: sharedSecret,
      theirRatchetPublicKey: theirSignedPreKey,
    );

    await _saveRatchetState(conversationId, ratchetState);
    return ratchetState;
  }

  /// Inizializza sessione crittografica come ricevente.
  /// Chiamato quando arriva il primo messaggio e non esiste ancora ratchet state.
  Future<RatchetState> initializeSessionAsReceiver({
    required String conversationId,
    required String theirMasterKeyBase64,
    required String theirSpkBase64,
  }) async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) throw Exception('No crypto keys found');

    final myIdentityKeyPair = await _generateKeyPairFromBytes(
      base64Decode(keys.masterKeyPrivate),
      base64Decode(keys.masterKeyPublic),
    );
    final mySpkKeyPair = await _generateKeyPairFromBytes(
      base64Decode(keys.signedPreKeyPrivate),
      base64Decode(keys.signedPreKeyPublic),
    );

    final theirIdentityKey = SimplePublicKey(
      base64Decode(theirMasterKeyBase64),
      type: KeyPairType.x25519,
    );
    final theirSpkBytes = theirSpkBase64.isNotEmpty
        ? base64Decode(theirSpkBase64)
        : base64Decode(theirMasterKeyBase64);
    final theirSpk = SimplePublicKey(theirSpkBytes, type: KeyPairType.x25519);

    // Stesso calcolo del lato mittente — simmetrico per costruzione
    final sharedSecret = await _computeSymmetricSharedSecret(
      myIdentityKeyPair: myIdentityKeyPair,
      mySpkKeyPair: mySpkKeyPair,
      theirIdentityKey: theirIdentityKey,
      theirSpk: theirSpk,
    );

    final ratchetState = await _doubleRatchet.initializeAsReceiver(
      sharedSecret: sharedSecret,
      ourRatchetKeyPair: mySpkKeyPair,
    );

    await _saveRatchetState(conversationId, ratchetState);
    return ratchetState;
  }

  /// Derivazione ECDH simmetrica: stesso risultato da entrambi i lati.
  ///
  /// Usa solo DH(myIdentity, theirIdentity) che è trivialmente simmetrico:
  ///   DH(A_priv, B_pub) == DH(B_priv, A_pub)
  /// Il Double Ratchet garantisce forward secrecy dopo l'handshake iniziale.
  Future<Uint8List> _computeSymmetricSharedSecret({
    required SimpleKeyPair myIdentityKeyPair,
    required SimpleKeyPair mySpkKeyPair,
    required PublicKey theirIdentityKey,
    required PublicKey theirSpk,
  }) async {
    final x25519 = X25519();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    // DH simmetrico identity-to-identity: stesso valore da entrambi i lati
    final dh = await (await x25519.sharedSecretKey(
      keyPair: myIdentityKeyPair,
      remotePublicKey: theirIdentityKey,
    )).extractBytes();

    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(Uint8List.fromList(dh)),
      nonce: Uint8List(32),
      info: utf8.encode('Invisible-X3DH'),
    );
    return Uint8List.fromList(await derived.extractBytes());
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

  /// Decrementa contatore messaggi non letti (minimo 0)
  Future<void> decrementUnreadCount(String conversationId) async {
    await _db.rawUpdate(
      'UPDATE conversations SET unread_count = MAX(0, unread_count - 1) WHERE id = ?',
      [conversationId],
    );
  }

  /// Ripristina lastMessageText dalla tabella messages (usato dopo cancellazione receipt)
  Future<void> refreshLastMessage(String conversationId) async {
    final rows = await _db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      await _db.update(
        'conversations',
        {'last_message_text': null, 'last_message_time': null},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    } else {
      final row = rows.first;
      final text = row['decrypted_text'] as String? ?? '';
      final timestamp = row['timestamp'] as String? ?? DateTime.now().toIso8601String();
      await _db.update(
        'conversations',
        {
          'last_message_text': text.length > 60 ? text.substring(0, 60) : text,
          'last_message_time': timestamp,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    }
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
