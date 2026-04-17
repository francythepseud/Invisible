import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:wireguard_flutter/wireguard_flutter.dart';
import 'package:invisible/core/services/profile_service.dart';

/// Stato del tunnel mesh WireGuard
enum MeshStatus { disconnected, connecting, connected, error }

/// Configurazione ricevuta dal mesh-gateway dopo l'autenticazione.
class MeshConfig {
  final String assignedIp;      // es. 10.7.0.42
  final String serverWgPubkey;  // WireGuard pubkey del server
  final String serverEndpoint;  // es. vps.example.com:51820
  final String meshNetwork;     // es. 10.7.0.0/16

  const MeshConfig({
    required this.assignedIp,
    required this.serverWgPubkey,
    required this.serverEndpoint,
    required this.meshNetwork,
  });

  factory MeshConfig.fromJson(Map<String, dynamic> j) => MeshConfig(
        assignedIp: j['assigned_ip'] as String,
        serverWgPubkey: j['server_wg_pub'] as String,
        serverEndpoint: j['server_endpoint'] as String,
        meshNetwork: j['mesh_network'] as String,
      );
}

/// Gestisce la connessione alla rete mesh WireGuard.
///
/// Flusso:
///   1. Genera una WireGuard keypair (Curve25519) locale.
///   2. Autentica sul mesh-gateway con Ed25519 challenge-response.
///   3. Il gateway assegna un IP mesh e restituisce la config WireGuard.
///   4. Configura e avvia il tunnel VPN tramite wireguard_flutter.
///
/// Ascolta [statusStream] per aggiornamenti in tempo reale.
class MeshVpnService {
  static final MeshVpnService _instance = MeshVpnService._internal();
  factory MeshVpnService() => _instance;
  MeshVpnService._internal();

  static const _wgPrivKeyStorage = 'wg_private_key';
  static const _wgPubKeyStorage = 'wg_public_key';

  final _profileService = ProfileService();
  final _secureStorage = const FlutterSecureStorage();
  final _statusController = StreamController<MeshStatus>.broadcast();
  final _notAuthorizedController = StreamController<void>.broadcast();

  MeshStatus _status = MeshStatus.disconnected;
  MeshConfig? _currentConfig;

  MeshStatus get status => _status;
  MeshConfig? get currentConfig => _currentConfig;
  String? get assignedIp => _currentConfig?.assignedIp;
  Stream<MeshStatus> get statusStream => _statusController.stream;
  Stream<void> get notAuthorizedStream => _notAuthorizedController.stream;

  void _updateStatus(MeshStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  // ─── Connessione ─────────────────────────────────────────────────────────

  /// Connette alla rete mesh. [gatewayHttpUrl] es. https://vps.example.com/v1/mesh
  Future<MeshConfig> connect(String gatewayHttpUrl) async {
    // WireGuard Network Extension richiede Apple Developer Program su macOS
    if (!Platform.isAndroid && !Platform.isIOS) {
      _updateStatus(MeshStatus.error);
      throw Exception('Mesh non disponibile su macOS senza Developer Program');
    }
    _updateStatus(MeshStatus.connecting);
    try {
      // 1. Ottieni/genera WireGuard keypair locale
      final wgKeys = await _getOrCreateWgKeys();

      // 2. Carica identity key (serve per il challenge)
      final keys = await _profileService.getCurrentCryptoKeys();
      if (keys == null) throw Exception('Profilo non disponibile');

      // 3. Ottieni challenge dal gateway (keyed by identity_key)
      final challenge = await _requestChallenge(gatewayHttpUrl, keys.identityKeyPublic);

      final signature = await _signChallenge(
        challenge,
        identityPrivate: keys.identityKeyPrivate,
        identityPublic: keys.identityKeyPublic,
      );

      // 4. Invia response → ottieni config WireGuard
      final config = await _submitAuth(
        gatewayHttpUrl,
        identityKey: keys.identityKeyPublic,
        wgPublicKey: wgKeys.publicKey,
        challenge: challenge,
        signature: signature,
      );

      // 5. Avvia tunnel
      await _startTunnel(config, wgKeys.privateKey);

      _currentConfig = config;
      _updateStatus(MeshStatus.connected);
      return config;
    } catch (e) {
      _updateStatus(MeshStatus.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _stopTunnel();
    _currentConfig = null;
    _updateStatus(MeshStatus.disconnected);
  }

  // ─── Keypair WireGuard ───────────────────────────────────────────────────

  Future<_WgKeyPair> _getOrCreateWgKeys() async {
    final stored = await _secureStorage.read(key: _wgPrivKeyStorage);
    if (stored != null) {
      final pub = await _secureStorage.read(key: _wgPubKeyStorage) ?? '';
      return _WgKeyPair(privateKey: stored, publicKey: pub);
    }
    // Genera una nuova Curve25519 keypair per WireGuard
    final kp = await X25519().newKeyPair();
    final privBytes = await kp.extractPrivateKeyBytes();
    final pubBytes = (await kp.extractPublicKey()).bytes;
    final priv = base64Encode(privBytes);
    final pub = base64Encode(pubBytes);
    await _secureStorage.write(key: _wgPrivKeyStorage, value: priv);
    await _secureStorage.write(key: _wgPubKeyStorage, value: pub);
    return _WgKeyPair(privateKey: priv, publicKey: pub);
  }

  // ─── HTTP calls al mesh-gateway ──────────────────────────────────────────

  /// POST {baseUrl}/challenge  {"identity_key": "..."}
  /// ← {"challenge": "base64_32_bytes"}
  Future<String> _requestChallenge(String baseUrl, String identityKey) async {
    final response = await http.post(
      Uri.parse('$baseUrl/challenge'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identity_key': identityKey}),
    );
    if (response.statusCode != 200) {
      throw Exception('Challenge HTTP ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['challenge'] as String;
  }

  /// POST {baseUrl}/connect  {"identity_key":..., "wg_pubkey":..., "challenge":..., "signature":...}
  /// ← MeshConfig JSON
  Future<MeshConfig> _submitAuth(
    String baseUrl, {
    required String identityKey,
    required String wgPublicKey,
    required String challenge,
    required String signature,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/connect'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identity_key': identityKey,
        'wg_pubkey': wgPublicKey,
        'challenge': challenge,
        'signature': signature,
      }),
    );
    if (response.statusCode == 403) {
      _notAuthorizedController.add(null);
      throw Exception('not_authorized');
    }
    if (response.statusCode != 200) {
      throw Exception('Auth HTTP ${response.statusCode}: ${response.body}');
    }
    return MeshConfig.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // ─── WireGuard tunnel ─────────────────────────────────────────────────────

  Future<void> _startTunnel(MeshConfig config, String wgPrivateKey) async {
    final wgConfig = _buildWgConfig(config, wgPrivateKey);
    await WireGuardFlutter.instance.initialize(interfaceName: 'wg0');
    await WireGuardFlutter.instance.startVpn(
      serverAddress: config.serverEndpoint,
      wgQuickConfig: wgConfig,
      providerBundleIdentifier: 'com.invisible.invisible.network-extension',
    );
  }

  Future<void> _stopTunnel() async {
    await WireGuardFlutter.instance.stopVpn();
  }

  String _buildWgConfig(MeshConfig config, String privateKey) {
    return '[Interface]\n'
        'PrivateKey = $privateKey\n'
        'Address = ${config.assignedIp}/16\n'
        'DNS = 1.1.1.1\n'
        '\n'
        '[Peer]\n'
        'PublicKey = ${config.serverWgPubkey}\n'
        'Endpoint = ${config.serverEndpoint}\n'
        'AllowedIPs = ${config.meshNetwork}\n'
        'PersistentKeepalive = 25\n';
  }

  // ─── Firma challenge ──────────────────────────────────────────────────────

  Future<String> _signChallenge(
    String challengeBase64, {
    required String identityPrivate,
    required String identityPublic,
  }) async {
    final ed25519 = Ed25519();
    final keyPair = SimpleKeyPairData(
      base64Decode(identityPrivate),
      publicKey: SimplePublicKey(
        base64Decode(identityPublic),
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    );
    final sig = await ed25519.sign(
      base64Decode(challengeBase64),
      keyPair: keyPair,
    );
    return base64Encode(sig.bytes);
  }
}

class _WgKeyPair {
  final String privateKey;
  final String publicKey;
  _WgKeyPair({required this.privateKey, required this.publicKey});
}
