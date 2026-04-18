import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:invisible/core/services/profile_service.dart';

/// Tipo di messaggio di segnalazione ricevuto dal server.
enum SignalingMessageType {
  callOffer,
  callAnswer,
  iceCandidate,
  callEnd,
  unknown,
}

/// Messaggio di segnalazione WebRTC ricevuto dal server.
class SignalingMessage {
  final SignalingMessageType type;
  final String fromIdentityHash;
  final String callId;
  final Map<String, dynamic> data;

  const SignalingMessage({
    required this.type,
    required this.fromIdentityHash,
    required this.callId,
    required this.data,
  });
}

/// Client WebSocket per il server di segnalazione WebRTC.
///
/// Protocollo server Go (/v1/signal):
///   Client → Server: {"type":"offer|answer|ice|hangup", "to":"destHash", "payload":"{...JSON...}"}
///   Server → Client: {"type":"offer|answer|ice|hangup", "from":"senderHash", "payload":"{...JSON...}"}
///
/// Autenticazione: stessa challenge-response Ed25519 del relay.
class SignalingClient {
  static final SignalingClient _instance = SignalingClient._internal();
  factory SignalingClient() => _instance;
  SignalingClient._internal();

  static const _pingInterval = Duration(seconds: 25);
  static const _reconnectDelay = Duration(seconds: 5);

  final _profileService = ProfileService();
  final _messageController = StreamController<SignalingMessage>.broadcast();

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;
  String? _signalingUrl;
  bool _connected = false;

  Stream<SignalingMessage> get messageStream => _messageController.stream;
  bool get isConnected => _connected;

  // ─── Connessione ─────────────────────────────────────────────────────────

  Future<void> connect(String signalingWsUrl) async {
    _signalingUrl = signalingWsUrl;
    _intentionalDisconnect = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_signalingUrl!));
      // cancelOnError: false → rimane in ascolto dopo un errore transitorio
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      // Aspetta la connessione: cattura WebSocketChannelException qui invece
      // di lasciarla propagare al zone error handler
      await _channel!.ready.catchError((e) {
        debugPrint('[SIGNAL] WebSocket ready error: $e');
        _connected = false;
        _scheduleReconnect();
      });
    } catch (e) {
      debugPrint('[SIGNAL] Connessione fallita: $e');
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
          _connected = true;
          debugPrint('[SIGNAL] auth_ok — connesso id=${msg['from'] ?? ''}');
          _startPing();
        case 'auth_fail':
          _intentionalDisconnect = true;
          await disconnect();
        case 'offer':
          _dispatchSignal(msg, SignalingMessageType.callOffer);
        case 'answer':
          _dispatchSignal(msg, SignalingMessageType.callAnswer);
        case 'ice':
          _dispatchSignal(msg, SignalingMessageType.iceCandidate);
        case 'hangup':
          _dispatchSignal(msg, SignalingMessageType.callEnd);
        case 'pong':
          break;
      }
    } catch (e) {
      debugPrint('[SIGNAL] _onMessage errore: $e');
    }
  }

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

  /// Decodifica un messaggio in arrivo dal server e lo emette nello stream.
  /// Il server invia: {"type":"offer|answer|ice|hangup", "from":"hash", "payload":"{...}"}
  void _dispatchSignal(Map<String, dynamic> msg, SignalingMessageType type) {
    try {
      final from = msg['from'] as String? ?? '';
      final payloadRaw = msg['payload'];
      Map<String, dynamic> payload = {};
      if (payloadRaw is String && payloadRaw.isNotEmpty) {
        payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
      } else if (payloadRaw is Map<String, dynamic>) {
        payload = payloadRaw;
      }
      final callId = payload['call_id'] as String? ?? '';
      debugPrint('[SIGNAL] ricevuto ${type.name} from=$from callId=$callId');
      final sigMsg = SignalingMessage(
        type: type,
        fromIdentityHash: from,
        callId: callId,
        data: payload,
      );
      if (!_messageController.isClosed) _messageController.add(sigMsg);
    } catch (e) {
      debugPrint('[SIGNAL] Errore dispatch signal: $e');
    }
  }

  // ─── Invio messaggi di segnalazione ──────────────────────────────────────

  void sendCallOffer({
    required String toIdentityHash,
    required String sdp,
    required String callId,
    required bool isVideo,
  }) {
    _send({
      'type': 'offer',
      'to': toIdentityHash,
      'payload': jsonEncode({
        'sdp': sdp,
        'call_id': callId,
        'is_video': isVideo,
      }),
    });
  }

  void sendCallAnswer({
    required String toIdentityHash,
    required String sdp,
    required String callId,
  }) {
    _send({
      'type': 'answer',
      'to': toIdentityHash,
      'payload': jsonEncode({
        'sdp': sdp,
        'call_id': callId,
      }),
    });
  }

  void sendIceCandidate({
    required String toIdentityHash,
    required Map<String, dynamic> candidate,
    required String callId,
  }) {
    _send({
      'type': 'ice',
      'to': toIdentityHash,
      'payload': jsonEncode({
        'candidate': candidate,
        'call_id': callId,
      }),
    });
  }

  void sendCallEnd({
    required String toIdentityHash,
    required String callId,
  }) {
    _send({
      'type': 'hangup',
      'to': toIdentityHash,
      'payload': jsonEncode({
        'call_id': callId,
      }),
    });
  }

  // ─── Infrastruttura ───────────────────────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _send({'type': 'ping'}));
  }

  void _onError(Object error, [StackTrace? _]) {
    debugPrint('[SIGNAL] stream error: $error');
    _connected = false;
    _scheduleReconnect();
  }

  void _onDone() {
    _connected = false;
    _pingTimer?.cancel();
    if (!_intentionalDisconnect) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay + Duration(milliseconds: Random().nextInt(2000)), () {
      if (!_intentionalDisconnect) _doConnect();
    });
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _connected = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}
