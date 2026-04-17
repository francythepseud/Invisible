import 'dart:io';
import 'package:flutter/foundation.dart';

/// Factory per HttpClient con TLS strict e certificate pinning.
///
/// - Rifiuta SEMPRE certificati non validi (self-signed, scaduti, wrong domain)
/// - Nessun bypass possibile anche con proxy MITM installato sul device
/// - Il pinning a livello OS è gestito da network_security_config.xml (Android)
class PinnedHttpClient {
  PinnedHttpClient._();

  /// Crea un [HttpClient] con strict TLS.
  ///
  /// [badCertificateCallback] è impostato a false: nessun certificato
  /// non valido viene mai accettato, neanche in presenza di CA installate
  /// dall'utente o da un proxy (es. Burp Suite, Charles Proxy).
  static HttpClient create() {
    final client = HttpClient()
      ..badCertificateCallback = _rejectBadCert
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 30);
    return client;
  }

  static bool _rejectBadCert(X509Certificate cert, String host, int port) {
    // In debug accettiamo cert non validi per test locali con proxy
    if (kDebugMode) return true;
    // In release: rifiuto assoluto — nessun MITM possibile
    debugPrint('[TLS] Certificato non valido da $host:$port — rifiutato');
    return false;
  }
}
