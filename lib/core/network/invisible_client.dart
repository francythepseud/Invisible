import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:invisible/core/network/pinned_http_client.dart';
import 'package:invisible/core/services/profile_service.dart';

/// Stato della connessione al relay
enum RelayStatus { disconnected, connecting, connected, reconnecting }

/// Evento presenza ricevuto dal relay
class PresenceEvent {
  final String userId; // shortHash dell'identity key
  final bool online;
  const PresenceEvent({required this.userId, required this.online});
}

/// Messaggio ricevuto dal relay già decriptato a livello trasporto
class IncomingRelayMessage {
  final String fromId;
  final String payload; // base64 del ciphertext E2E (decripta il Double Ratchet)
  final String msgId;
  final DateTime timestamp;

  const IncomingRelayMessage({
    required this.fromId,
    required this.payload,
    required this.msgId,
    required this.timestamp,
  });
}

/// Client WebSocket per il relay cifrato di Invisible.
///
/// Autenticazione: challenge-response Ed25519 senza username/password.
/// Il server non vede mai il contenuto dei messaggi (E2E con Double Ratchet).
class InvisibleClient {
  static final InvisibleClient _instance = InvisibleClient._internal();
  factory InvisibleClient() => _instance;
  InvisibleClient._internal();

  static const _reconnectDelay = Duration(seconds: 3);
  static const _maxReconnectDelay = Duration(seconds: 60);
  static const _pingInterval = Duration(seconds: 25);

  final _profileService = ProfileService();
  final _statusController = StreamController<RelayStatus>.broadcast();
  final _messageController = StreamController<IncomingRelayMessage>.broadcast();
  final _presenceController = StreamController<PresenceEvent>.broadcast();
  final _notAuthorizedController = StreamController<void>.broadcast();

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Duration _currentReconnectDelay = _reconnectDelay;
  bool _intentionalDisconnect = false;
  String? _relayUrl;

  Stream<RelayStatus> get statusStream => _statusController.stream;
  Stream<IncomingRelayMessage> get messageStream => _messageController.stream;
  Stream<PresenceEvent> get presenceStream => _presenceController.stream;
  Stream<void> get notAuthorizedStream => _notAuthorizedController.stream;

  RelayStatus _status = RelayStatus.disconnected;
  RelayStatus get status => _status;

  void _updateStatus(RelayStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Connette al relay e autentica via Ed25519 challenge-response.
  Future<void> connect(String relayWsUrl) async {
    _relayUrl = relayWsUrl;
    _intentionalDisconnect = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _updateStatus(RelayStatus.connecting);
    try {
      // WebSocket con TLS strict: usa HttpClient custom che rifiuta cert non validi.
      // Su Android il pinning è rafforzato a livello OS da network_security_config.xml.
      final ws = await WebSocket.connect(
        _relayUrl!,
        customClient: PinnedHttpClient.create(),
      );
      _channel = IOWebSocketChannel(ws);

      _channel!.stream.listen(
        _onMessage,
        onError: (e) => _onError(e),
        onDone: _onDone,
        cancelOnError: false,
      );

      // Connessione riuscita: richiedi il challenge
      _send({'type': 'get_challenge'});
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) async {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      switch (type) {
        case 'challenge':
          await _handleChallenge(msg['challenge'] as String);
        case 'auth_ok':
          _updateStatus(RelayStatus.connected);
          _currentReconnectDelay = _reconnectDelay;
          _startPing();
        case 'auth_fail':
          if (msg['payload'] == 'not_authorized') {
            _notAuthorizedController.add(null);
          }
          _intentionalDisconnect = true;
          await disconnect();
        case 'deliver':
          _handleDeliver(msg);
        case 'presence':
          final userId = msg['from'] as String?;
          final status = msg['payload'] as String?;
          if (userId != null && status != null) {
            _presenceController.add(PresenceEvent(
              userId: userId,
              online: status == 'online',
            ));
          }
        case 'pong':
          break;
        case 'error':
          break;
      }
    } catch (_) {
      // Messaggio malformato — ignoriamo
    }
  }

  /// Firma il challenge con la identity key Ed25519 del profilo.
  Future<void> _handleChallenge(String challengeBase64) async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) return;

    final ed25519 = Ed25519();
    final keyPair = SimpleKeyPairData(
      base64Decode(keys.identityKeyPrivate),
      publicKey: SimplePublicKey(
        base64Decode(keys.identityKeyPublic),
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    );

    final sig = await ed25519.sign(base64Decode(challengeBase64), keyPair: keyPair);

    _send({
      'type': 'auth',
      'identity_key': keys.identityKeyPublic,
      'challenge': challengeBase64,
      'signature': base64Encode(sig.bytes),
    });
  }

  void _handleDeliver(Map<String, dynamic> msg) {
    try {
      final incoming = IncomingRelayMessage(
        fromId: msg['from'] as String,
        payload: msg['payload'] as String,
        msgId: msg['msg_id'] as String,
        timestamp: DateTime.parse(msg['timestamp'] as String),
      );
      _messageController.add(incoming);
      // Invia ACK al server per confermare ricezione
      _send({'type': 'ack', 'msg_id': incoming.msgId});
    } catch (_) {}
  }

  /// Invia un messaggio E2E cifrato al destinatario.
  /// [toIdentityKeyHash] = SHA-256 base64 dell'identity key Ed25519 del destinatario
  /// [encryptedPayload]  = base64 del ciphertext prodotto dal Double Ratchet
  Future<void> sendMessage({
    required String toIdentityKeyHash,
    required String encryptedPayload,
  }) async {
    if (_status != RelayStatus.connected) {
      throw Exception('Relay non connesso');
    }
    final msgId = _generateMsgId();
    _send({
      'type': 'send',
      'to': toIdentityKeyHash,
      'payload': encryptedPayload,
      'msg_id': msgId,
    });
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      _send({'type': 'ping'});
    });
  }

  void _onError(Object error) {
    _scheduleReconnect();
  }

  void _onDone() {
    _pingTimer?.cancel();
    if (!_intentionalDisconnect) {
      _updateStatus(RelayStatus.reconnecting);
      _scheduleReconnect();
    } else {
      _updateStatus(RelayStatus.disconnected);
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_currentReconnectDelay, () {
      if (!_intentionalDisconnect) _doConnect();
    });
    // Exponential backoff con jitter
    final jitter = Duration(milliseconds: Random().nextInt(1000));
    final next = _currentReconnectDelay * 2 + jitter;
    _currentReconnectDelay =
        next > _maxReconnectDelay ? _maxReconnectDelay : next;
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _updateStatus(RelayStatus.disconnected);
  }

  String _generateMsgId() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
    _presenceController.close();
    _notAuthorizedController.close();
  }
}
