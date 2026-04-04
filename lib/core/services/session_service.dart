import 'dart:async';
import 'dart:convert';
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
      final contact = await _findContactByIdentityHash(incoming.fromId, db);
      if (contact == null) return;

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
      final message = await _messageService.receiveMessage(
        conversationId: conversation.id,
        ciphertextBase64: ciphertext,
        headerJson: headerJson,
        senderId: contact.id,
      );

      // Notifica il ChatScreen se è aperto su questa conversazione
      final ctrl = _convStreams[conversation.id];
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(message);
      }

      // Mostra notifica locale anonima (solo se l'utente l'ha abilitata)
      NotificationService().showMessageNotification();
    } catch (_) {
      // Ignora errori di decriptazione
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
      final computed = _sha256Hex(ik);
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
