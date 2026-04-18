import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scelta suono notifica. Il valore viene salvato in SharedPreferences.
enum NotifSound { predefinito, soloVibrazione, silenzioso }

/// Gestisce le notifiche locali anonime (nessun dato inviato a Google/FCM).
///
/// Vengono creati 3 canali Android, uno per ogni modalità audio.
/// Una volta che un canale esiste su Android, il suo suono non può essere
/// cambiato programmaticamente (limite OS): l'utente può modificarlo
/// dalle impostazioni di sistema.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const _keyEnabled = 'notif_enabled';
  static const _keyMessage = 'notif_message';
  static const _keySound   = 'notif_sound';

  static const _defaultMessage = 'Hai ricevuto un messaggio';

  // ID canali Android — uno per modalità audio
  static const _chDefault   = 'invisible_default';
  static const _chVibration = 'invisible_vibration';
  static const _chSilent    = 'invisible_silent';

  final _plugin = FlutterLocalNotificationsPlugin();
  int _notifId = 0;

  // ─── Inizializzazione ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _plugin.initialize(initSettings);
  }

  /// Richiede il permesso notifiche su Android 13+ e iOS. Restituisce true se concesso.
  Future<bool> requestPermission() async {
    // iOS
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    // Android 13+
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  // ─── Impostazioni utente ───────────────────────────────────────────────────

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
  }

  Future<String> getMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMessage) ?? _defaultMessage;
  }

  Future<void> setMessage(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyMessage,
      message.trim().isEmpty ? _defaultMessage : message.trim(),
    );
  }

  Future<NotifSound> getSound() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySound) ?? NotifSound.predefinito.name;
    return NotifSound.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => NotifSound.predefinito,
    );
  }

  Future<void> setSound(NotifSound sound) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySound, sound.name);
  }

  // ─── Mostra notifica ───────────────────────────────────────────────────────

  /// Mostra una notifica anonima quando arriva un messaggio.
  /// Il testo è quello personalizzato — nessun dato sensibile incluso.
  Future<void> showMessageNotification() async {
    final enabled = await isEnabled();
    if (!enabled) return;

    final text = await getMessage();
    final sound = await getSound();

    final details = NotificationDetails(
      android: _buildAndroidDetails(sound),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: sound != NotifSound.silenzioso,
      ),
    );

    await _plugin.show(
      _notifId++ % 1000,
      null, // Nessun titolo — massima anonimizzazione
      text,
      details,
    );
  }

  AndroidNotificationDetails _buildAndroidDetails(NotifSound sound) {
    switch (sound) {
      case NotifSound.silenzioso:
        return const AndroidNotificationDetails(
          _chSilent,
          'Silenzioso',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
        );
      case NotifSound.soloVibrazione:
        return const AndroidNotificationDetails(
          _chVibration,
          'Solo vibrazione',
          importance: Importance.high,
          priority: Priority.high,
          playSound: false,
          enableVibration: true,
        );
      case NotifSound.predefinito:
        return const AndroidNotificationDetails(
          _chDefault,
          'Suono predefinito',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
    }
  }
}
