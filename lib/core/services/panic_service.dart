import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invisible/core/database/database_service.dart';
import 'package:invisible/core/services/profile_service.dart';

/// Cancella TUTTI i dati dell'app: profili, chiavi, database, media, preferenze.
/// Dopo l'esecuzione l'app è come appena installata.
class PanicService {
  static final PanicService _instance = PanicService._internal();
  factory PanicService() => _instance;
  PanicService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final _profileService = ProfileService();
  final _dbService = DatabaseService();

  Future<void> wipeAll() async {
    // 1. Chiudi il database aperto
    try { await _dbService.closeDatabase(); } catch (_) {}

    // 2. Cancella tutti i database dei profili
    try {
      final profiles = await _profileService.getProfiles();
      final dbDir = await getApplicationDocumentsDirectory();
      for (final profile in profiles) {
        final dbPath = p.join(dbDir.path, 'profile_${profile.id}.db');
        final f = File(dbPath);
        if (await f.exists()) await f.delete();
        // Cancella anche journal e wal
        for (final suffix in ['-journal', '-wal', '-shm']) {
          final extra = File('$dbPath$suffix');
          if (await extra.exists()) await extra.delete();
        }
      }
    } catch (_) {}

    // 3. Cancella tutte le chiavi da FlutterSecureStorage (KeyStore/Keychain)
    try { await _secureStorage.deleteAll(); } catch (_) {}

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
