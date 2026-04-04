import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:invisible/core/services/error_reporting_service.dart';
import 'package:invisible/core/services/notification_service.dart';

import 'app.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await ErrorReportingService().initialize();
      await NotificationService().initialize();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      runApp(const InvisibleApp());
    },
    (error, stack) {
      ErrorReportingService().onZoneError(error, stack);
      debugPrint('Unhandled error: $error');
    },
  );
}

