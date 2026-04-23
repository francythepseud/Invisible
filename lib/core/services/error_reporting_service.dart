import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/utils/constants.dart';

class _Breadcrumb {
  final DateTime time;
  final String category; // nav | action | network | info
  final String message;
  _Breadcrumb(this.category, this.message) : time = DateTime.now();

  @override
  String toString() =>
      '[${time.toIso8601String()}] [$category] $message';
}

/// Servizio di error reporting con breadcrumb trail.
///
/// Cattura automaticamente errori Flutter e di zona.
/// Mantiene gli ultimi 30 eventi utente per contestualizzare gli errori.
///
/// Uso:
///   ErrorReportingService().addBreadcrumb('nav', 'Aperto ChatScreen');
///   ErrorReportingService().addBreadcrumb('action', 'Inviato messaggio');
class ErrorReportingService {
  static final ErrorReportingService _instance =
      ErrorReportingService._internal();
  factory ErrorReportingService() => _instance;
  ErrorReportingService._internal();

  static const _maxBreadcrumbs = 30;
  static const _maxRetries = 2;

  final _breadcrumbs = <_Breadcrumb>[];
  String? _deviceModel;
  String? _osVersion;
  bool _initialized = false;

  // ─── Inizializzazione ────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _loadDeviceInfo();

    // Cattura errori del framework Flutter (es. widget build errors)
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _report(
        errorType: 'FlutterError',
        errorMessage: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
      );
    };

    // Cattura errori asincroni non gestiti (Platform dispatcher)
    PlatformDispatcher.instance.onError = (error, stack) {
      _report(
        errorType: 'PlatformError',
        errorMessage: error.toString(),
        stackTrace: stack.toString(),
      );
      return true;
    };
  }

  /// Chiamato da runZonedGuarded in main.dart per errori di zona.
  void onZoneError(Object error, StackTrace stack) {
    final msg = error.toString();
    // Ignora errori di rete comuni — non sono bug dell'app
    if (msg.contains('WebSocketChannelException') ||
        msg.contains('SocketException') ||
        msg.contains('WebSocketException') ||
        msg.contains('HandshakeException')) {
      return;
    }

    _report(
      errorType: 'ZoneError',
      errorMessage: msg,
      stackTrace: stack.toString(),
    );
  }

  // ─── Breadcrumbs ─────────────────────────────────────────────────────────

  /// Registra un evento utente nel trail.
  ///
  /// [category]: 'nav' | 'action' | 'network' | 'info' | 'error'
  void addBreadcrumb(String category, String message) {
    _breadcrumbs.add(_Breadcrumb(category, message));
    if (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
  }

  // ─── Report manuale ───────────────────────────────────────────────────────

  /// Segnala un errore esplicito (es. catch in try/catch critico).
  void reportError(
    dynamic error, {
    StackTrace? stackTrace,
    String errorType = 'ManualReport',
  }) {
    _report(
      errorType: errorType,
      errorMessage: error.toString(),
      stackTrace: stackTrace?.toString(),
    );
  }

  /// Shortcut statico — usabile ovunque con una sola riga:
  ///   ErrorReportingService.log(e, st, 'CallError');
  static void log(dynamic error, [StackTrace? stackTrace, String errorType = 'AppError']) {
    ErrorReportingService().reportError(error, stackTrace: stackTrace, errorType: errorType);
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  Future<void> _loadDeviceInfo() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        _deviceModel = '${android.manufacturer} ${android.model}';
        _osVersion = 'Android ${android.version.release} (SDK ${android.version.sdkInt})';
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        _deviceModel = '${ios.name} ${ios.model}';
        _osVersion = 'iOS ${ios.systemVersion}';
      }
    } catch (_) {
      _deviceModel = Platform.operatingSystem;
      _osVersion = Platform.operatingSystemVersion;
    }
  }

  Future<void> _report({
    required String errorType,
    required String errorMessage,
    String? stackTrace,
  }) async {
    try {
      final identityHash = await _getIdentityHash();
      final breadcrumbLog = _breadcrumbs.map((b) => b.toString()).join('\n');
      final fullTrace = [
        if (stackTrace != null) 'STACK TRACE:\n$stackTrace',
        if (_breadcrumbs.isNotEmpty) '\nBREADCRUMBS (ultimi eventi):\n$breadcrumbLog',
      ].join('\n\n');

      final body = jsonEncode({
        'identity_hash':  identityHash,
        'app_version':    AppConstants.appVersion,
        'os_type':        Platform.isIOS ? 'ios' : 'android',
        'os_version':     _osVersion ?? Platform.operatingSystemVersion,
        'device_model':   _deviceModel ?? Platform.operatingSystem,
        'error_type':     errorType,
        'error_message':  errorMessage,
        'stack_trace':    fullTrace.isEmpty ? null : fullTrace,
      });

      for (int i = 0; i <= _maxRetries; i++) {
        try {
          final resp = await http
              .post(
                Uri.parse(AppConstants.errorsUrl),
                headers: {'Content-Type': 'application/json'},
                body: body,
              )
              .timeout(const Duration(seconds: 5));
          if (resp.statusCode == 200) break;
        } catch (_) {
          if (i == _maxRetries) break;
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
    } catch (_) {
      // Mai lanciare eccezioni dal servizio di errori
    }
  }

  Future<String?> _getIdentityHash() async {
    try {
      final keys = await ProfileService().getCurrentCryptoKeys();
      if (keys == null) return null;
      final k = keys.identityKeyPublic;
      return k.length > 32 ? k.substring(k.length - 32) : k;
    } catch (_) {
      return null;
    }
  }
}
