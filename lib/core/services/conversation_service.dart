import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:invisible/core/crypto/crypto_service.dart';
import 'package:invisible/core/crypto/double_ratchet.dart';
import 'package:invisible/core/crypto/x3dh.dart';
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

  /// Inizializza sessione come mittente usando X3DH completo.
  ///
  /// DH1 = DH(myIdentity, theirSPK)
  /// DH2 = DH(ephemeral,  theirIdentity)
  /// DH3 = DH(ephemeral,  theirSPK)
  /// DH4 = DH(ephemeral,  theirOPK)   [opzionale]
  ///
  /// L'ephemeral key è inclusa nel primo messaggio (header DR).
  /// Il ricevente la usa per completare X3DH lato responder.
  Future<RatchetState> initializeSession({
    required String conversationId,
    required String theirPublicKeyBase64,      // X25519 master key (identity DH)
    String? theirSignedPreKeyBase64,
    String? theirOPKBase64,
    int? theirOPKId,
  }) async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) throw Exception('No crypto keys found');

    final myIdentityKP = await _generateKeyPairFromBytes(
      base64Decode(keys.masterKeyPrivate),
      base64Decode(keys.masterKeyPublic),
    );

    final theirIdentityKey = SimplePublicKey(
      base64Decode(theirPublicKeyBase64), type: KeyPairType.x25519,
    );
    final theirSpkBytes = theirSignedPreKeyBase64 != null
        ? base64Decode(theirSignedPreKeyBase64)
        : base64Decode(theirPublicKeyBase64);
    final theirSpk = SimplePublicKey(theirSpkBytes, type: KeyPairType.x25519);

    PublicKey? theirOPK;
    if (theirOPKBase64 != null) {
      theirOPK = SimplePublicKey(base64Decode(theirOPKBase64), type: KeyPairType.x25519);
    }

    // X3DH completo (3 o 4 DH operations)
    final x3dh = X3DH();
    final x3dhResult = await x3dh.performAsInitiator(
      myIdentityKey: myIdentityKP,
      theirIdentityKey: theirIdentityKey,
      theirSignedPreKey: theirSpk,
      theirOneTimePreKey: theirOPK,
    );

    final ephemeralPub = base64Encode(
      (x3dhResult.ephemeralPublicKey as SimplePublicKey).bytes,
    );

    // Double Ratchet inizializzato con shared secret X3DH
    // La chiave DH ratchet iniziale è la SPK del destinatario
    final ratchetState = await _doubleRatchet.initializeAsSender(
      sharedSecret: x3dhResult.sharedSecret,
      theirRatchetPublicKey: theirSpk,
    );

    await _saveRatchetState(
      conversationId, ratchetState,
      x3dhEphemeralPub: ephemeralPub,
      x3dhOpkId: theirOPKId,
    );
    return ratchetState;
  }

  /// Inizializza sessione come ricevente usando X3DH completo.
  ///
  /// [x3dhEphemeralPubBase64] = chiave effimera X25519 del mittente (dall'header del primo messaggio)
  /// [x3dhOpkId]              = ID della OPK usata dal mittente (opzionale)
  Future<RatchetState> initializeSessionAsReceiver({
    required String conversationId,
    required String theirMasterKeyBase64,
    required String theirSpkBase64,
    String? x3dhEphemeralPubBase64,
    int? x3dhOpkId,
  }) async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) throw Exception('No crypto keys found');

    final myIdentityKP = await _generateKeyPairFromBytes(
      base64Decode(keys.masterKeyPrivate),
      base64Decode(keys.masterKeyPublic),
    );
    final mySpkKP = await _generateKeyPairFromBytes(
      base64Decode(keys.signedPreKeyPrivate),
      base64Decode(keys.signedPreKeyPublic),
    );

    final theirIdentityKey = SimplePublicKey(
      base64Decode(theirMasterKeyBase64), type: KeyPairType.x25519,
    );
    final theirSpkBytes = theirSpkBase64.isNotEmpty
        ? base64Decode(theirSpkBase64)
        : base64Decode(theirMasterKeyBase64);
    final theirEphKey = x3dhEphemeralPubBase64 != null
        ? SimplePublicKey(base64Decode(x3dhEphemeralPubBase64), type: KeyPairType.x25519)
        : SimplePublicKey(theirSpkBytes, type: KeyPairType.x25519);

    // Recupera OPK privata se indicata dal mittente
    SimpleKeyPair? myOPKKP;
    if (x3dhOpkId != null) {
      final opkRow = await _profileService.getOPKById(x3dhOpkId);
      if (opkRow != null) {
        myOPKKP = await _generateKeyPairFromBytes(
          base64Decode(opkRow['private_key'] as String),
          base64Decode(opkRow['public_key'] as String),
        );
        // Segna come usata — usa-e-getta
        await _profileService.markOPKUsed(x3dhOpkId);
      }
    }

    // X3DH completo lato responder
    final x3dh = X3DH();
    final sharedSecret = await x3dh.performAsResponder(
      myIdentityKey: myIdentityKP,
      mySignedPreKey: mySpkKP,
      myOneTimePreKey: myOPKKP,
      theirIdentityKey: theirIdentityKey,
      theirEphemeralKey: theirEphKey,
    );

    final ratchetState = await _doubleRatchet.initializeAsReceiver(
      sharedSecret: sharedSecret,
      ourRatchetKeyPair: mySpkKP,
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
    RatchetState state, {
    String? x3dhEphemeralPub,
    int? x3dhOpkId,
  }) async {

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
      x3dhEphemeralPub: x3dhEphemeralPub,
      x3dhOpkId: x3dhOpkId,
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

  /// Carica i metadati X3DH dello stato ratchet (ephemeral pub + opk id).
  /// Restituisce null se non esiste uno stato o se i campi sono assenti.
  Future<Map<String, dynamic>?> loadRatchetX3dhMeta(String conversationId) async {
    final maps = await _db.query(
      'ratchet_states',
      columns: ['x3dh_ephemeral_pub', 'x3dh_opk_id'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    if (maps.isEmpty) return null;
    final eph = maps.first['x3dh_ephemeral_pub'] as String?;
    if (eph == null) return null;
    return {
      'eph': eph,
      'opk_id': maps.first['x3dh_opk_id'] as int?,
    };
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
