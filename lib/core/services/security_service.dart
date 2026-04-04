import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';

/// Risultato della scansione di sicurezza del dispositivo.
class SecurityReport {
  final bool isRooted;
  final bool isEmulator;
  final bool isDeveloperModeEnabled;
  final bool isDebuggerAttached;

  const SecurityReport({
    required this.isRooted,
    required this.isEmulator,
    required this.isDeveloperModeEnabled,
    required this.isDebuggerAttached,
  });

  /// True se almeno un rischio è rilevato.
  bool get hasRisk =>
      isRooted || isEmulator || isDeveloperModeEnabled || isDebuggerAttached;

  /// Lista dei rischi rilevati come stringhe leggibili.
  List<String> get risks {
    final list = <String>[];
    if (isRooted) list.add('Dispositivo con accesso root');
    if (isEmulator) list.add('Emulatore rilevato');
    if (isDeveloperModeEnabled) list.add('Modalità sviluppatore attiva');
    if (isDebuggerAttached) list.add('Debugger collegato');
    return list;
  }
}

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  /// Esegue la scansione di sicurezza del dispositivo.
  Future<SecurityReport> scan() async {
    // In debug mode non mostrare warning (APK di test)
    if (kDebugMode) {
      return const SecurityReport(
        isRooted: false, isEmulator: false,
        isDeveloperModeEnabled: false, isDebuggerAttached: false,
      );
    }
    bool isRooted = false;
    bool isEmulator = false;
    bool isDeveloperMode = false;
    bool isDebugger = false;

    // Solo su Android/iOS, non su desktop/web
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        isRooted = await SafeDevice.isJailBroken;
      } catch (_) {}

      try {
        isEmulator = !(await SafeDevice.isRealDevice);
      } catch (_) {}

      try {
        isDeveloperMode = await SafeDevice.isDevelopmentModeEnable;
      } catch (_) {}
    }

    // Debugger: funziona su tutte le piattaforme
    isDebugger = kDebugMode;

    return SecurityReport(
      isRooted: isRooted,
      isEmulator: isEmulator,
      isDeveloperModeEnabled: isDeveloperMode,
      isDebuggerAttached: isDebugger,
    );
  }
}
