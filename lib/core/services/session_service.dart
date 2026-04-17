import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:invisible/core/crypto/crypto_service.dart';
import 'package:invisible/core/network/invisible_client.dart';
import 'package:invisible/core/network/mesh_vpn_service.dart';
import 'package:invisible/core/network/signaling_client.dart';
import 'package:invisible/core/services/conversation_service.dart';
import 'package:invisible/core/services/message_service.dart';
import 'package:invisible/core/services/notification_service.dart';
import 'package:invisible/core/services/presence_service.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/contact.dart';
import 'package:invisible/models/message.dart';
import 'package:invisible/utils/constants.dart';

/// Gestisce il ciclo di vita della sessione P2P:
///   - Connessione relay WebSocket (Ed25519 auth automatica)
///   - Connessione rete mesh WireGuard
///   - Connessione server di segnalazione WebRTC
///   - Rotazione Signed Pre-Key ogni 7 giorni
///   - Dispatch dei messaggi in arrivo al ChatScreen giusto
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  final _relay = InvisibleClient();
  final _mesh = MeshVpnService();
  final _signaling = SignalingClient();
  final _profileService = ProfileService();
  final _conversationService = ConversationService();
  final _messageService = MessageService();
  final _cryptoService = CryptoService();
  final _presenceService = PresenceService();

  // Per-conversation stream: ChatScreen si iscrive per aggiornamenti real-time
  final Map<String, StreamController<Message>> _convStreams = {};
  StreamSubscription<IncomingRelayMessage>? _relaySubscription;

  // Global stream: ChatsListScreen si iscrive per aggiornare i badge in real-time
  final _anyMessageController = StreamController<Message>.broadcast();
  Stream<Message> get anyMessageStream => _anyMessageController.stream;

  // Read receipt stream: conversationId quando l'altro ha letto
  final _readReceiptController = StreamController<String>.broadcast();
  Stream<String> get readReceiptStream => _readReceiptController.stream;

  InvisibleClient get relay => _relay;
  MeshVpnService get mesh => _mesh;
  SignalingClient get signaling => _signaling;

  /// Stream di messaggi in arrivo per una specifica conversazione.
  Stream<Message> messagesFor(String conversationId) {
    _convStreams.putIfAbsent(
      conversationId,
      () => StreamController<Message>.broadcast(),
    );
    return _convStreams[conversationId]!.stream;
  }

  // ─── Avvio sessione ─────────────────────────────────────────────────────────

  /// Avvia la sessione dopo il login. Non blocca la UI.
  void startSession() {
    _connectRelay();
    _connectSignaling();
    _checkSpkRotation();
  }

  void _connectRelay() {
    _relaySubscription?.cancel();
    _relaySubscription = _relay.messageStream.listen(_onRelayMessage);
    _presenceService.start();
    if (_relay.status == RelayStatus.connected) return;
    _relay.connect(AppConstants.relayWsUrl).catchError((_) {});
  }

  void _connectSignaling() {
    Future(() async {
      try {
        await _signaling.connect(AppConstants.signalingWsUrl);
      } catch (_) {}
    });
  }

  /// Controlla se la Signed Pre-Key è scaduta e, in caso, la ruota.
  void _checkSpkRotation() {
    Future(() async {
      try {
        final keys = await _profileService.getCurrentCryptoKeys();
        if (keys == null) return;
        final age = DateTime.now().difference(keys.signedPreKeyCreatedAt).inDays;
        if (age < AppConstants.prekeyRotationDays) return;
        final newKeys = await _cryptoService.rotateSignedPreKey(keys);
        await _profileService.saveCryptoKeys(newKeys);
      } catch (_) {}
    });
  }

  // ─── Messaggio in arrivo ─────────────────────────────────────────────────────

  Future<void> _onRelayMessage(IncomingRelayMessage incoming) async {
    try {
      final db = _profileService.currentDatabase;
      if (db == null) return;

      // Trova il contatto corrispondente all'identity hash del mittente
      debugPrint('[SESSION] Messaggio in arrivo da fromId=${incoming.fromId}');
      final contact = await _findContactByIdentityHash(incoming.fromId, db);
      if (contact == null) {
        debugPrint('[SESSION] Contatto non trovato per fromId=${incoming.fromId}');
        return;
      }
      debugPrint('[SESSION] Contatto trovato: ${contact.name}');

      // Il payload esterno è JSON base64: {"ciphertext":"...","header":"..."}
      // Tipo e media sono dentro il plaintext DR — il relay non li ha mai visti
      final payloadJson =
          jsonDecode(utf8.decode(base64Decode(incoming.payload)))
              as Map<String, dynamic>;

      final ciphertext = payloadJson['ciphertext'] as String;
      final headerJson = payloadJson['header'] as String;

      // Ottieni o crea la conversazione con questo contatto
      final conversation =
          await _conversationService.getOrCreateConversation(contact);

      // Decripta e salva il messaggio (tipo estratto dal plaintext DR)
      debugPrint('[SESSION] Decripto messaggio per conversazione ${conversation.id}');
      final message = await _messageService.receiveMessage(
        conversationId: conversation.id,
        ciphertextBase64: ciphertext,
        headerJson: headerJson,
        senderId: contact.id,
      );
      debugPrint('[SESSION] Messaggio decriptato OK: ${message.id}');

      // Se è una read receipt, aggiorna i messaggi uscenti e notifica la UI
      if (message.decryptedText == '{"t":"rr"}' || message.decryptedText?.trim() == '{"t":"rr"}') {
        debugPrint('[SESSION] Read receipt ricevuta per conversazione ${conversation.id}');
        await _messageService.markOutgoingMessagesAsRead(conversation.id);
        // Cancella il messaggio rr dal DB (non va mostrato in chat)
        await _messageService.deleteMessage(message.id);
        // receiveMessage ha già incrementato unread_count e lastMessageText: correggiamo
        await _conversationService.decrementUnreadCount(conversation.id);
        await _conversationService.refreshLastMessage(conversation.id);
        if (!_readReceiptController.isClosed) {
          _readReceiptController.add(conversation.id);
        }
        return;
      }

      // Notifica il ChatScreen se è aperto su questa conversazione
      final ctrl = _convStreams[conversation.id];
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(message);
      }

      // Notifica globale (ChatsListScreen per aggiornare badge)
      if (!_anyMessageController.isClosed) {
        _anyMessageController.add(message);
      }

      // Mostra notifica locale anonima (solo se l'utente l'ha abilitata)
      NotificationService().showMessageNotification();
    } catch (e, st) {
      debugPrint('[SESSION] Errore ricezione messaggio: $e\n$st');
    }
  }

  // ─── Ricerca contatto da identity hash ──────────────────────────────────────

  Future<Contact?> _findContactByIdentityHash(
    String hash,
    dynamic db,
  ) async {
    final rows = await db.query('contacts') as List<Map<String, dynamic>>;
    for (final row in rows) {
      final ik = row['identity_key'] as String?;
      if (ik == null) continue;
      // Il relay usa shortHash: ultimi 32 caratteri della identity key base64
      final computed = ik.length > 32 ? ik.substring(ik.length - 32) : ik;
      debugPrint('[SESSION] Confronto hash=$hash vs computed=$computed (ik len=${ik.length})');
      if (computed == hash) return Contact.fromJson(row);
    }
    return null;
  }

  String _sha256Hex(String input) {
    final digest = crypto.sha256.convert(utf8.encode(input));
    return digest.toString();
  }

  /// Calcola l'identity hash da inviare al relay come destinatario.
  String identityHash(String identityKeyBase64) => _sha256Hex(identityKeyBase64);

  // ─── Fine sessione ──────────────────────────────────────────────────────────

  /// Ferma la sessione al logout. Chiude relay, mesh, signaling e tutti gli stream.
  Future<void> endSession() async {
    _relaySubscription?.cancel();
    _relaySubscription = null;
    _presenceService.stop();
    await _relay.disconnect();
    await _mesh.disconnect();
    await _signaling.disconnect();
    for (final ctrl in _convStreams.values) {
      if (!ctrl.isClosed) ctrl.close();
    }
    _convStreams.clear();
  }
}
