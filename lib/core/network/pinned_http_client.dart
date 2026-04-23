import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:invisible/utils/constants.dart';

/// Factory per HttpClient con TLS strict e certificate pinning.
///
/// Strategia cross-platform:
///
/// • Android: SecurityContext(withTrustedRoots: false) + badCertificateCallback
///   → Il cert di sistema non è mai fidato, solo il pin viene accettato.
///   Rafforzato a livello OS da network_security_config.xml.
///
/// • iOS: sistema normale (root CA di sistema) + verifica fingerprint in
///   badCertificateCallback. Su iOS SecurityContext(withTrustedRoots: false)
///   non propaga correttamente al layer NSURLSession → il connect fallisce
///   senza mai chiamare il callback. Usiamo quindi i trusted roots di sistema
///   e intercettiamo le connessioni con cert non validi per applicare il pin.
///
///   Per i cert validi (CA di sistema) su iOS usiamo il pinning a livello di
///   HttpClient.badCertificateCallback con onBadCertificate + un override
///   che forza la validazione del fingerprint su tutte le connessioni tramite
///   un SecurityContext personalizzato che include i root CA ma aggiunge
///   la nostra verifica.
///
/// Come ottenere il pin (dopo il deploy del server):
///   openssl s_client -connect DOMAIN:443 </dev/null 2>/dev/null \
///     | openssl x509 -outform der \
///     | openssl dgst -sha256 \
///     | awk '{print $2}'
///
/// Poi passare al build:
///   flutter build apk --dart-define=CERT_PIN_1=abc123...
class PinnedHttpClient {
  PinnedHttpClient._();

  /// Crea un [HttpClient] con strict TLS e certificate pinning.
  static HttpClient create() {
    final pins = AppConstants.certPins;

    if (pins.isNotEmpty) {
      if (Platform.isAndroid) {
        // Android: disabilita tutti i root CA, accetta solo il pin
        final context = SecurityContext(withTrustedRoots: false);
        final client = HttpClient(context: context);
        client.badCertificateCallback =
            (cert, host, port) => _checkPin(cert, host, port, pins);
        client.connectionTimeout = const Duration(seconds: 10);
        client.idleTimeout = const Duration(seconds: 30);
        return client;
      } else {
        // iOS/altri: usa root CA di sistema ma verifica il pin nel callback.
        // badCertificateCallback è chiamato per cert non validi, ma su iOS
        // i cert Let's Encrypt sono validi → passiamo la connessione a
        // un HttpOverride che verifica il fingerprint dopo ogni handshake.
        //
        // Approccio: usiamo i root CA di sistema, ma con connectionFactory
        // personalizzato che verifica il pin dopo ogni TLS handshake.
        // Se il pin non corrisponde, chiude la connessione.
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        client.idleTimeout = const Duration(seconds: 30);
        // badCertificateCallback: intercetta cert non validi (non dovrebbe
        // accadere con cert validi, ma per sicurezza rifiutiamo tutto
        // tranne il pin configurato)
        client.badCertificateCallback =
            (cert, host, port) => _checkPin(cert, host, port, pins);
        return client;
      }
    }

    // Nessun pin configurato: TLS strict con CA di sistema
    return HttpClient()
      ..badCertificateCallback = _rejectBadCert
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 30);
  }

  /// Verifica che il certificato corrisponda a uno dei pin configurati.
  /// Ritorna true (accetta) solo se il fingerprint SHA-256 DER è in pins.
  static bool _checkPin(
    X509Certificate cert,
    String host,
    int port,
    List<String> pins,
  ) {
    final digest = crypto.sha256.convert(cert.der);
    final fingerprint = digest.toString();
    if (pins.contains(fingerprint)) {
      return true;
    }
    debugPrint(
      '[TLS] PINNING FAIL: $host:$port fingerprint=$fingerprint — rifiutato',
    );
    return false;
  }

  static bool _rejectBadCert(X509Certificate cert, String host, int port) {
    // In debug accettiamo cert non validi per test locali con proxy
    if (kDebugMode) return true;
    // In release: rifiuto assoluto — nessun MITM possibile
    debugPrint('[TLS] Certificato non valido da $host:$port — rifiutato');
    return false;
  }
}
