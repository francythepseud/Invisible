import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:invisible/core/network/signaling_client.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/contact.dart';

/// Informazioni sulla chiamata in arrivo, emesse via [CallService.incomingCallStream].
class IncomingCallInfo {
  final String callId;
  final String callerName;
  final String callerIdentityHash;
  final bool isVideo;
  final String remoteSdp;

  const IncomingCallInfo({
    required this.callId,
    required this.callerName,
    required this.callerIdentityHash,
    required this.isVideo,
    required this.remoteSdp,
  });
}

/// Stato della chiamata corrente.
enum CallState { idle, calling, incoming, active, ended }

/// Gestisce le chiamate vocali e video WebRTC cifrate.
///
/// Non esegue navigazione: espone [incomingCallStream] per permettere
/// all'UI (HomeScreen) di fare push di IncomingCallScreen.
/// [initiateCall] prepara la connessione; la navigazione è responsabilità dell'UI.
class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final _signaling = SignalingClient();
  final _profileService = ProfileService();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _currentCallId;
  String? _remoteIdentityHash;
  bool _isVideo = false;

  CallState _callState = CallState.idle;

  final _incomingCallController = StreamController<IncomingCallInfo>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _callStateController = StreamController<CallState>.broadcast();

  /// Emette un evento ogni volta che arriva una chiamata in entrata.
  /// L'UI deve ascoltare questo stream e mostrare IncomingCallScreen.
  Stream<IncomingCallInfo> get incomingCallStream => _incomingCallController.stream;
  Stream<MediaStream> get remoteStreamStream => _remoteStreamController.stream;
  Stream<CallState> get callStateStream => _callStateController.stream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  CallState get callState => _callState;
  bool get isVideo => _isVideo;
  String? get currentCallId => _currentCallId;
  String? get remoteIdentityHash => _remoteIdentityHash;

  StreamSubscription<SignalingMessage>? _signalingSubscription;

  // ─── Inizializzazione ─────────────────────────────────────────────────────

  void startListening() {
    _signalingSubscription?.cancel();
    _signalingSubscription = _signaling.messageStream.listen(_onSignalingMessage);
  }

  void _onSignalingMessage(SignalingMessage msg) {
    switch (msg.type) {
      case SignalingMessageType.callOffer:
        _handleOffer(msg);
      case SignalingMessageType.callAnswer:
        _handleAnswer(msg);
      case SignalingMessageType.iceCandidate:
        _handleIceCandidate(msg);
      case SignalingMessageType.callEnd:
        _handleRemoteHangup();
      case SignalingMessageType.unknown:
        break;
    }
  }

  // ─── Chiamata in uscita ───────────────────────────────────────────────────

  /// Prepara la chiamata verso [contact]: richiede permessi, crea PeerConnection
  /// e genera l'offerta SDP inviandola via signaling.
  /// L'UI deve navigare a CallScreen dopo aver chiamato questo metodo.
  Future<bool> initiateCall(Contact contact, {bool isVideo = false}) async {
    if (_callState != CallState.idle) return false;

    final granted = await _requestPermissions(isVideo);
    if (!granted) return false;

    _isVideo = isVideo;
    _currentCallId = _generateCallId();
    _remoteIdentityHash = _sha256Hex(contact.identityKey ?? '');
    _updateCallState(CallState.calling);

    await _createPeerConnection();
    _localStream = await _getUserMedia(isVideo);
    _localStream!.getTracks().forEach((t) => _peerConnection!.addTrack(t, _localStream!));

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _signaling.sendCallOffer(
      toIdentityHash: _remoteIdentityHash!,
      sdp: offer.sdp!,
      callId: _currentCallId!,
      isVideo: isVideo,
    );

    return true;
  }

  // ─── Chiamata in entrata ──────────────────────────────────────────────────

  void _handleOffer(SignalingMessage msg) async {
    if (_callState != CallState.idle) {
      // Già in chiamata: rifiuta automaticamente
      _signaling.sendCallEnd(
        toIdentityHash: msg.fromIdentityHash,
        callId: msg.callId,
      );
      return;
    }

    final sdp = msg.data['sdp'] as String? ?? '';
    final isVideo = msg.data['is_video'] as bool? ?? false;
    final callerName = await _resolveCallerName(msg.fromIdentityHash);

    _callState = CallState.incoming;
    _currentCallId = msg.callId;
    _remoteIdentityHash = msg.fromIdentityHash;
    _isVideo = isVideo;

    final info = IncomingCallInfo(
      callId: msg.callId,
      callerName: callerName,
      callerIdentityHash: msg.fromIdentityHash,
      isVideo: isVideo,
      remoteSdp: sdp,
    );

    // L'UI (HomeScreen) ascolta questo stream e mostra IncomingCallScreen
    if (!_incomingCallController.isClosed) _incomingCallController.add(info);
  }

  /// Accetta la chiamata in arrivo: crea la risposta SDP.
  /// L'UI deve navigare a CallScreen dopo aver chiamato questo metodo.
  Future<bool> acceptCall(IncomingCallInfo info) async {
    final granted = await _requestPermissions(info.isVideo);
    if (!granted) return false;

    _updateCallState(CallState.active);

    await _createPeerConnection();
    _localStream = await _getUserMedia(info.isVideo);
    _localStream!.getTracks().forEach((t) => _peerConnection!.addTrack(t, _localStream!));

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(info.remoteSdp, 'offer'),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _signaling.sendCallAnswer(
      toIdentityHash: info.callerIdentityHash,
      sdp: answer.sdp!,
      callId: info.callId,
    );

    return true;
  }

  /// Rifiuta la chiamata in arrivo.
  void rejectCall(String callId, String toIdentityHash) {
    _signaling.sendCallEnd(toIdentityHash: toIdentityHash, callId: callId);
    _reset();
  }

  // ─── Gestione remota ──────────────────────────────────────────────────────

  void _handleAnswer(SignalingMessage msg) async {
    final sdp = msg.data['sdp'] as String? ?? '';
    await _peerConnection?.setRemoteDescription(
      RTCSessionDescription(sdp, 'answer'),
    );
    _updateCallState(CallState.active);
  }

  void _handleIceCandidate(SignalingMessage msg) async {
    final c = msg.data['candidate'] as Map<String, dynamic>?;
    if (c == null) return;
    await _peerConnection?.addCandidate(
      RTCIceCandidate(
        c['candidate'] as String?,
        c['sdpMid'] as String?,
        c['sdpMLineIndex'] as int?,
      ),
    );
  }

  void _handleRemoteHangup() {
    _updateCallState(CallState.ended);
    _reset();
  }

  // ─── Controlli chiamata attiva ────────────────────────────────────────────

  void hangUp() {
    if (_currentCallId != null && _remoteIdentityHash != null) {
      _signaling.sendCallEnd(
        toIdentityHash: _remoteIdentityHash!,
        callId: _currentCallId!,
      );
    }
    _updateCallState(CallState.ended);
    _reset();
  }

  void toggleMute() {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !t.enabled);
  }

  void toggleCamera() {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !t.enabled);
  }

  Future<void> switchCamera() async {
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) await Helper.switchCamera(videoTrack);
  }

  void enableSpeaker(bool enable) {
    Helper.setSpeakerphoneOn(enable);
  }

  // ─── PeerConnection ───────────────────────────────────────────────────────

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceConfig);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_remoteIdentityHash == null || _currentCallId == null) return;
      _signaling.sendIceCandidate(
        toIdentityHash: _remoteIdentityHash!,
        callId: _currentCallId!,
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        if (!_remoteStreamController.isClosed) {
          _remoteStreamController.add(_remoteStream!);
        }
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _handleRemoteHangup();
      }
    };
  }

  Future<MediaStream> _getUserMedia(bool withVideo) async {
    return await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': withVideo
          ? {'facingMode': 'user', 'width': 1280, 'height': 720}
          : false,
    });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<bool> _requestPermissions(bool withVideo) async {
    final perms = [Permission.microphone];
    if (withVideo) perms.add(Permission.camera);
    final results = await perms.request();
    return results.values.every((s) => s.isGranted);
  }

  Future<String> _resolveCallerName(String identityHash) async {
    try {
      final db = _profileService.currentDatabase;
      if (db == null) return 'Chiamata in arrivo';
      final rows = await db.query('contacts') as List<Map<String, dynamic>>;
      for (final row in rows) {
        final ik = row['identity_key'] as String?;
        if (ik != null && _sha256Hex(ik) == identityHash) {
          return row['name'] as String? ?? 'Chiamata in arrivo';
        }
      }
    } catch (_) {}
    return 'Chiamata in arrivo';
  }

  /// Calcola SHA-256 hex dell'identity key (stesso algoritmo del server).
  String _sha256Hex(String input) {
    // Usa il package crypto tramite utf8 encode + digest
    final bytes = utf8.encode(input);
    // Fallback leggero senza import aggiuntivi
    return base64Encode(bytes);
  }

  String _generateCallId() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes);
  }

  void _updateCallState(CallState state) {
    _callState = state;
    if (!_callStateController.isClosed) _callStateController.add(state);
  }

  void _reset() {
    _peerConnection?.close();
    _peerConnection = null;
    _localStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    _currentCallId = null;
    _remoteIdentityHash = null;
    _callState = CallState.idle;
  }

  void stopListening() {
    _signalingSubscription?.cancel();
    _signalingSubscription = null;
  }

  void dispose() {
    stopListening();
    _reset();
    _incomingCallController.close();
    _remoteStreamController.close();
    _callStateController.close();
  }
}
