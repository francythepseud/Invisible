import 'dart:math';
import 'dart:typed_data';

/// Padding a blocchi fissi per nascondere la lunghezza dei messaggi.
///
/// Un osservatore che intercetta il traffico cifrato può inferire il tipo
/// di contenuto (testo breve, testo lungo, immagine) dalla dimensione del
/// ciphertext. Il padding porta ogni plaintext alla dimensione del blocco
/// più piccolo che lo contiene, rendendo i messaggi indistinguibili per
/// dimensione.
///
/// Schema:
///   [2 byte big-endian: lunghezza reale] [payload] [random padding fino al blocco]
///
/// Blocchi: 256 B · 1 KB · 8 KB · 64 KB · 512 KB
/// Un messaggio di testo breve (<254 B) avrà sempre ciphertext da 256 B.
/// Un'immagine piccola (<8 KB) avrà sempre ciphertext da 8 KB.
class MessagePadding {
  static const _blockSizes = [256, 1024, 8192, 65536, 524288];

  /// Aggiunge padding al [data] portandolo al blocco successivo.
  static Uint8List pad(Uint8List data) {
    // +2 per i 2 byte del length prefix
    final needed = data.length + 2;
    final target = _blockSizes.firstWhere(
      (s) => s >= needed,
      orElse: () => ((needed ~/ 524288) + 1) * 524288,
    );

    final out = Uint8List(target);
    // Length prefix big-endian (supporta fino a 65535 byte payload)
    out[0] = (data.length >> 8) & 0xFF;
    out[1] = data.length & 0xFF;
    out.setRange(2, 2 + data.length, data);

    // Riempie il resto con byte casuali (non zeri — più difficile da distinguere)
    final rng = Random.secure();
    for (int i = 2 + data.length; i < target; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  /// Rimuove il padding e restituisce il payload originale.
  /// Se il formato non è riconosciuto, restituisce [data] invariato (backward compat).
  static Uint8List unpad(Uint8List data) {
    if (data.length < 2) return data;
    final len = (data[0] << 8) | data[1];
    if (len + 2 > data.length) return data; // formato non valido → pass-through
    return Uint8List.fromList(data.sublist(2, 2 + len));
  }
}
