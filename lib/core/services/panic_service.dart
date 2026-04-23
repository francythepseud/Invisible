import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invisible/core/database/database_service.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/utils/constants.dart';

/// Cancella TUTTI i dati dell'app: profili, chiavi, database, media, preferenze.
/// Dopo l'esecuzione l'app è come appena installata.
class PanicService {
  static final PanicService _instance = PanicService._internal();
  factory PanicService() => _instance;
  PanicService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final _profileService = ProfileService();
  final _dbService = DatabaseService();

  /// Sovrascrive un file con dati casuali (3 passaggi) poi lo elimina.
  /// Riduce drasticamente la possibilità di recupero forense su flash/SSD.
  Future<void> _secureDeleteFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return;
    try {
      final size = await f.length();
      if (size > 0) {
        final rng = Random.secure();
        final buf = Uint8List(size > 65536 ? 65536 : size);
        // 3 passaggi di sovrascrittura
        for (int pass = 0; pass < 3; pass++) {
          final sink = f.openWrite();
          int written = 0;
          while (written < size) {
            final chunk = size - written < buf.length ? size - written : buf.length;
            for (int i = 0; i < chunk; i++) buf[i] = rng.nextInt(256);
            sink.add(buf.sublist(0, chunk));
            written += chunk;
          }
          await sink.flush();
          await sink.close();
        }
      }
    } catch (_) {}
    try { await f.delete(); } catch (_) {}
  }

  /// Invia la richiesta di cancellazione account al server (best-effort).
  /// Firmata con la identity key Ed25519 per prevenire cancellazioni non autorizzate.
  Future<void> _deleteAccountOnServer() async {
    try {
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
      final sig = await ed25519.sign(
        utf8.encode('invisible_delete_account'),
        keyPair: keyPair,
      );
      await http.delete(
        Uri.parse(AppConstants.tosHttpUrl.replaceAll('/tos', '/account')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identity_key': keys.identityKeyPublic,
          'signature': base64Encode(sig.bytes),
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[PANIC] deleteAccountOnServer errore (ignorato): $e');
    }
  }

  Future<void> wipeAll() async {
    // 0. Cancella account sul server (best-effort, non blocca se offline)
    await _deleteAccountOnServer();

    // 1. Chiudi il database aperto
    try { await _dbService.closeDatabase(); } catch (_) {}

    // 2. Secure-delete tutti i database dei profili:
    //    sovrascrive con dati casuali in 3 passaggi prima di eliminare.
    try {
      final profiles = await _profileService.getProfiles();
      final dbDir = await getApplicationDocumentsDirectory();
      for (final profile in profiles) {
        final dbPath = p.join(dbDir.path, 'databases', 'profile_${profile.id}.db');
        await _secureDeleteFile(dbPath);
        for (final suffix in ['-journal', '-wal', '-shm']) {
          await _secureDeleteFile('$dbPath$suffix');
        }
      }
    } catch (_) {}

    // 3. Cancella tutte le chiavi da FlutterSecureStorage (KeyStore/Keychain)
    // Prima cancella esplicitamente profiles_list per garantire che getProfiles()
    // ritorni vuoto anche se deleteAll() fallisce parzialmente su Android.
    try { await _secureStorage.delete(key: 'profiles_list'); } catch (_) {}
    try { await _secureStorage.deleteAll(); } catch (_) {}

    // 3b. Reset cache in-memory del ProfileService (singleton)
    _profileService.resetSession();

    // 4. Cancella tutta la cartella documenti dell'app (media, file allegati, ecc.)
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      for (final entity in docsDir.listSync()) {
        try { await entity.delete(recursive: true); } catch (_) {}
      }
    } catch (_) {}

    // 5. Cancella SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    // 6. Cancella cache
    try {
      final cacheDir = await getTemporaryDirectory();
      for (final entity in cacheDir.listSync()) {
        try { await entity.delete(recursive: true); } catch (_) {}
      }
    } catch (_) {}
  }
}
