import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Double Ratchet Protocol Implementation
/// Protocollo di ratcheting usato da Signal per forward secrecy
class DoubleRatchet {
  final X25519 _x25519 = X25519();
  final Hmac _hmac = Hmac.sha256();

  /// Inizializza Double Ratchet come sender (Alice)
  Future<RatchetState> initializeAsSender({
    required Uint8List sharedSecret,
    required PublicKey theirRatchetPublicKey,
  }) async {
    // Genera il nostro primo DH ratchet key pair
    final ourRatchetKey = await _x25519.newKeyPair();

    // Esegui DH per ottenere nuovo shared secret
    final dhOutput = await _performDH(ourRatchetKey, theirRatchetPublicKey);

    // Deriva root key e chain key
    final kdfOutput = await _kdfRK(sharedSecret, dhOutput);

    return RatchetState(
      rootKey: kdfOutput.rootKey,
      sendingChainKey: kdfOutput.chainKey,
      receivingChainKey: null,
      ourRatchetKeyPair: ourRatchetKey,
      theirRatchetPublicKey: theirRatchetPublicKey,
      sendCount: 0,
      receiveCount: 0,
      previousSendCount: 0,
    );
  }

  /// Inizializza Double Ratchet come receiver (Bob)
  Future<RatchetState> initializeAsReceiver({
    required Uint8List sharedSecret,
    required SimpleKeyPair ourRatchetKeyPair,
  }) async {
    return RatchetState(
      rootKey: sharedSecret,
      sendingChainKey: null,
      receivingChainKey: null,
      ourRatchetKeyPair: ourRatchetKeyPair,
      theirRatchetPublicKey: null,
      sendCount: 0,
      receiveCount: 0,
      previousSendCount: 0,
    );
  }

  /// Cripta un messaggio
  Future<EncryptedMessage> encrypt(
    RatchetState state,
    Uint8List plaintext,
  ) async {
    // Se non abbiamo sending chain key, dobbiamo fare DH ratchet
    if (state.sendingChainKey == null) {
      throw Exception('Cannot encrypt: no sending chain key');
    }

    // Deriva message key dalla chain key
    final kdfOutput = await _kdfCK(state.sendingChainKey!);
    final messageKey = kdfOutput.messageKey;
    final newChainKey = kdfOutput.chainKey;

    // Cripta il messaggio
    final ciphertext = await _encryptWithMessageKey(
      messageKey,
      plaintext,
      state.sendCount,
    );

    // Aggiorna lo stato
    final newState = state.copyWith(
      sendingChainKey: newChainKey,
      sendCount: state.sendCount + 1,
    );

    final ourPublicKey = await state.ourRatchetKeyPair.extractPublicKey();

    return EncryptedMessage(
      ciphertext: ciphertext,
      header: MessageHeader(
        publicKey: ourPublicKey,
        messageNumber: state.sendCount,
        previousChainLength: state.previousSendCount,
      ),
      newState: newState,
    );
  }

  /// Decripta un messaggio
  Future<DecryptedMessage> decrypt(
    RatchetState state,
    EncryptedMessage encryptedMessage,
  ) async {
    RatchetState currentState = state;

    // Se la public key è diversa, esegui DH ratchet
    if (currentState.theirRatchetPublicKey == null ||
        !_publicKeysEqual(
          currentState.theirRatchetPublicKey!,
          encryptedMessage.header.publicKey,
        )) {
      currentState = await _performDHRatchet(
        currentState,
        encryptedMessage.header.publicKey,
      );
    }

    // Salta messaggi se necessario
    while (currentState.receiveCount < encryptedMessage.header.messageNumber) {
      if (currentState.receivingChainKey == null) {
        throw Exception('Cannot decrypt: no receiving chain key');
      }

      final kdfOutput = await _kdfCK(currentState.receivingChainKey!);
      currentState = currentState.copyWith(
        receivingChainKey: kdfOutput.chainKey,
        receiveCount: currentState.receiveCount + 1,
      );
    }

    // Deriva message key
    if (currentState.receivingChainKey == null) {
      throw Exception('Cannot decrypt: no receiving chain key');
    }

    final kdfOutput = await _kdfCK(currentState.receivingChainKey!);
    final messageKey = kdfOutput.messageKey;

    // Decripta il messaggio
    final plaintext = await _decryptWithMessageKey(
      messageKey,
      encryptedMessage.ciphertext,
      encryptedMessage.header.messageNumber,
    );

    // Aggiorna lo stato
    final newState = currentState.copyWith(
      receivingChainKey: kdfOutput.chainKey,
      receiveCount: currentState.receiveCount + 1,
    );

    return DecryptedMessage(
      plaintext: plaintext,
      newState: newState,
    );
  }

  /// Esegue DH ratchet step
  Future<RatchetState> _performDHRatchet(
    RatchetState state,
    PublicKey theirNewPublicKey,
  ) async {
    // Salva previous chain length
    final previousSendCount = state.sendCount;

    // Esegui DH con la loro nuova chiave
    final dhOutput = await _performDH(
      state.ourRatchetKeyPair,
      theirNewPublicKey,
    );

    // Deriva nuova root key e receiving chain key
    final kdfRKOutput = await _kdfRK(state.rootKey, dhOutput);

    // Genera nuovo DH key pair
    final newRatchetKey = await _x25519.newKeyPair();

    // Esegui DH con nuovo key pair
    final dhOutput2 = await _performDH(newRatchetKey, theirNewPublicKey);

    // Deriva nuova root key e sending chain key
    final kdfRKOutput2 = await _kdfRK(kdfRKOutput.rootKey, dhOutput2);

    return state.copyWith(
      rootKey: kdfRKOutput2.rootKey,
      sendingChainKey: kdfRKOutput2.chainKey,
      receivingChainKey: kdfRKOutput.chainKey,
      ourRatchetKeyPair: newRatchetKey,
      theirRatchetPublicKey: theirNewPublicKey,
      sendCount: 0,
      receiveCount: 0,
      previousSendCount: previousSendCount,
    );
  }

  /// KDF per Root Key (deriva RK e CK da RK e DH output)
  Future<KDFRKOutput> _kdfRK(Uint8List rootKey, Uint8List dhOutput) async {
    final hkdf = Hkdf(hmac: _hmac, outputLength: 64);

    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(rootKey),
      nonce: dhOutput,
      info: utf8.encode('Invisible-RK'),
    );

    final bytes = await derivedKey.extractBytes();
    return KDFRKOutput(
      rootKey: Uint8List.fromList(bytes.sublist(0, 32)),
      chainKey: Uint8List.fromList(bytes.sublist(32, 64)),
    );
  }

  /// KDF per Chain Key (deriva MK e nuova CK da CK)
  Future<KDFCKOutput> _kdfCK(Uint8List chainKey) async {
    // Message Key = HMAC(CK, 0x01)
    final messageKeyMac = await _hmac.calculateMac(
      [0x01],
      secretKey: SecretKey(chainKey),
    );

    // New Chain Key = HMAC(CK, 0x02)
    final chainKeyMac = await _hmac.calculateMac(
      [0x02],
      secretKey: SecretKey(chainKey),
    );

    return KDFCKOutput(
      messageKey: Uint8List.fromList(messageKeyMac.bytes),
      chainKey: Uint8List.fromList(chainKeyMac.bytes),
    );
  }

  /// Esegue Diffie-Hellman
  Future<Uint8List> _performDH(
    SimpleKeyPair ourKey,
    PublicKey theirKey,
  ) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ourKey,
      remotePublicKey: theirKey,
    );
    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  /// Genera 12 byte casuali crittograficamente sicuri per il nonce
  Uint8List _randomNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
  }

  /// Cripta con message key usando AES-256-GCM
  Future<Uint8List> _encryptWithMessageKey(
    Uint8List messageKey,
    Uint8List plaintext,
    int messageNumber,
  ) async {
    final aesGcm = AesGcm.with256bits();

    // Nonce casuale a 12 byte — evita keystream reuse anche se la chain key
    // venisse in qualche modo riutilizzata dopo un DH ratchet step
    final nonce = _randomNonce();

    final secretBox = await aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(messageKey),
      nonce: nonce,
    );

    // Combina nonce + ciphertext + mac
    return Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// Decripta con message key usando AES-256-GCM
  Future<Uint8List> _decryptWithMessageKey(
    Uint8List messageKey,
    Uint8List encrypted,
    int messageNumber,
  ) async {
    final aesGcm = AesGcm.with256bits();

    // Estrai componenti
    final nonce = encrypted.sublist(0, 12);
    final ciphertext = encrypted.sublist(12, encrypted.length - 16);
    final mac = Mac(encrypted.sublist(encrypted.length - 16));

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: mac,
    );

    return Uint8List.fromList(
      await aesGcm.decrypt(
        secretBox,
        secretKey: SecretKey(messageKey),
      ),
    );
  }

  /// Confronta due chiavi pubbliche
  bool _publicKeysEqual(PublicKey a, PublicKey b) {
    final aBytes = (a as SimplePublicKey).bytes;
    final bBytes = (b as SimplePublicKey).bytes;
    return const ListEquality().equals(aBytes, bBytes);
  }


}

class ListEquality {
  const ListEquality();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Stato del Double Ratchet
class RatchetState {
  final Uint8List rootKey;
  final Uint8List? sendingChainKey;
  final Uint8List? receivingChainKey;
  final SimpleKeyPair ourRatchetKeyPair;
  final PublicKey? theirRatchetPublicKey;
  final int sendCount;
  final int receiveCount;
  final int previousSendCount;

  RatchetState({
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
    required this.ourRatchetKeyPair,
    required this.theirRatchetPublicKey,
    required this.sendCount,
    required this.receiveCount,
    required this.previousSendCount,
  });

  RatchetState copyWith({
    Uint8List? rootKey,
    Uint8List? sendingChainKey,
    Uint8List? receivingChainKey,
    SimpleKeyPair? ourRatchetKeyPair,
    PublicKey? theirRatchetPublicKey,
    int? sendCount,
    int? receiveCount,
    int? previousSendCount,
  }) {
    return RatchetState(
      rootKey: rootKey ?? this.rootKey,
      sendingChainKey: sendingChainKey ?? this.sendingChainKey,
      receivingChainKey: receivingChainKey ?? this.receivingChainKey,
      ourRatchetKeyPair: ourRatchetKeyPair ?? this.ourRatchetKeyPair,
      theirRatchetPublicKey:
          theirRatchetPublicKey ?? this.theirRatchetPublicKey,
      sendCount: sendCount ?? this.sendCount,
      receiveCount: receiveCount ?? this.receiveCount,
      previousSendCount: previousSendCount ?? this.previousSendCount,
    );
  }
}

class KDFRKOutput {
  final Uint8List rootKey;
  final Uint8List chainKey;
  KDFRKOutput({required this.rootKey, required this.chainKey});
}

class KDFCKOutput {
  final Uint8List messageKey;
  final Uint8List chainKey;
  KDFCKOutput({required this.messageKey, required this.chainKey});
}

class MessageHeader {
  final PublicKey publicKey;
  final int messageNumber;
  final int previousChainLength;

  MessageHeader({
    required this.publicKey,
    required this.messageNumber,
    required this.previousChainLength,
  });
}

class EncryptedMessage {
  final Uint8List ciphertext;
  final MessageHeader header;
  final RatchetState newState;

  EncryptedMessage({
    required this.ciphertext,
    required this.header,
    required this.newState,
  });
}

class DecryptedMessage {
  final Uint8List plaintext;
  final RatchetState newState;

  DecryptedMessage({
    required this.plaintext,
    required this.newState,
  });
}
