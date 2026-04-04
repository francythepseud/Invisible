import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Risultato della cifratura di un file media.
class MediaEncryptResult {
  final String encryptedBase64; // ciphertext AES-256-GCM in base64
  final String keyBase64;       // chiave AES-256 in base64
  final String nonceBase64;     // nonce 12 byte in base64

  const MediaEncryptResult({
    required this.encryptedBase64,
    required this.keyBase64,
    required this.nonceBase64,
  });
}

/// Cifra e decifra file media con AES-256-GCM.
///
/// La chiave e il nonce sono generati casualmente per ogni file
/// e incorporati nel payload del Double Ratchet (mai visibili al relay).
class MediaCryptoService {
  static final MediaCryptoService _instance = MediaCryptoService._internal();
  factory MediaCryptoService() => _instance;
  MediaCryptoService._internal();

  final _aesGcm = AesGcm.with256bits();
  final _random = Random.secure();

  /// Cifra i bytes di un file media con una chiave AES-256 casuale.
  /// Restituisce ciphertext, chiave e nonce in base64.
  Future<MediaEncryptResult> encryptFile(Uint8List bytes) async {
    final keyBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final nonceBytes = List<int>.generate(12, (_) => _random.nextInt(256));

    final secretKey = SecretKey(keyBytes);
    final secretBox = await _aesGcm.encrypt(
      bytes,
      secretKey: secretKey,
      nonce: nonceBytes,
    );

    // ciphertext include il MAC (16 byte) in coda
    final ciphertextWithMac = Uint8List.fromList(
      secretBox.cipherText + secretBox.mac.bytes,
    );

    return MediaEncryptResult(
      encryptedBase64: base64Encode(ciphertextWithMac),
      keyBase64: base64Encode(keyBytes),
      nonceBase64: base64Encode(nonceBytes),
    );
  }

  /// Decifra un file media con la chiave e il nonce forniti.
  Future<Uint8List> decryptMedia(
    String encryptedBase64,
    String keyBase64,
    String nonceBase64,
  ) async {
    final raw = base64Decode(encryptedBase64);
    // Ultimi 16 byte = MAC GCM
    final mac = raw.sublist(raw.length - 16);
    final ciphertext = raw.sublist(0, raw.length - 16);

    final secretKey = SecretKey(base64Decode(keyBase64));
    final secretBox = SecretBox(
      ciphertext,
      nonce: base64Decode(nonceBase64),
      mac: Mac(mac),
    );

    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(plainBytes);
  }
}
