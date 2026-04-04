import 'package:flutter/material.dart';
import 'package:invisible/core/services/error_reporting_service.dart';

/// NavigatorObserver che registra automaticamente ogni cambio schermata
/// come breadcrumb nel ErrorReportingService.
class BreadcrumbObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    final name = route.settings.name ?? route.runtimeType.toString();
    ErrorReportingService().addBreadcrumb('nav', 'push → $name');
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    final name = previousRoute?.settings.name ??
        previousRoute?.runtimeType.toString() ??
        'unknown';
    ErrorReportingService().addBreadcrumb('nav', 'pop → $name');
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final name = newRoute?.settings.name ?? newRoute?.runtimeType.toString();
    ErrorReportingService().addBreadcrumb('nav', 'replace → $name');
  }
}
