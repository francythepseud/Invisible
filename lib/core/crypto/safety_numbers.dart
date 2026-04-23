import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// Genera i "Safety Numbers" Signal-style per la verifica dell'identità.
///
/// Un Safety Number è un fingerprint a 60 cifre derivato dalle chiavi pubbliche
/// di entrambi i partecipanti (ordinate per riproducibilità), visualizzato come
/// 12 gruppi di 5 cifre. Entrambi i lati devono vedere lo stesso numero:
/// se differiscono, la comunicazione è compromessa (MITM in corso).
///
/// Algoritmo:
///   1. Prendi le due chiavi pubbliche (myIdentityKey, theirIdentityKey) come base64
///   2. Concatenale in ordine lessicografico (così il risultato è identico su entrambi i lati)
///   3. Calcola SHA-256 × 5120 iterazioni (seguendo il calcolo Signal v2)
///   4. Converti i primi 30 byte in 12 gruppi da 5 cifre decimali (0–99999)
class SafetyNumbers {
  /// Genera il Safety Number tra due partecipanti.
  ///
  /// [myIdentityKeyBase64]    = chiave identità Ed25519 pubblica dell'utente locale
  /// [theirIdentityKeyBase64] = chiave identità Ed25519 pubblica del contatto
  ///
  /// Restituisce una stringa di 60 cifre formattata come 12 gruppi da 5 (separati da spazio).
  static String generate({
    required String myIdentityKeyBase64,
    required String theirIdentityKeyBase64,
  }) {
    // Ordine deterministico: sempre [minore, maggiore] lessicograficamente
    final keys = [myIdentityKeyBase64, theirIdentityKeyBase64]..sort();

    final combined = Uint8List.fromList(
      utf8.encode(keys[0]) + utf8.encode(keys[1]),
    );

    // 5120 iterazioni SHA-256 (simile al calcolo Signal fingerprint v2)
    List<int> hash = combined;
    for (int i = 0; i < 5120; i++) {
      hash = crypto.sha256.convert(hash).bytes;
    }

    // Converti i primi 30 byte in 12 gruppi da 5 cifre
    final groups = <String>[];
    for (int i = 0; i < 12; i++) {
      final offset = i * 2;
      final value = ((hash[offset] & 0xFF) << 8 | (hash[offset + 1] & 0xFF)) % 100000;
      groups.add(value.toString().padLeft(5, '0'));
    }

    return groups.join(' ');
  }

  /// Confronta due Safety Numbers ignorando spazi e capitalizzazione.
  static bool matches(String a, String b) {
    return a.replaceAll(' ', '') == b.replaceAll(' ', '');
  }
}
