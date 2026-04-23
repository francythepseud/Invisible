import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Sealed Sender — nasconde l'identità del mittente al relay.
///
/// Schema:
///   1. Genera keypair X25519 effimera per questa busta.
///   2. DH(ephemeralPriv, recipientMasterPub) → shared secret.
///   3. HKDF → chiave AES-256-GCM.
///   4. Cifra: { sender_identity_key, inner_payload } con quella chiave.
///   5. Outer packet: { eph_pub, nonce, ciphertext } — tutto base64 JSON.
///
/// Il relay vede solo il destinatario (per instradare) e un blob opaco.
/// Solo il destinatario può aprire la busta e scoprire chi ha scritto.
class SealedSender {
  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf   = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Sigilla il payload per il destinatario.
  ///
  /// [recipientMasterPubBase64] — chiave X25519 pubblica del destinatario
  /// [senderIdentityPubBase64] — chiave Ed25519 pubblica del mittente
  ///   (viene inclusa nel plaintext cifrato così solo il destinatario la vede)
  /// [innerPayload] — base64 del payload DR già cifrato E2E
  static Future<String> seal({
    required String recipientMasterPubBase64,
    required String senderIdentityPubBase64,
    required String innerPayload,
  }) async {
    // 1. Keypair effimera — usata solo per questa busta, poi scartata
    final ephemeralKp = await _x25519.newKeyPair();
    final ephemeralPub = await ephemeralKp.extractPublicKey();

    // 2. DH con la chiave master del destinatario
    final recipientPub = SimplePublicKey(
      base64Decode(recipientMasterPubBase64),
      type: KeyPairType.x25519,
    );
    final dhSecret = await (await _x25519.sharedSecretKey(
      keyPair: ephemeralKp,
      remotePublicKey: recipientPub,
    )).extractBytes();

    // 3. HKDF per derivare chiave AES-256-GCM
    final aesKey = await _hkdf.deriveKey(
      secretKey: SecretKey(dhSecret),
      nonce: ephemeralPub.bytes,
      info: utf8.encode('invisible-sealed-sender-v1'),
    );

    // 4. Plaintext: { mittente + payload }
    final plaintext = utf8.encode(jsonEncode({
      'from': senderIdentityPubBase64,
      'p':    innerPayload,
    }));

    // 5. Cifra con AES-256-GCM
    final nonce = _aesGcm.newNonce();
    final encrypted = await _aesGcm.encrypt(
      Uint8List.fromList(plaintext),
      secretKey: aesKey,
      nonce: nonce,
    );

    // 6. Serializza: { eph_pub, nonce, ciphertext } tutto base64
    return jsonEncode({
      'e': base64Encode(ephemeralPub.bytes),
      'n': base64Encode(nonce),
      'c': base64Encode(encrypted.cipherText + encrypted.mac.bytes),
    });
  }

  /// Apre una busta sealed-sender.
  ///
  /// Ritorna [SealedMessage] con mittente e payload interni.
  /// Lancia eccezione se il MAC fallisce (busta corrotta o chiave sbagliata).
  static Future<SealedMessage> unseal({
    required String ourMasterPrivBase64,
    required String ourMasterPubBase64,
    required String sealedJson,
  }) async {
    final map = jsonDecode(sealedJson) as Map<String, dynamic>;
    final ephemeralPubBytes = base64Decode(map['e'] as String);
    final nonce             = base64Decode(map['n'] as String);
    final ciphertextAndMac  = base64Decode(map['c'] as String);

    // Separa ciphertext e MAC (ultimi 16 byte = tag GCM)
    final ciphertext = ciphertextAndMac.sublist(0, ciphertextAndMac.length - 16);
    final mac        = ciphertextAndMac.sublist(ciphertextAndMac.length - 16);

    // 1. Ricostruisce keypair locale
    final ourKp = SimpleKeyPairData(
      base64Decode(ourMasterPrivBase64),
      publicKey: SimplePublicKey(
        base64Decode(ourMasterPubBase64),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );

    // 2. DH con la chiave effimera del mittente
    final ephemeralPub = SimplePublicKey(ephemeralPubBytes, type: KeyPairType.x25519);
    final dhSecret = await (await _x25519.sharedSecretKey(
      keyPair: ourKp,
      remotePublicKey: ephemeralPub,
    )).extractBytes();

    // 3. HKDF — stessa derivazione del mittente
    final aesKey = await _hkdf.deriveKey(
      secretKey: SecretKey(dhSecret),
      nonce: ephemeralPubBytes,
      info: utf8.encode('invisible-sealed-sender-v1'),
    );

    // 4. Decifra
    final decrypted = await _aesGcm.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: aesKey,
    );

    final inner = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    return SealedMessage(
      senderIdentityKey: inner['from'] as String,
      innerPayload:      inner['p']    as String,
    );
  }
}

class SealedMessage {
  final String senderIdentityKey; // Ed25519 pubkey base64 del mittente
  final String innerPayload;      // payload DR cifrato E2E (base64 JSON)

  const SealedMessage({
    required this.senderIdentityKey,
    required this.innerPayload,
  });
}
