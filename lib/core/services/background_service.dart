import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Gestisce il Foreground Service Android per mantenere il relay WebSocket
/// vivo in background senza FCM/Google.
///
/// Su iOS la gestione background è limitata dal sistema (non c'è equivalente
/// del foreground service); il WebSocket si riconnette automaticamente quando
/// l'utente torna in foreground grazie al reconnect esponenziale di InvisibleClient.
class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  static const _channel = MethodChannel('com.invisible.invisible/service');

  /// Avvia il foreground service (solo Android).
  /// Chiamare dopo il login riuscito.
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startRelayService');
      debugPrint('[BG] Foreground service avviato');
    } catch (e) {
      debugPrint('[BG] Errore avvio foreground service: $e');
    }
  }

  /// Ferma il foreground service (solo Android).
  /// Chiamare al logout.
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopRelayService');
      debugPrint('[BG] Foreground service fermato');
    } catch (e) {
      debugPrint('[BG] Errore stop foreground service: $e');
    }
  }
}
