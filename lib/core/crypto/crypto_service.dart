import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:invisible/models/crypto_keys.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _random = Random.secure();

  /// Genera tutte le chiavi crittografiche per un nuovo profilo.
  /// - masterKey  (X25519): long-term DH identity key usata in X3DH
  /// - identityKey (Ed25519): firma e autenticazione
  /// - signedPreKey (X25519): pre-key separata per X3DH, firmata con identityKey
  Future<CryptoKeys> generateKeys() async {
    // Master Key: X25519 — long-term DH identity key in X3DH
    final masterKeyPair = await _generateX25519KeyPair();

    // Identity Key: Ed25519 — firme + autenticazione mesh
    final identityKeyPair = await _generateEd25519KeyPair();

    // Signed Pre-Key: X25519 — chiave DH separata dalla masterKey
    final signedPreKeyPair = await _generateX25519KeyPair();

    // Firma la SPK pubblica con la identity key → prova di proprietà
    final spkPublicBytes =
        (await signedPreKeyPair.extractPublicKey()).bytes;
    final spkSigBytes = await signData(
      identityKeyPair,
      Uint8List.fromList(spkPublicBytes),
    );

    return CryptoKeys(
      masterKeyPrivate: await _keyPairToBase64Private(masterKeyPair),
      masterKeyPublic: await _keyPairToBase64Public(masterKeyPair),
      identityKeyPrivate: await _keyPairToBase64Private(identityKeyPair),
      identityKeyPublic: await _keyPairToBase64Public(identityKeyPair),
      signedPreKeyPrivate: await _keyPairToBase64Private(signedPreKeyPair),
      signedPreKeyPublic: await _keyPairToBase64Public(signedPreKeyPair),
      signedPreKeySignature: base64Encode(spkSigBytes),
      signedPreKeyCreatedAt: DateTime.now(),
    );
  }

  /// Firma dati arbitrari con una coppia di chiavi Ed25519.
  Future<List<int>> signData(SimpleKeyPair identityKeyPair, Uint8List data) async {
    final ed25519 = Ed25519();
    final sig = await ed25519.sign(data, keyPair: identityKeyPair);
    return sig.bytes;
  }

  /// Verifica una firma Ed25519.
  Future<bool> verifySignature({
    required String identityPublicKeyBase64,
    required String dataBase64,
    required String signatureBase64,
  }) async {
    try {
      final ed25519 = Ed25519();
      final publicKey = SimplePublicKey(
        base64Decode(identityPublicKeyBase64),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        base64Decode(signatureBase64),
        publicKey: publicKey,
      );
      return await ed25519.verify(
        base64Decode(dataBase64),
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }

  /// Ricostruisce un SimpleKeyPair Ed25519 da bytes.
  Future<SimpleKeyPair> reconstructEd25519KeyPair({
    required String privateBase64,
    required String publicBase64,
  }) async {
    return SimpleKeyPairData(
      base64Decode(privateBase64),
      publicKey: SimplePublicKey(
        base64Decode(publicBase64),
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    );
  }

  /// Ricostruisce un SimpleKeyPair X25519 da bytes.
  Future<SimpleKeyPair> reconstructX25519KeyPair({
    required String privateBase64,
    required String publicBase64,
  }) async {
    return SimpleKeyPairData(
      base64Decode(privateBase64),
      publicKey: SimplePublicKey(
        base64Decode(publicBase64),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  /// Genera una coppia di chiavi X25519
  Future<SimpleKeyPair> _generateX25519KeyPair() async {
    return await X25519().newKeyPair();
  }

  /// Genera una coppia di chiavi Ed25519
  Future<SimpleKeyPair> _generateEd25519KeyPair() async {
    return await Ed25519().newKeyPair();
  }

  /// Converte la chiave privata in Base64
  Future<String> _keyPairToBase64Private(SimpleKeyPair keyPair) async {
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return base64Encode(privateKeyBytes);
  }

  /// Converte la chiave pubblica in Base64
  Future<String> _keyPairToBase64Public(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Deriva una chiave per il database dalla password usando PBKDF2
  Future<String> deriveDatabaseKey(String password, String salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    final saltBytes = utf8.encode(salt);
    final passwordBytes = utf8.encode(password);

    final derivedKey = await algorithm.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: saltBytes,
    );

    final keyBytes = await derivedKey.extractBytes();
    return _bytesToHex(Uint8List.fromList(keyBytes));
  }

  /// Genera un salt casuale per PBKDF2
  String generateSalt() {
    final saltBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Encode(saltBytes);
  }

  /// Genera un ID univoco
  String generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomBytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final combined = [..._int64ToBytes(timestamp), ...randomBytes];
    return base64Encode(combined).replaceAll('/', '_').replaceAll('+', '-');
  }

  /// Converte bytes in stringa esadecimale
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Converte int64 in bytes
  List<int> _int64ToBytes(int value) {
    return [
      (value >> 56) & 0xFF,
      (value >> 48) & 0xFF,
      (value >> 40) & 0xFF,
      (value >> 32) & 0xFF,
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  /// Valida se una chiave pubblica X25519 è valida (32 byte)
  bool isValidPublicKey(String publicKeyBase64) {
    try {
      final bytes = base64Decode(publicKeyBase64);
      return bytes.length == 32;
    } catch (e) {
      return false;
    }
  }

  /// Hash di una stringa usando SHA-256
  Future<String> hashSHA256(String input) async {
    final hash = await Sha256().hash(utf8.encode(input));
    return base64Encode(hash.bytes);
  }

  /// Ruota la Identity Key Ed25519 e la Master Key X25519.
  ///
  /// Genera nuove chiavi e crea una firma di transizione:
  ///   sig = oldIdentityKey.sign(newIdentityKeyPublic + newMasterKeyPublic)
  ///
  /// La firma permette ai contatti di verificare che la rotazione è autentica
  /// (il vecchio proprietario ha autorizzato il passaggio alla nuova chiave).
  ///
  /// Restituisce (newKeys, transitionSig) dove transitionSig è base64.
  Future<(CryptoKeys, String)> rotateIdentityKey(CryptoKeys existing) async {
    // Genera nuova identity key Ed25519
    final newIkKp = await Ed25519().newKeyPair();
    final newIkPriv = await newIkKp.extractPrivateKeyBytes();
    final newIkPub = await newIkKp.extractPublicKey();

    // Genera nuova master key X25519
    final newMkKp = await X25519().newKeyPair();
    final newMkPriv = await newMkKp.extractPrivateKeyBytes();
    final newMkPub = await newMkKp.extractPublicKey();

    // Firma di transizione: old_ik firma (new_ik_pub || new_mk_pub)
    final oldIkKp = await reconstructEd25519KeyPair(
      privateBase64: existing.identityKeyPrivate,
      publicBase64: existing.identityKeyPublic,
    );
    final payload = Uint8List.fromList(newIkPub.bytes + newMkPub.bytes);
    final sigBytes = await signData(oldIkKp, payload);

    // Genera nuova SPK firmata con la nuova identity key
    final newSpk = await X25519().newKeyPair();
    final newSpkPriv = await newSpk.extractPrivateKeyBytes();
    final newSpkPub = (await newSpk.extractPublicKey()).bytes;
    final spkSig = await signData(newIkKp, Uint8List.fromList(newSpkPub));

    final newKeys = CryptoKeys(
      masterKeyPrivate: base64Encode(Uint8List.fromList(newMkPriv)),
      masterKeyPublic: base64Encode(newMkPub.bytes),
      identityKeyPrivate: base64Encode(Uint8List.fromList(newIkPriv)),
      identityKeyPublic: base64Encode(newIkPub.bytes),
      signedPreKeyPrivate: base64Encode(Uint8List.fromList(newSpkPriv)),
      signedPreKeyPublic: base64Encode(newSpkPub),
      signedPreKeySignature: base64Encode(spkSig),
      signedPreKeyCreatedAt: DateTime.now(),
    );

    return (newKeys, base64Encode(sigBytes));
  }

  /// Verifica una firma di transizione identity key.
  ///
  /// [oldIdentityKeyBase64] = vecchia identity key Ed25519 del contatto (conosciuta)
  /// [newIdentityKeyBase64] = nuova identity key proposta
  /// [newMasterKeyBase64]   = nuova master key proposta
  /// [signatureBase64]      = firma della transizione
  Future<bool> verifyKeyRotation({
    required String oldIdentityKeyBase64,
    required String newIdentityKeyBase64,
    required String newMasterKeyBase64,
    required String signatureBase64,
  }) async {
    try {
      final newIkBytes = base64Decode(newIdentityKeyBase64);
      final newMkBytes = base64Decode(newMasterKeyBase64);
      final payload = Uint8List.fromList(newIkBytes + newMkBytes);
      return await verifySignature(
        identityPublicKeyBase64: oldIdentityKeyBase64,
        dataBase64: base64Encode(payload),
        signatureBase64: signatureBase64,
      );
    } catch (_) {
      return false;
    }
  }

  /// Genera una nuova Signed Pre-Key X25519, la firma con la identity key Ed25519
  /// e restituisce CryptoKeys aggiornato con nuova SPK e timestamp corrente.
  Future<CryptoKeys> rotateSignedPreKey(CryptoKeys existing) async {
    final newSpk = await X25519().newKeyPair();
    final privBytes = await newSpk.extractPrivateKeyBytes();
    final pubBytes = (await newSpk.extractPublicKey()).bytes;

    final identityKp = await reconstructEd25519KeyPair(
      privateBase64: existing.identityKeyPrivate,
      publicBase64: existing.identityKeyPublic,
    );
    final sigBytes = await signData(identityKp, Uint8List.fromList(pubBytes));

    return CryptoKeys(
      masterKeyPrivate: existing.masterKeyPrivate,
      masterKeyPublic: existing.masterKeyPublic,
      identityKeyPrivate: existing.identityKeyPrivate,
      identityKeyPublic: existing.identityKeyPublic,
      signedPreKeyPrivate: base64Encode(privBytes),
      signedPreKeyPublic: base64Encode(pubBytes),
      signedPreKeySignature: base64Encode(sigBytes),
      signedPreKeyCreatedAt: DateTime.now(),
    );
  }
}
