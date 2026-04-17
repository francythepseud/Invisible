import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:invisible/core/crypto/crypto_service.dart';
import 'package:invisible/core/database/database_service.dart';
import 'package:invisible/models/profile.dart';
import 'package:invisible/models/crypto_keys.dart';
import 'package:invisible/models/user_credentials.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );
  final _cryptoService = CryptoService();
  final _databaseService = DatabaseService();

  static const _profilesListKey = 'profiles_list';
  static const _saltPrefix = 'salt_';

  Profile? _currentProfile;
  Database? _currentDatabase;

  Profile? get currentProfile => _currentProfile;
  Database? get currentDatabase => _currentDatabase;

  /// Ottiene la lista di tutti i profili salvati
  Future<List<Profile>> getProfiles() async {
    try {
      final profilesJson = await _secureStorage.read(key: _profilesListKey);
      if (profilesJson == null) {
        return [];
      }

      final List<dynamic> profilesList = jsonDecode(profilesJson);
      return profilesList.map((json) => Profile.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Verifica se esistono profili
  Future<bool> hasProfiles() async {
    final profiles = await getProfiles();
    return profiles.isNotEmpty;
  }

  /// Crea un nuovo profilo
  Future<Profile> createProfile(UserCredentials credentials) async {
    // Verifica che lo username non esista già
    final existingProfiles = await getProfiles();
    final usernameExists = existingProfiles.any(
      (p) => p.username.toLowerCase() == credentials.username.toLowerCase(),
    );

    if (usernameExists) {
      throw Exception('Attenzione: username già in uso, sceglierne un altro');
    }

    // Genera ID profilo
    final profileId = _cryptoService.generateId();

    // Genera salt per PBKDF2
    final salt = _cryptoService.generateSalt();

    // Deriva la chiave del database dalla password
    final dbKey = await _cryptoService.deriveDatabaseKey(
      credentials.password,
      salt,
    );

    // Genera chiavi crittografiche
    final cryptoKeys = await _cryptoService.generateKeys();

    // Crea database criptato
    final database = await _databaseService.getDatabase(profileId, dbKey);

    // Crea profilo
    final profile = Profile(
      id: profileId,
      username: credentials.username,
      publicKey: cryptoKeys.masterKeyPublic,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );

    // Salva profilo nel database
    await database.insert('profile', profile.toJson());

    // Salva chiavi crittografiche nel database
    await database.insert('crypto_keys', {
      'id': profileId,
      ...cryptoKeys.toJson(),
    });

    // Salva salt in secure storage
    await _secureStorage.write(
      key: '$_saltPrefix$profileId',
      value: salt,
    );

    // Aggiorna lista profili
    existingProfiles.add(profile);
    await _saveProfilesList(existingProfiles);

    // Imposta come profilo corrente
    _currentProfile = profile;
    _currentDatabase = database;

    return profile;
  }

  /// Effettua il login con un profilo esistente
  Future<Profile> login(UserCredentials credentials) async {
    // Trova il profilo con lo username specificato
    final profiles = await getProfiles();
    final profile = profiles.firstWhere(
      (p) => p.username.toLowerCase() == credentials.username.toLowerCase(),
      orElse: () => throw Exception('Attenzione: username non esistente'),
    );

    // Ottieni il salt
    final salt = await _secureStorage.read(key: '$_saltPrefix${profile.id}');
    if (salt == null) {
      throw Exception('Attenzione: dati di accesso non validi');
    }

    // Deriva la chiave del database dalla password
    final dbKey = await _cryptoService.deriveDatabaseKey(
      credentials.password,
      salt,
    );

    // Prova ad aprire il database
    try {
      final database = await _databaseService.getDatabase(profile.id, dbKey);

      // Verifica che il database sia valido leggendo il profilo
      final result = await database.query(
        'profile',
        where: 'id = ?',
        whereArgs: [profile.id],
      );

      if (result.isEmpty) {
        throw Exception('Attenzione: password errata');
      }

      // Aggiorna last_login_at
      final updatedProfile = profile.copyWith(lastLoginAt: DateTime.now());
      await database.update(
        'profile',
        {'last_login_at': updatedProfile.lastLoginAt!.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [profile.id],
      );

      // Aggiorna lista profili
      final updatedProfiles = profiles.map((p) {
        return p.id == updatedProfile.id ? updatedProfile : p;
      }).toList();
      await _saveProfilesList(updatedProfiles);

      // Imposta come profilo corrente
      _currentProfile = updatedProfile;
      _currentDatabase = database;

      return updatedProfile;
    } catch (e) {
      // Se fallisce l'apertura del database, probabilmente la password è errata
      await _databaseService.closeDatabase();
      throw Exception('Password errata');
    }
  }

  /// Effettua il logout
  Future<void> logout() async {
    await _databaseService.closeDatabase();
    _currentProfile = null;
    _currentDatabase = null;
  }

  /// Elimina il profilo correntemente loggato
  Future<void> deleteCurrentProfile() async {
    final id = _currentProfile?.id;
    if (id == null) return;
    await deleteProfile(id);
  }

  /// Elimina un profilo
  Future<void> deleteProfile(String profileId) async {
    // Chiudi database se è quello corrente
    if (_currentProfile?.id == profileId) {
      await logout();
    }

    // Elimina database
    await _databaseService.deleteDatabase(profileId);

    // Elimina salt
    await _secureStorage.delete(key: '$_saltPrefix$profileId');

    // Rimuovi dalla lista profili
    final profiles = await getProfiles();
    final updatedProfiles = profiles.where((p) => p.id != profileId).toList();
    await _saveProfilesList(updatedProfiles);
  }

  /// Salva la lista dei profili
  Future<void> _saveProfilesList(List<Profile> profiles) async {
    final profilesJson = jsonEncode(
      profiles.map((p) => p.toJson()).toList(),
    );
    await _secureStorage.write(key: _profilesListKey, value: profilesJson);
  }

  /// Ottiene le chiavi crittografiche del profilo corrente
  Future<CryptoKeys?> getCurrentCryptoKeys() async {
    if (_currentDatabase == null || _currentProfile == null) {
      return null;
    }

    final result = await _currentDatabase!.query(
      'crypto_keys',
      where: 'id = ?',
      whereArgs: [_currentProfile!.id],
    );

    if (result.isEmpty) {
      return null;
    }

    return CryptoKeys.fromJson(result.first);
  }

  /// Aggiorna le chiavi crittografiche del profilo corrente (es. dopo rotazione SPK).
  Future<void> saveCryptoKeys(CryptoKeys keys) async {
    if (_currentDatabase == null || _currentProfile == null) return;
    await _currentDatabase!.update(
      'crypto_keys',
      keys.toJson(),
      where: 'id = ?',
      whereArgs: [_currentProfile!.id],
    );
  }
}
