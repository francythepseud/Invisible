import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';

/// Tipi di minaccia rilevabili al boot dell'app.
enum SecurityThreat {
  /// Device rooted (Android) o jailbroken (iOS)
  rootJailbreak,
  /// L'app sta girando su emulatore/simulatore
  emulator,
  /// Modalità sviluppatore attiva (USB debugging, ecc.)
  developerOptions,
  /// APK installato da storage esterno (sideload non sicuro) — solo Android
  externalStorage,
}

class SecurityCheckResult {
  final bool isSafe;
  final Set<SecurityThreat> threats;
  const SecurityCheckResult({required this.isSafe, required this.threats});
}

/// Controlla l'integrità del device prima di avviare l'app.
///
/// In [kDebugMode] i controlli sono disabilitati per permettere lo sviluppo.
/// In release BLOCCA l'avvio se il device è compromesso.
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  Future<SecurityCheckResult> runChecks() async {
    // In debug mode saltiamo tutti i check (sviluppo locale)
    if (kDebugMode) {
      return const SecurityCheckResult(isSafe: true, threats: {});
    }

    final threats = <SecurityThreat>{};

    // ── Root / Jailbreak ────────────────────────────────────────────────────
    try {
      if (await SafeDevice.isJailBroken) {
        threats.add(SecurityThreat.rootJailbreak);
        debugPrint('[SECURITY] Root/Jailbreak rilevato');
      }
    } catch (_) {}

    // ── Emulatore / Simulatore ──────────────────────────────────────────────
    try {
      final isReal = await SafeDevice.isRealDevice;
      if (!isReal) {
        threats.add(SecurityThreat.emulator);
        debugPrint('[SECURITY] Emulatore rilevato');
      }
    } catch (_) {}

    // ── Developer options (Android) ─────────────────────────────────────────
    try {
      if (Platform.isAndroid && await SafeDevice.isDevelopmentModeEnable) {
        threats.add(SecurityThreat.developerOptions);
        debugPrint('[SECURITY] Modalità sviluppatore attiva');
      }
    } catch (_) {}

    // ── APK su storage esterno (Android) ────────────────────────────────────
    try {
      if (Platform.isAndroid && await SafeDevice.isOnExternalStorage) {
        threats.add(SecurityThreat.externalStorage);
        debugPrint('[SECURITY] APK su storage esterno rilevato');
      }
    } catch (_) {}

    return SecurityCheckResult(
      isSafe: threats.isEmpty,
      threats: threats,
    );
  }

  /// Descrizione leggibile per ogni minaccia.
  static String describeThreats(Set<SecurityThreat> threats) {
    return threats.map((t) {
      switch (t) {
        case SecurityThreat.rootJailbreak:
          return 'Dispositivo rootato o con jailbreak';
        case SecurityThreat.emulator:
          return 'Emulatore o simulatore';
        case SecurityThreat.developerOptions:
          return 'Modalità sviluppatore attiva';
        case SecurityThreat.externalStorage:
          return 'App installata su storage esterno';
      }
    }).join('\n• ');
  }
}
