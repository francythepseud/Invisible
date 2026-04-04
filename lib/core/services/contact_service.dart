import 'package:invisible/core/crypto/crypto_service.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/contact.dart';

class ContactService {
  static final ContactService _instance = ContactService._internal();
  factory ContactService() => _instance;
  ContactService._internal();

  final _profileService = ProfileService();
  final _cryptoService = CryptoService();

  /// Ottiene tutti i contatti
  Future<List<Contact>> getContacts() async {
    final db = _profileService.currentDatabase;
    if (db == null) {
      throw Exception('Nessun database aperto');
    }

    final results = await db.query(
      'contacts',
      where: 'blocked = ?',
      whereArgs: [0],
      orderBy: 'name ASC',
    );

    return results.map((json) => Contact.fromJson(json)).toList();
  }

  /// Aggiunge un contatto da QR code.
  /// [identityKey]     = Ed25519 pubkey del contatto (firma/auth)
  /// [signedPreKey]    = X25519 SPK separata per X3DH
  /// [signedPreKeySig] = firma Ed25519 della SPK (verifica proprietà)
  Future<Contact> addContact(
    String name,
    String publicKey, {
    String? identityKey,
    String? signedPreKey,
    String? signedPreKeySig,
  }) async {
    final db = _profileService.currentDatabase;
    if (db == null) throw Exception('Nessun database aperto');

    if (!_cryptoService.isValidPublicKey(publicKey)) {
      throw Exception('Chiave pubblica non valida');
    }

    // Verifica firma SPK se il QR include le chiavi complete
    if (identityKey != null && signedPreKey != null && signedPreKeySig != null) {
      final valid = await _cryptoService.verifySignature(
        identityPublicKeyBase64: identityKey,
        dataBase64: signedPreKey,
        signatureBase64: signedPreKeySig,
      );
      if (!valid) {
        throw Exception('Firma SPK non valida — QR corrotto o manomesso');
      }
    }

    final existing = await db.query(
      'contacts',
      where: 'public_key = ?',
      whereArgs: [publicKey],
    );
    if (existing.isNotEmpty) throw Exception('Contatto già esistente');

    final contact = Contact(
      id: _cryptoService.generateId(),
      name: name,
      publicKey: publicKey,
      identityKey: identityKey,
      signedPreKey: signedPreKey,
      signedPreKeySig: signedPreKeySig,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await db.insert('contacts', contact.toJson());
    return contact;
  }

  /// Ottiene un contatto per ID
  Future<Contact?> getContact(String contactId) async {
    final db = _profileService.currentDatabase;
    if (db == null) {
      throw Exception('Nessun database aperto');
    }

    final results = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [contactId],
    );

    if (results.isEmpty) {
      return null;
    }

    return Contact.fromJson(results.first);
  }

  /// Aggiorna un contatto
  Future<void> updateContact(Contact contact) async {
    final db = _profileService.currentDatabase;
    if (db == null) {
      throw Exception('Nessun database aperto');
    }

    await db.update(
      'contacts',
      contact.copyWith(updatedAt: DateTime.now()).toJson(),
      where: 'id = ?',
      whereArgs: [contact.id],
    );
  }

  /// Elimina un contatto
  Future<void> deleteContact(String contactId) async {
    final db = _profileService.currentDatabase;
    if (db == null) {
      throw Exception('Nessun database aperto');
    }

    await db.delete(
      'contacts',
      where: 'id = ?',
      whereArgs: [contactId],
    );
  }

  /// Blocca/sblocca un contatto
  Future<void> toggleBlock(String contactId) async {
    final contact = await getContact(contactId);
    if (contact == null) {
      throw Exception('Contatto non trovato');
    }

    await updateContact(contact.copyWith(blocked: !contact.blocked));
  }
}
