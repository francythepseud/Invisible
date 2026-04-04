import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestisce il codice segreto di avvio (*#*#CODICE#*#*) e la visibilità
/// dell'icona nel launcher Android.
class LaunchCodeService {
  static final LaunchCodeService _instance = LaunchCodeService._internal();
  factory LaunchCodeService() => _instance;
  LaunchCodeService._internal();

  static const _channel = MethodChannel('com.invisible.invisible/launcher');
  static const _codeKey = 'invisible_launch_code';
  static const _defaultCode = '1234';

  /// Codici registrati nel manifest (android:host). Solo questi funzionano
  /// con il receiver SECRET_CODE. Aggiornare in sync con AndroidManifest.xml.
  static const Set<String> allowedCodes = {
    // Sequenziali
    '1234','2345','3456','4567','5678','6789','7890','8901','9012','0123',
    // Inversi
    '4321','9876','0987','6543',
    // Ripetuti
    '0000','1111','2222','3333','4444','5555','6666','7777','8888','9999',
    // Doppi
    '1212','2121','1122','2211','1221','2112',
    '3344','4433','5566','6655','7788','8877','1313','3131',
    // A scacchiera
    '1357','2468','8642','9753','2580','1470','3690','1593',
    // Tondi
    '1000','2000','3000','4000','5000','6000','7000','8000','9000',
    // Vari
    '1024','4096','7531','9630','6321','7419','4826','3141','2718','1618',
  };

  static bool isCodeAllowed(String code) => allowedCodes.contains(code);

  // ─── Codice segreto ────────────────────────────────────────────────────────

  Future<String> getLaunchCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_codeKey) ?? _defaultCode;
  }

  /// Salva il nuovo codice. Il receiver Kotlin lo leggerà al prossimo avvio.
  Future<void> setLaunchCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
  }

  // ─── Visibilità launcher ────────────────────────────────────────────────────

  Future<bool> isLauncherVisible() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLauncherVisible');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> hideLauncherIcon() async {
    try {
      await _channel.invokeMethod('hideLauncherIcon');
    } catch (_) {}
  }

  Future<void> showLauncherIcon() async {
    try {
      await _channel.invokeMethod('showLauncherIcon');
    } catch (_) {}
  }

  // ─── Overlay permission (Android 12+) ──────────────────────────────────────

  Future<bool> hasOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }
}
