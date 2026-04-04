import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste le impostazioni di privacy e sicurezza dell'app.
///
/// Default sicuri:
/// - Screenshot prevention: ON
/// - Auto-lock: 5 minuti
/// - Message expiration: OFF
class SecuritySettingsService {
  static final SecuritySettingsService _instance = SecuritySettingsService._internal();
  factory SecuritySettingsService() => _instance;
  SecuritySettingsService._internal();

  static const _keyScreenshot = 'sec_screenshot_prevention';
  static const _keyAutoLock   = 'sec_auto_lock_minutes';
  static const _keyMsgExpiry  = 'sec_msg_expiry_days';

  static const _securityChannel = MethodChannel('com.invisible.invisible/security');

  // ── Screenshot Prevention ────────────────────────────────────────────────

  Future<bool> getScreenshotPrevention() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyScreenshot) ?? true;
  }

  /// Salva la preferenza E applica subito il FLAG_SECURE Android.
  Future<void> setScreenshotPrevention(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyScreenshot, value);
    try {
      await _securityChannel.invokeMethod('setScreenshotPrevention', value);
    } catch (_) {}
  }

  /// Solo applica il flag (senza salvare) — usato all'avvio da app.dart.
  Future<void> applyScreenshotPrevention(bool value) async {
    try {
      await _securityChannel.invokeMethod('setScreenshotPrevention', value);
    } catch (_) {}
  }

  // ── Auto-lock ────────────────────────────────────────────────────────────

  Future<int> getAutoLockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyAutoLock) ?? 5;
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAutoLock, minutes);
  }

  // ── Message Expiration ───────────────────────────────────────────────────

  Future<int> getMessageExpirationDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyMsgExpiry) ?? 0;
  }

  Future<void> setMessageExpirationDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMsgExpiry, days);
  }
}
