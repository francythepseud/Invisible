import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/utils/constants.dart';

/// Invia errori tecnici al server admin in modo silenzioso.
/// NON invia mai contenuti di messaggi o dati personali.
class ErrorReporter {
  static final ErrorReporter _instance = ErrorReporter._internal();
  factory ErrorReporter() => _instance;
  ErrorReporter._internal();

  final _profileService = ProfileService();

  Future<void> report({
    required String errorType,
    required String errorMessage,
    String? stackTrace,
  }) async {
    if (kDebugMode) return; // Non invia in debug
    try {
      final keys = await _profileService.getCurrentCryptoKeys();
      String? identityHash;
      if (keys != null) {
        final bytes = utf8.encode(keys.identityKeyPublic);
        final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        identityHash = hex.length > 64 ? hex.substring(0, 64) : hex;
      }

      await http.post(
        Uri.parse(AppConstants.errorsUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identity_hash': identityHash,
          'app_version': AppConstants.appVersion,
          'os_type': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'device_model': '',
          'error_type': errorType,
          'error_message': errorMessage.length > 500
              ? errorMessage.substring(0, 500)
              : errorMessage,
          'stack_trace': stackTrace != null && stackTrace.length > 1000
              ? stackTrace.substring(0, 1000)
              : stackTrace,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Silenzioso — non deve mai crashare l'app
    }
  }
}
