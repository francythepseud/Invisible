import 'package:flutter/material.dart';
import 'package:invisible/utils/constants.dart';
import 'create_profile_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.primaryBlack,
      body: Stack(
        children: [
          // Background glow
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.5),
                  radius: 1.1,
                  colors: [
                    AppConstants.primaryBlue.withValues(alpha: 0.09),
                    AppConstants.primaryBlack,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),

                  // Logo — immagine senza card
                  Center(
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.primaryBlue.withValues(alpha: 0.45),
                            blurRadius: 40,
                            spreadRadius: 5,
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

                  const SizedBox(height: 24),

                  const Text(
                    'INVISIBLE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 9,
                      color: AppConstants.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Messaggistica End-to-End Cifrata',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppConstants.primaryBlue,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const Spacer(),

                  // Feature list
                  _FeatureRow(
                    icon: Icons.shield_rounded,
                    title: 'Crittografia End-to-End',
                    subtitle: 'Signal Protocol — Double Ratchet',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.phone_android_rounded,
                    title: 'Nessun Numero di Telefono',
                    subtitle: 'Solo username + password locale',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.visibility_off_rounded,
                    title: 'Zero Knowledge Server',
                    subtitle: 'Il server non può leggere nulla',
                  ),

                  const Spacer(),

                  // CTA button
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateProfileScreen()),
                      );
                    },
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppConstants.primaryBlue, AppConstants.darkBlue],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.primaryBlue.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'Crea Profilo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'v${AppConstants.appVersion}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: AppConstants.textTertiary),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppConstants.primaryBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppConstants.primaryBlue.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: AppConstants.primaryBlue, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppConstants.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
