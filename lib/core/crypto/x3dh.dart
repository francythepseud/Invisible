import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// X3DH (Extended Triple Diffie-Hellman) Key Agreement Protocol
/// Implementazione del protocollo usato da Signal per stabilire shared secret
class X3DH {
  final X25519 _x25519 = X25519();

  /// Esegue X3DH come iniziatore (Alice)
  /// Ritorna: (sharedSecret, ephemeralPublicKey)
  Future<X3DHResult> performAsInitiator({
    required SimpleKeyPair myIdentityKey,
    required PublicKey theirIdentityKey,
    required PublicKey theirSignedPreKey,
    PublicKey? theirOneTimePreKey,
  }) async {
    // Genera ephemeral key
    final ephemeralKey = await _x25519.newKeyPair();

    // Esegui 4 Diffie-Hellman
    final dh1 = await _dh(myIdentityKey, theirSignedPreKey);
    final dh2 = await _dh(ephemeralKey, theirIdentityKey);
    final dh3 = await _dh(ephemeralKey, theirSignedPreKey);

    // Prefisso F = 0xFF × 32 come da specifica X3DH di Signal
    // Garantisce che il KM non sia mai zero anche in corner case DH
    final F = List.filled(32, 0xFF);
    List<int> dhOutputs = [...F, ...dh1, ...dh2, ...dh3];

    // DH4 opzionale con one-time pre-key
    if (theirOneTimePreKey != null) {
      final dh4 = await _dh(ephemeralKey, theirOneTimePreKey);
      dhOutputs.addAll(dh4);
    }

    // Deriva shared secret con KDF
    final sharedSecret = await _kdf(Uint8List.fromList(dhOutputs));

    final ephemeralPublicKey = await ephemeralKey.extractPublicKey();

    return X3DHResult(
      sharedSecret: sharedSecret,
      ephemeralPublicKey: ephemeralPublicKey,
    );
  }

  /// Esegue X3DH come ricevente (Bob)
  /// Ritorna: sharedSecret
  Future<Uint8List> performAsResponder({
    required SimpleKeyPair myIdentityKey,
    required SimpleKeyPair mySignedPreKey,
    SimpleKeyPair? myOneTimePreKey,
    required PublicKey theirIdentityKey,
    required PublicKey theirEphemeralKey,
  }) async {
    // Esegui 4 Diffie-Hellman (ordine inverso rispetto all'iniziatore)
    final dh1 = await _dh(mySignedPreKey, theirIdentityKey);
    final dh2 = await _dh(myIdentityKey, theirEphemeralKey);
    final dh3 = await _dh(mySignedPreKey, theirEphemeralKey);

    // Stesso prefisso F del lato initiator — entrambi devono usarlo
    final F = List.filled(32, 0xFF);
    List<int> dhOutputs = [...F, ...dh1, ...dh2, ...dh3];

    // DH4 opzionale con one-time pre-key
    if (myOneTimePreKey != null) {
      final dh4 = await _dh(myOneTimePreKey, theirEphemeralKey);
      dhOutputs.addAll(dh4);
    }

    // Deriva shared secret con KDF
    return await _kdf(Uint8List.fromList(dhOutputs));
  }

  /// Esegue Diffie-Hellman tra due chiavi
  Future<List<int>> _dh(SimpleKeyPair privateKey, PublicKey publicKey) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: privateKey,
      remotePublicKey: publicKey,
    );
    return await sharedSecret.extractBytes();
  }

  /// Key Derivation Function usando HKDF-SHA256
  Future<Uint8List> _kdf(Uint8List input) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32, // 256 bit
    );

    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(input),
      nonce: Uint8List(32), // Salt vuoto per semplicità
      info: utf8.encode('Invisible-X3DH'),
    );

    return Uint8List.fromList(await derivedKey.extractBytes());
  }
}

/// Risultato di X3DH per l'iniziatore
class X3DHResult {
  final Uint8List sharedSecret;
  final PublicKey ephemeralPublicKey;

  X3DHResult({
    required this.sharedSecret,
    required this.ephemeralPublicKey,
  });
}
