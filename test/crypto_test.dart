import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invisible/core/crypto/x3dh.dart';
import 'package:invisible/core/crypto/double_ratchet.dart';

void main() {
  test('X3DH + Double Ratchet: Alice cifra, Bob decifra', () async {
    final x25519 = X25519();

    // Chiavi Alice
    final aliceIdentity = await x25519.newKeyPair();
    final aliceSpk = await x25519.newKeyPair();

    // Chiavi Bob
    final bobIdentity = await x25519.newKeyPair();
    final bobSpk = await x25519.newKeyPair();

    final aliceIdentityPub = await aliceIdentity.extractPublicKey();
    final bobIdentityPub = await bobIdentity.extractPublicKey();
    final bobSpkPub = await bobSpk.extractPublicKey();

    // Alice X3DH initiator
    final x3dh = X3DH();
    final aliceResult = await x3dh.performAsInitiator(
      myIdentityKey: aliceIdentity,
      theirIdentityKey: bobIdentityPub,
      theirSignedPreKey: bobSpkPub,
    );

    print('Alice shared: ${base64Encode(aliceResult.sharedSecret)}');

    // Bob X3DH responder
    final bobSecret = await x3dh.performAsResponder(
      myIdentityKey: bobIdentity,
      mySignedPreKey: bobSpk,
      theirIdentityKey: aliceIdentityPub,
      theirEphemeralKey: aliceResult.ephemeralPublicKey,
    );

    print('Bob shared:   ${base64Encode(bobSecret)}');
    expect(base64Encode(aliceResult.sharedSecret), equals(base64Encode(bobSecret)),
        reason: 'Shared secrets devono essere uguali');

    // Double Ratchet
    final dr = DoubleRatchet();
    final aliceState = await dr.initializeAsSender(
      sharedSecret: aliceResult.sharedSecret,
      theirRatchetPublicKey: bobSpkPub,
    );
    final bobState = await dr.initializeAsReceiver(
      sharedSecret: bobSecret,
      ourRatchetKeyPair: bobSpk,
    );

    expect(aliceState.sendingChainKey, isNotNull, reason: 'Alice deve avere sendingChainKey');
    expect(bobState.sendingChainKey, isNull, reason: 'Bob receiver non ha sendingChainKey');

    // Alice cifra
    final plaintext = Uint8List.fromList(utf8.encode('ciao bob'));
    final encrypted = await dr.encrypt(aliceState, plaintext);
    print('Cifrato: ${encrypted.ciphertext.length} bytes');

    // Bob decifra
    final decrypted = await dr.decrypt(bobState, encrypted);
    final msg = utf8.decode(decrypted.plaintext);
    print('Decifrato: "$msg"');
    expect(msg, equals('ciao bob'));
  });
}
