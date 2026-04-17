import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:invisible/core/network/invisible_client.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/user_credentials.dart';
import 'package:invisible/utils/constants.dart';
import 'package:invisible/core/services/tos_service.dart';
import 'package:invisible/features/auth/screens/not_activated_screen.dart';
import 'package:invisible/features/home/home_screen.dart';
import 'package:invisible/features/onboarding/screens/tos_screen.dart';
import 'create_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _profileService = ProfileService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Connette al relay e aspetta l'esito: true=attivato, false=non attivato.
  Future<bool> _checkActivation() async {
    // Forza disconnessione e riconnessione fresca per verificare whitelist
    await InvisibleClient().disconnect();
    InvisibleClient().connect(AppConstants.relayWsUrl).catchError((_) {});
    try {
      await InvisibleClient().statusStream
          .firstWhere((s) => s == RelayStatus.connected)
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await _profileService.login(UserCredentials(
        username: username,
        password: password,
      ));
      if (!mounted) return;

      final tosAccepted = await TosService().hasAccepted();
      if (!mounted) return;

      if (!tosAccepted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TosScreen(
              onAccepted: () async {
                final activated = await _checkActivation();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => activated ? const HomeScreen() : const NotActivatedScreen()),
                  (route) => false,
                );
              },
            ),
            fullscreenDialog: true,
          ),
        );
      } else {
        final activated = await _checkActivation();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => activated ? const HomeScreen() : const NotActivatedScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Errore durante l\'accesso';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Sfondo gradient nero ────────────────────────────────────────
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF000000),
                    Color(0xFF050510),
                    Color(0xFF000000),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // ── Glow blu in alto ──────────────────────────────────────────
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppConstants.primaryBlue.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),

                  // ── Logo ───────────────────────────────────────────────
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.primaryBlue.withValues(alpha: 0.5),
                            blurRadius: 40,
                            spreadRadius: 6,
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

                  const SizedBox(height: 28),

                  // ── Titolo INVISIBLE — font Roboto ─────────────────────
                  Center(
                    child: Text(
                      'INVISIBLE',
                      style: GoogleFonts.roboto(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppConstants.primaryBlue,
                        letterSpacing: 8,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Center(
                    child: Text(
                      'Messaggistica Sicura',
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: AppConstants.textTertiary,
                        letterSpacing: 2.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),

                  const SizedBox(height: 52),

                  // ── Campo username ─────────────────────────────────────
                  _buildTextField(
                    controller: _usernameController,
                    hint: 'Username',
                    icon: Icons.person_outline_rounded,
                    obscure: false,
                    action: TextInputAction.next,
                  ),

                  const SizedBox(height: 12),

                  // ── Campo password ─────────────────────────────────────
                  _buildTextField(
                    controller: _passwordController,
                    hint: 'Password',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscurePassword,
                    action: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppConstants.textTertiary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Pulsante ACCEDI ────────────────────────────────────
                  _buildLoginButton(),

                  const SizedBox(height: 32),

                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CreateProfileScreen()),
                        );
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                      label: const Text('Crea nuovo profilo'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppConstants.textTertiary,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscure,
    required TextInputAction action,
    ValueChanged<String>? onSubmitted,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppConstants.primaryBlue.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        textInputAction: action,
        onFieldSubmitted: onSubmitted,
        style: const TextStyle(color: AppConstants.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: AppConstants.textTertiary.withValues(alpha: 0.6)),
          prefixIcon: Icon(icon, color: AppConstants.primaryBlue, size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _login,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isLoading
                ? [Colors.grey.shade800, Colors.grey.shade900]
                : [AppConstants.primaryBlue, AppConstants.darkBlue],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isLoading
              ? null
              : [
                  BoxShadow(
                    color: AppConstants.primaryBlue.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'ACCEDI',
                  style: GoogleFonts.roboto(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
        ),
      ),
    );
  }
}
