import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:invisible/core/services/error_reporting_service.dart';
import 'package:invisible/core/services/notification_service.dart';

import 'app.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      try {
        debugPrint('[STARTUP] initializeDateFormatting...');
        await initializeDateFormatting('it', null);
        debugPrint('[STARTUP] initializeDateFormatting OK');
      } catch (e, st) {
        debugPrint('[STARTUP] initializeDateFormatting ERROR: $e\n$st');
      }

      try {
        debugPrint('[STARTUP] ErrorReportingService...');
        await ErrorReportingService().initialize();
        debugPrint('[STARTUP] ErrorReportingService OK');
      } catch (e, st) {
        debugPrint('[STARTUP] ErrorReportingService ERROR: $e\n$st');
      }

      try {
        debugPrint('[STARTUP] NotificationService...');
        await NotificationService().initialize();
        debugPrint('[STARTUP] NotificationService OK');
      } catch (e, st) {
        debugPrint('[STARTUP] NotificationService ERROR: $e\n$st');
      }

      try {
        debugPrint('[STARTUP] setPreferredOrientations...');
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        debugPrint('[STARTUP] setPreferredOrientations OK');
      } catch (e, st) {
        debugPrint('[STARTUP] setPreferredOrientations ERROR: $e\n$st');
      }

      debugPrint('[STARTUP] runApp...');
      runApp(const InvisibleApp());
      debugPrint('[STARTUP] runApp OK');
    },
    (error, stack) {
      debugPrint('[STARTUP] ZONE ERROR: $error\n$stack');
      ErrorReportingService().onZoneError(error, stack);
      // Mostra errore su schermo solo in debug — in release logga e basta
      if (kDebugMode) {
        runApp(MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  'CRASH\n\n$error\n\n$stack',
                  style: const TextStyle(color: Colors.red, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ));
      }
    },
  );
}
