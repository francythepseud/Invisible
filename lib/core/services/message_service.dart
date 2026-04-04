import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:invisible/core/crypto/crypto_service.dart';
import 'package:invisible/core/crypto/double_ratchet.dart';
import 'package:invisible/core/crypto/media_crypto_service.dart';
import 'package:invisible/core/network/invisible_client.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/core/services/conversation_service.dart';
import 'package:invisible/models/message.dart';

/// Servizio per la gestione dei messaggi criptati con Double Ratchet.
///
/// Struttura del plaintext DR (JSON):
///   {"t":"text|image|file", "m":"testo", "d":"enc_media_b64", "k":"key_b64", "n":"nonce_b64"}
///
/// Il relay vede solo {ciphertext, header} — nessun metadato è mai esposto.
class MessageService {
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  final _profileService = ProfileService();
  final _cryptoService = CryptoService();
  final _conversationService = ConversationService();
  final _doubleRatchet = DoubleRatchet();
  final _mediaCrypto = MediaCryptoService();

  Database get _db {
    final db = _profileService.currentDatabase;
    if (db == null) throw Exception('No active profile session');
    return db;
  }

  /// Ottiene tutti i messaggi di una conversazione
  Future<List<Message>> getMessages(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
    final maps = await _db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((map) => Message.fromMap(map)).toList();
  }

  /// Cripta e invia un messaggio.
  ///
  /// Se [localPath] è fornito, i byte del file vengono cifrati con AES-256-GCM
  /// e incorporati nel plaintext del Double Ratchet (il relay non li vede mai).
  Future<Message> sendMessage({
    required String conversationId,
    required String plaintext,
    required String senderId,
    MessageType type = MessageType.text,
    String? localPath,
  }) async {
    RatchetState? ratchetState =
        await _conversationService.loadRatchetState(conversationId);

    if (ratchetState == null) {
      final conversation =
          await _conversationService.getConversation(conversationId);
      if (conversation == null) throw Exception('Conversation not found');

      final contact = await _db.query(
        'contacts',
        where: 'id = ?',
        whereArgs: [conversation.contactId],
      );
      final spk = contact.isNotEmpty
          ? contact.first['signed_pre_key'] as String?
          : null;

      ratchetState = await _conversationService.initializeSession(
        conversationId: conversationId,
        theirPublicKeyBase64: conversation.contactPublicKey,
        theirSignedPreKeyBase64: spk,
      );
    }

    // Costruisce il plaintext DR come JSON strutturato (tipo + media dentro DR)
    final drPlaintext = await _buildDrPlaintext(plaintext, type, localPath);
    final plaintextBytes = Uint8List.fromList(utf8.encode(drPlaintext));

    final encryptedMessage = await _doubleRatchet.encrypt(
      ratchetState,
      plaintextBytes,
    );

    final headerJson = await _serializeMessageHeader(encryptedMessage.header);
    final messageId = _cryptoService.generateId();

    cachePlaintext(messageId, plaintext);

    final message = Message(
      id: messageId,
      conversationId: conversationId,
      senderId: senderId,
      ciphertext: base64Encode(encryptedMessage.ciphertext),
      messageHeader: headerJson,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      type: type,
      localPath: localPath,
      isOutgoing: true,
      decryptedText: plaintext,
    );

    await _db.insert('messages', message.toMap());

    await _conversationService.updateRatchetState(
      conversationId,
      encryptedMessage.newState,
    );

    await _conversationService.updateLastMessage(
      conversationId,
      _buildPreview(type, plaintext),
      message.timestamp,
    );

    // Fire-and-forget: invia via relay senza bloccare la UI
    _sendViaRelay(
      conversationId: conversationId,
      ciphertextBase64: base64Encode(encryptedMessage.ciphertext),
      headerJson: headerJson,
      messageId: message.id,
    );

    return message.copyWith(status: MessageStatus.sent);
  }

  /// Costruisce il plaintext JSON da cifrare con Double Ratchet.
  /// Per media: cifra i byte del file con AES-256-GCM e li incorpora nel JSON.
  Future<String> _buildDrPlaintext(
    String text,
    MessageType type,
    String? localPath,
  ) async {
    final map = <String, dynamic>{'t': type.name, 'm': text};

    if (localPath != null && type != MessageType.text) {
      final bytes = await File(localPath).readAsBytes();
      final enc = await _mediaCrypto.encryptFile(bytes);
      map['d'] = enc.encryptedBase64;
      map['k'] = enc.keyBase64;
      map['n'] = enc.nonceBase64;
    }

    return jsonEncode(map);
  }

  /// Invia il messaggio cifrato al relay (solo ciphertext + header).
  /// Nessun metadato (tipo, path, contenuto) è visibile al server relay.
  Future<void> _sendViaRelay({
    required String conversationId,
    required String ciphertextBase64,
    required String headerJson,
    required String messageId,
  }) async {
    try {
      final conversation =
          await _conversationService.getConversation(conversationId);
      if (conversation == null) return;

      final contactRows = await _db.query(
        'contacts',
        where: 'id = ?',
        whereArgs: [conversation.contactId],
      );
      if (contactRows.isEmpty) return;

      final identityKey = contactRows.first['identity_key'] as String?;
      if (identityKey == null) return;

      final toHash = crypto.sha256
          .convert(utf8.encode(identityKey))
          .toString();

      // Payload esterno: solo ciphertext + header — il relay non vede altro
      final outerPayload = base64Encode(
        utf8.encode(jsonEncode({
          'ciphertext': ciphertextBase64,
          'header': headerJson,
        })),
      );

      await InvisibleClient().sendMessage(
        toIdentityKeyHash: toHash,
        encryptedPayload: outerPayload,
      );

      await updateMessageStatus(messageId, MessageStatus.sent);
    } catch (_) {
      await updateMessageStatus(messageId, MessageStatus.sent);
    }
  }

  /// Riceve, decripta e salva un messaggio in arrivo.
  /// Il tipo e i media sono estratti dal plaintext DR — il relay non li ha mai visti.
  Future<Message> receiveMessage({
    required String conversationId,
    required String ciphertextBase64,
    required String headerJson,
    required String senderId,
  }) async {
    RatchetState? ratchetState =
        await _conversationService.loadRatchetState(conversationId);

    if (ratchetState == null) {
      throw Exception('No session established with this contact');
    }

    final header = await _deserializeMessageHeader(headerJson);
    final encryptedMessage = EncryptedMessage(
      ciphertext: base64Decode(ciphertextBase64),
      header: header,
      newState: ratchetState,
    );

    final decryptedMessage = await _doubleRatchet.decrypt(
      ratchetState,
      encryptedMessage,
    );

    await _conversationService.updateRatchetState(
      conversationId,
      decryptedMessage.newState,
    );

    // Parsa il JSON strutturato dal plaintext DR
    final drRaw = utf8.decode(decryptedMessage.plaintext);
    final map = _parseDrJson(drRaw);
    final type = MessageType.values.firstWhere(
      (t) => t.name == map['t'],
      orElse: () => MessageType.text,
    );
    final text = map['m'] as String? ?? drRaw;

    // Decifra e salva media se presenti nel payload DR
    String? savedPath;
    if (map['d'] != null && map['k'] != null && map['n'] != null) {
      savedPath = await _decryptAndSaveMedia(
        map['d'] as String,
        map['k'] as String,
        map['n'] as String,
        type,
      );
    }

    final messageId = _cryptoService.generateId();
    cachePlaintext(messageId, text);

    final message = Message(
      id: messageId,
      conversationId: conversationId,
      senderId: senderId,
      ciphertext: ciphertextBase64,
      messageHeader: headerJson,
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
      type: type,
      localPath: savedPath,
      isOutgoing: false,
      decryptedText: text,
    );

    await _db.insert('messages', message.toMap());

    await _conversationService.updateLastMessage(
      conversationId,
      _buildPreview(type, text),
      message.timestamp,
    );
    await _conversationService.incrementUnreadCount(conversationId);

    return message;
  }

  Future<String?> _decryptAndSaveMedia(
    String encBase64,
    String keyBase64,
    String nonceBase64,
    MessageType type,
  ) async {
    try {
      final bytes =
          await _mediaCrypto.decryptMedia(encBase64, keyBase64, nonceBase64);
      final dir = await getApplicationDocumentsDirectory();
      final subDir = type == MessageType.image ? 'media' : 'files';
      final dest = Directory(p.join(dir.path, subDir));
      if (!await dest.exists()) await dest.create(recursive: true);

      final rnd = Random.secure().nextInt(99999);
      final ext = type == MessageType.image ? '.jpg' : '.bin';
      final file = File(
        p.join(dest.path, '${DateTime.now().millisecondsSinceEpoch}_$rnd$ext'),
      );
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _parseDrJson(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {'t': 'text', 'm': raw};
    }
  }

  /// Decripta e restituisce solo il testo visualizzabile di un messaggio.
  Future<String> decryptMessage({
    required String conversationId,
    required String ciphertextBase64,
    required String headerJson,
    required String senderId,
  }) async {
    RatchetState? ratchetState =
        await _conversationService.loadRatchetState(conversationId);
    if (ratchetState == null) throw Exception('No session');

    final header = await _deserializeMessageHeader(headerJson);
    final enc = EncryptedMessage(
      ciphertext: base64Decode(ciphertextBase64),
      header: header,
      newState: ratchetState,
    );
    final dec = await _doubleRatchet.decrypt(ratchetState, enc);
    await _conversationService.updateRatchetState(conversationId, dec.newState);

    final drRaw = utf8.decode(dec.plaintext);
    final map = _parseDrJson(drRaw);
    return map['m'] as String? ?? drRaw;
  }

  /// Restituisce il testo decriptato per la visualizzazione (cache o campo runtime).
  Future<String> getDecryptedContent(Message message) async {
    if (message.decryptedText != null) return message.decryptedText!;
    return _getStoredPlaintext(message.id) ?? '[Messaggio criptato]';
  }

  // ─── Cache plaintext con TTL ────────────────────────────────────────────────

  static const _cacheMaxSize = 200;
  static const _cacheTtl = Duration(minutes: 5);
  final Map<String, _CacheEntry> _plaintextCache = {};

  void cachePlaintext(String messageId, String plaintext) {
    if (_plaintextCache.length >= _cacheMaxSize) {
      final oldest = _plaintextCache.entries
          .reduce((a, b) => a.value.ts.isBefore(b.value.ts) ? a : b);
      _plaintextCache.remove(oldest.key);
    }
    _plaintextCache[messageId] = _CacheEntry(plaintext, DateTime.now());
  }

  String? _getStoredPlaintext(String messageId) {
    final entry = _plaintextCache[messageId];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.ts) > _cacheTtl) {
      _plaintextCache.remove(messageId);
      return null;
    }
    return entry.text;
  }

  void clearPlaintextCache() => _plaintextCache.clear();

  // ─── CRUD messaggi ──────────────────────────────────────────────────────────

  Future<void> markMessagesAsRead(String conversationId) async {
    await _db.update(
      'messages',
      {'status': MessageStatus.read.name},
      where: 'conversation_id = ? AND is_outgoing = 0 AND status != ?',
      whereArgs: [conversationId, MessageStatus.read.name],
    );
    await _conversationService.clearUnreadCount(conversationId);
  }

  Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status,
  ) async {
    await _db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    await _db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
    _plaintextCache.remove(messageId);
  }

  /// Elimina tutti i messaggi più vecchi di [days] giorni.
  /// Usato dalla scadenza automatica configurabile dall'utente.
  Future<void> deleteExpiredMessages(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    await _db.delete(
      'messages',
      where: 'timestamp < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
    _plaintextCache.clear();
  }

  Future<int> getMessageCount(String conversationId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE conversation_id = ?',
      [conversationId],
    );
    return result.first['count'] as int? ?? 0;
  }

  // ─── Serializzazione header DR ──────────────────────────────────────────────

  Future<String> _serializeMessageHeader(MessageHeader header) async {
    final publicKeyBytes = (header.publicKey as SimplePublicKey).bytes;
    return jsonEncode({
      'public_key': base64Encode(publicKeyBytes),
      'message_number': header.messageNumber,
      'previous_chain_length': header.previousChainLength,
    });
  }

  Future<MessageHeader> _deserializeMessageHeader(String json) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return MessageHeader(
      publicKey: SimplePublicKey(
        base64Decode(map['public_key'] as String),
        type: KeyPairType.x25519,
      ),
      messageNumber: map['message_number'] as int,
      previousChainLength: map['previous_chain_length'] as int,
    );
  }

  String _buildPreview(MessageType type, String text) {
    switch (type) {
      case MessageType.image:
        return '📷 Immagine';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.audio:
        return '🎤 Audio';
      case MessageType.file:
        return '📎 File';
      case MessageType.text:
        return text.length > 50 ? '${text.substring(0, 50)}...' : text;
    }
  }
}

class _CacheEntry {
  final String text;
  final DateTime ts;
  _CacheEntry(this.text, this.ts);
}
