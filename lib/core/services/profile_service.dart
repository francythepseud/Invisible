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

  // FlutterSecureStorage usa iOS Keychain / Android Keystore — hardware-backed.
  // Le chiavi private non escono mai dal chip sicuro (TEE/Secure Enclave).
  // NOTA: su Android NON usiamo encryptedSharedPreferences:true perché usa un
  // backing store diverso rispetto al default (KeyStore AES-256-GCM), e
  // cambiarla romperebbe la lettura del salt dei profili esistenti.
  // Il default è già hardware-backed su tutti i dispositivi Android moderni.
  final _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );
  final _cryptoService = CryptoService();
  final _databaseService = DatabaseService();

  static const _profilesListKey = 'profiles_list';
  static const _saltPrefix = 'salt_';

  // Chiavi private nel TEE — mai nel DB
  static String _ikPrivKey(String id)  => '_ik_priv_$id';
  static String _mkPrivKey(String id)  => '_mk_priv_$id';
  static String _spkPrivKey(String id) => '_spk_priv_$id';

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

    final profileId = _cryptoService.generateId();
    final salt = _cryptoService.generateSalt();
    final dbKey = await _cryptoService.deriveDatabaseKey(credentials.password, salt);
    final cryptoKeys = await _cryptoService.generateKeys();

    // Salva le chiavi PRIVATE nel TEE (iOS Keychain / Android Keystore hardware-backed).
    // Non escono mai dal chip sicuro — anche con root o backup non sono accessibili.
    await _secureStorage.write(key: _ikPrivKey(profileId),  value: cryptoKeys.identityKeyPrivate);
    await _secureStorage.write(key: _mkPrivKey(profileId),  value: cryptoKeys.masterKeyPrivate);
    await _secureStorage.write(key: _spkPrivKey(profileId), value: cryptoKeys.signedPreKeyPrivate);

    final database = await _databaseService.getDatabase(profileId, dbKey);

    final profile = Profile(
      id: profileId,
      username: credentials.username,
      publicKey: cryptoKeys.masterKeyPublic,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );

    await database.insert('profile', profile.toJson());

    // Nel DB salviamo SOLO le chiavi pubbliche e la firma SPK — nessuna chiave privata
    await database.insert('crypto_keys', {
      'id': profileId,
      'master_key_private':       '', // vuoto — chiave privata è nel TEE
      'master_key_public':        cryptoKeys.masterKeyPublic,
      'identity_key_private':     '', // vuoto — chiave privata è nel TEE
      'identity_key_public':      cryptoKeys.identityKeyPublic,
      'signed_pre_key_private':   '', // vuoto — chiave privata è nel TEE
      'signed_pre_key_public':    cryptoKeys.signedPreKeyPublic,
      'signed_pre_key_signature': cryptoKeys.signedPreKeySignature,
      'signed_pre_key_created_at': cryptoKeys.signedPreKeyCreatedAt.millisecondsSinceEpoch,
    });

    await _secureStorage.write(key: '$_saltPrefix$profileId', value: salt);

    existingProfiles.add(profile);
    await _saveProfilesList(existingProfiles);

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

    // Elimina salt e chiavi private dal TEE
    await _secureStorage.delete(key: '$_saltPrefix$profileId');
    await _secureStorage.delete(key: _ikPrivKey(profileId));
    await _secureStorage.delete(key: _mkPrivKey(profileId));
    await _secureStorage.delete(key: _spkPrivKey(profileId));

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

  /// Ottiene le chiavi crittografiche del profilo corrente.
  /// Le chiavi private vengono lette dal TEE (Keychain/Keystore hardware-backed),
  /// le chiavi pubbliche dal DB cifrato.
  Future<CryptoKeys?> getCurrentCryptoKeys() async {
    if (_currentDatabase == null || _currentProfile == null) return null;
    final id = _currentProfile!.id;

    final result = await _currentDatabase!.query(
      'crypto_keys', where: 'id = ?', whereArgs: [id],
    );
    if (result.isEmpty) return null;

    final row = result.first;

    // Leggi chiavi private dal TEE
    final ikPriv  = await _secureStorage.read(key: _ikPrivKey(id));
    final mkPriv  = await _secureStorage.read(key: _mkPrivKey(id));
    final spkPriv = await _secureStorage.read(key: _spkPrivKey(id));

    // Migrazione automatica: se le private non sono nel TEE ma sono nel DB
    // (profilo creato con versione precedente), le migriamo nel TEE e le
    // cancelliamo dal DB.
    final ikPrivFinal  = await _migratePrivateKey(id, _ikPrivKey(id),  ikPriv,  row['identity_key_private']  as String?, row);
    final mkPrivFinal  = await _migratePrivateKey(id, _mkPrivKey(id),  mkPriv,  row['master_key_private']     as String?, row);
    final spkPrivFinal = await _migratePrivateKey(id, _spkPrivKey(id), spkPriv, row['signed_pre_key_private'] as String?, row);

    if (ikPrivFinal == null || mkPrivFinal == null || spkPrivFinal == null) {
      return null;
    }

    return CryptoKeys(
      masterKeyPrivate:       mkPrivFinal,
      masterKeyPublic:        row['master_key_public']        as String,
      identityKeyPrivate:     ikPrivFinal,
      identityKeyPublic:      row['identity_key_public']      as String,
      signedPreKeyPrivate:    spkPrivFinal,
      signedPreKeyPublic:     row['signed_pre_key_public']    as String,
      signedPreKeySignature:  (row['signed_pre_key_signature'] as String?) ?? '',
      signedPreKeyCreatedAt:  DateTime.fromMillisecondsSinceEpoch(
        row['signed_pre_key_created_at'] as int,
      ),
    );
  }

  /// Migrazione: se la chiave privata non è nel TEE ma è nel DB (vecchia versione),
  /// la sposta nel TEE e la cancella dal DB.
  Future<String?> _migratePrivateKey(
    String profileId,
    String storageKey,
    String? teeValue,
    String? dbValue,
    Map<String, dynamic> row,
  ) async {
    if (teeValue != null && teeValue.isNotEmpty) return teeValue;
    if (dbValue != null && dbValue.isNotEmpty) {
      // Sposta nel TEE
      await _secureStorage.write(key: storageKey, value: dbValue);
      // Cancella dal DB
      await _currentDatabase!.execute(
        'UPDATE crypto_keys SET identity_key_private="", master_key_private="", signed_pre_key_private="" WHERE id=?',
        [profileId],
      );
      return dbValue;
    }
    return null;
  }

  /// Aggiorna le chiavi crittografiche del profilo corrente (es. dopo rotazione SPK).
  /// Le chiavi private vengono salvate nel TEE, le pubbliche nel DB.
  Future<void> saveCryptoKeys(CryptoKeys keys) async {
    if (_currentDatabase == null || _currentProfile == null) return;
    final id = _currentProfile!.id;

    // Salva private nel TEE
    await _secureStorage.write(key: _ikPrivKey(id),  value: keys.identityKeyPrivate);
    await _secureStorage.write(key: _mkPrivKey(id),  value: keys.masterKeyPrivate);
    await _secureStorage.write(key: _spkPrivKey(id), value: keys.signedPreKeyPrivate);

    // Salva solo pubbliche nel DB
    await _currentDatabase!.update(
      'crypto_keys',
      {
        'master_key_private':       '',
        'master_key_public':        keys.masterKeyPublic,
        'identity_key_private':     '',
        'identity_key_public':      keys.identityKeyPublic,
        'signed_pre_key_private':   '',
        'signed_pre_key_public':    keys.signedPreKeyPublic,
        'signed_pre_key_signature': keys.signedPreKeySignature,
        'signed_pre_key_created_at': keys.signedPreKeyCreatedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
