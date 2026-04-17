import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'utils/theme.dart';
import 'utils/constants.dart';
import 'utils/navigator_key.dart';
import 'core/services/breadcrumb_observer.dart';
import 'core/services/profile_service.dart';
import 'core/services/security_settings_service.dart';
import 'core/services/message_service.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/splash_screen.dart';

class InvisibleApp extends StatefulWidget {
  const InvisibleApp({super.key});

  @override
  State<InvisibleApp> createState() => _InvisibleAppState();
}

class _InvisibleAppState extends State<InvisibleApp> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyStartupSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Applica screenshot prevention e cancella messaggi scaduti all'avvio.
  Future<void> _applyStartupSettings() async {
    final settings = SecuritySettingsService();

    // Screenshot prevention — sovrascrive il default FLAG_SECURE di MainActivity
    final screenshotOn = await settings.getScreenshotPrevention();
    await settings.applyScreenshotPrevention(screenshotOn);

    // Elimina messaggi scaduti
    try {
      final expiryDays = await settings.getMessageExpirationDays();
      if (expiryDays > 0) {
        await MessageService().deleteExpiredMessages(expiryDays);
      }
    } catch (_) {}
  }

  // ── Auto-lock ────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _checkAutoLock();
    }
  }

  Future<void> _checkAutoLock() async {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;

    final lockMinutes = await SecuritySettingsService().getAutoLockMinutes();
    if (lockMinutes == 0) return;

    final elapsed = DateTime.now().difference(pausedAt).inMinutes;
    if (elapsed >= lockMinutes) {
      _pausedAt = null;
      try {
        await ProfileService().logout();
      } catch (_) {}
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppConstants.primaryBlack,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey,
      navigatorObservers: [BreadcrumbObserver()],
      home: const SplashScreen(),
    );
  }
}
