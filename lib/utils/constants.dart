import 'package:flutter/material.dart';

class AppConstants {
  // App Info
  static const String appName = 'Invisible';
  static const String appVersion = '1.0.0';

  // Colors - Tema Nero + Blu
  static const Color primaryBlack = Color(0xFF000000);
  static const Color backgroundBlack = Color(0xFF0A0A0A);
  static const Color surfaceBlack = Color(0xFF1A1A1A);
  static const Color cardBlack = Color(0xFF252525);

  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color accentBlue = Color(0xFF42A5F5);
  static const Color darkBlue = Color(0xFF1976D2);
  static const Color lightBlue = Color(0xFF64B5F6);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textTertiary = Color(0xFF707070);

  static const Color divider = Color(0xFF303030);
  static const Color error = Color(0xFFFF5252);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);

  // Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;

  // Icon Sizes
  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 32.0;
  static const double iconXLarge = 48.0;

  // Avatar Sizes
  static const double avatarSmall = 32.0;
  static const double avatarMedium = 48.0;
  static const double avatarLarge = 64.0;
  static const double avatarXLarge = 96.0;

  // Animation Durations
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // Database
  static const String dbName = 'invisible.db';
  static const int dbVersion = 1;

  // Crypto
  static const int masterKeyBits = 256;
  static const int prekeyCount = 100;
  static const int prekeyRotationDays = 7;

  // ── Rete Mesh / Microservizi ─────────────────────────────────────────────
  // Passare al build con --dart-define=DOMAIN=tuodominio.com ecc.
  // Esempio: flutter build apk --dart-define=DOMAIN=example.com --dart-define=VPS_IP=1.2.3.4 --dart-define=WG_PUBKEY=xxx
  static const String _domain        = String.fromEnvironment('DOMAIN', defaultValue: 'YOUR_DOMAIN');
  static const String _vpsIp         = String.fromEnvironment('VPS_IP', defaultValue: 'YOUR_VPS_IP');
  static const String _wgPubKey      = String.fromEnvironment('WG_PUBKEY', defaultValue: 'YOUR_SERVER_WG_PUBKEY');

  static const String errorsUrl        = 'https://$_domain/v1/errors';
  static const String relayWsUrl      = 'wss://$_domain/v1/relay';
  static const String signalingWsUrl  = 'wss://$_domain/v1/signal';
  static const String meshHttpUrl     = 'https://$_domain/v1/mesh';
  static const String tosHttpUrl      = 'https://$_domain/v1/tos';
  static const String meshWgEndpoint  = '$_vpsIp:51820';
  static const String meshWgServerPub = _wgPubKey;
  static const String meshCidr        = '10.7.0.0/16';

  // ToS
  static const String tosVersion      = '1.0';
  static const String tosKey          = 'tos_accepted_v';

  // ── Certificate Pinning ───────────────────────────────────────────────────
  // SHA-256 (hex) del DER del certificato del server.
  // Passare al build: flutter build apk --dart-define=CERT_PIN_1=abc123...
  //
  // Ottenere il fingerprint dopo il deploy:
  //   openssl s_client -connect DOMAIN:443 </dev/null 2>/dev/null \
  //     | openssl x509 -outform der \
  //     | openssl dgst -sha256 \
  //     | awk '{print $2}'
  static List<String> get certPins {
    const raw = [
      String.fromEnvironment('CERT_PIN_1', defaultValue: ''),
      String.fromEnvironment('CERT_PIN_2', defaultValue: ''),
    ];
    return raw.where((p) => p.isNotEmpty).toList();
  }
}
