import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/core/services/security_service.dart';
import 'package:invisible/utils/constants.dart';
import 'create_profile_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Inizializza animazioni
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    // Avvia animazione
    _animationController.forward();

    // Naviga alla prossima schermata dopo 3 secondi
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _navigateToNext();
      }
    });
  }

  Future<void> _navigateToNext() async {
    // Scansione sicurezza prima di tutto
    final report = await SecurityService().scan();
    if (!mounted) return;

    if (report.hasRisk) {
      final proceed = await _showSecurityWarning(report);
      if (!mounted) return;
      if (proceed != true) {
        // Chiude l'app
        SystemNavigator.pop();
        return;
      }
    }

    final profileService = ProfileService();
    final hasProfiles = await profileService.hasProfiles();

    if (!mounted) return;

    if (hasProfiles) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CreateProfileScreen()),
      );
    }
  }

  Future<bool?> _showSecurityWarning(SecurityReport report) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E0E1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppConstants.error, size: 22),
            const SizedBox(width: 10),
            const Text(
              'Dispositivo a rischio',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sono stati rilevati i seguenti problemi di sicurezza:',
              style: TextStyle(
                  color: AppConstants.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...report.risks.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle,
                        color: AppConstants.error, size: 7),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(
                          color: AppConstants.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppConstants.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppConstants.error.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Un dispositivo compromesso potrebbe esporre le tue comunicazioni. '
                'Si consiglia di non utilizzare Invisible su questo dispositivo.',
                style: TextStyle(
                    color: AppConstants.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Esci',
                style: TextStyle(color: AppConstants.error)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continua comunque',
                style: TextStyle(color: AppConstants.textTertiary)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.primaryBlack,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppConstants.primaryBlack,
              AppConstants.backgroundBlack,
              AppConstants.primaryBlack,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo animato
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primaryBlue.withValues(alpha: 0.5),
                        blurRadius: 50,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/darkimage1.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingXLarge),

              // Nome app
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: child,
                  );
                },
                child: Text(
                  AppConstants.appName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.textPrimary,
                    letterSpacing: 8,
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingSmall),

              // Tagline
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: child,
                  );
                },
                child: const Text(
                  'Messaggistica Sicura',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppConstants.primaryBlue,
                    letterSpacing: 2,
                  ),
                ),
              ),

              const Spacer(),

              // Loading indicator
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: child,
                  );
                },
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppConstants.primaryBlue,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingXLarge),

              // Versione
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: child,
                  );
                },
                child: Text(
                  'v${AppConstants.appVersion}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppConstants.textTertiary,
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingMedium),
            ],
          ),
        ),
      ),
    );
  }
}
