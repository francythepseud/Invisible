import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invisible/utils/constants.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/core/crypto/crypto_service.dart';
import 'package:invisible/core/network/pinned_http_client.dart';

/// Gestisce l'accettazione dei Termini di Servizio per ogni profilo.
///
/// Ogni profilo è identificato dalla sua identity_key Ed25519 (unica, crittografica).
/// - SharedPreferences: chiave per-profilo → un device con 3 profili ha 3 accettazioni distinte
/// - PostgreSQL centrale: un record per (identity_hash, tos_version) — admin può vedere tutto
class TosService {
  static final TosService _instance = TosService._internal();
  factory TosService() => _instance;
  TosService._internal();

  final _profileService = ProfileService();
  final _cryptoService  = CryptoService();

  /// Chiave SharedPreferences per-profilo: "tos_accepted_v1.0_{primi16charDellIdentityKey}"
  Future<String?> _prefKeyForCurrentProfile() async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) return null;
    // Usa i primi 16 caratteri della identity key pubblica come suffisso leggibile
    final suffix = keys.identityKeyPublic.length >= 16
        ? keys.identityKeyPublic.substring(0, 16)
        : keys.identityKeyPublic;
    return '${AppConstants.tosKey}${AppConstants.tosVersion}_$suffix';
  }

  /// Controlla se il profilo corrente ha già accettato la ToS corrente.
  /// Ritorna false se nessun profilo è loggato.
  Future<bool> hasAccepted() async {
    final key = await _prefKeyForCurrentProfile();
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  /// Registra l'accettazione per il profilo corrente:
  /// 1. Salva localmente in SharedPreferences (per-profilo)
  /// 2. Invia al server PostgreSQL con firma Ed25519 come prova legale
  Future<void> accept() async {
    final key = await _prefKeyForCurrentProfile();
    if (key == null) return;

    // 1. Salva localmente — immediato, anche se il server non risponde
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    await prefs.setString('${key}_at', DateTime.now().toIso8601String());

    // 2. Invia al server in background
    try {
      await _sendToServer();
    } catch (e) {
      debugPrint('[TOS] Invio server fallito: $e — salvato solo localmente');
    }
  }

  Future<void> _sendToServer() async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null) return;

    // Ricostruisce la chiave privata Ed25519 del profilo corrente
    final identityKeyPair = await _cryptoService.reconstructEd25519KeyPair(
      privateBase64: keys.identityKeyPrivate,
      publicBase64:  keys.identityKeyPublic,
    );

    // Firma il payload — deve corrispondere esattamente al server Go
    final payload  = 'invisible_tos_v${AppConstants.tosVersion}_accepted';
    final sigBytes = await _cryptoService.signData(
      identityKeyPair,
      Uint8List.fromList(utf8.encode(payload)),
    );

    final profile = _profileService.currentProfile;
    final body = jsonEncode({
      'identity_key': keys.identityKeyPublic,       // Ed25519 pubkey del profilo
      'tos_version':  AppConstants.tosVersion,
      'app_version':  AppConstants.appVersion,
      'platform':     Platform.isIOS ? 'ios' : 'android',
      'username':     profile?.username ?? '',       // nome utente per la dashboard admin
      'signature':    base64Encode(sigBytes),        // prova crittografica del consenso
    });

    final uri    = Uri.parse('${AppConstants.tosHttpUrl}/accept');
    final client = PinnedHttpClient.create();
    try {
      final request = await client.postUrl(uri)
        ..headers.contentType = ContentType.json
        ..write(body);
      final response = await request.close();
      if (response.statusCode == 200) {
        debugPrint('[TOS] Accettazione registrata sul server per questo profilo');
      } else {
        debugPrint('[TOS] Server risponde ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}
