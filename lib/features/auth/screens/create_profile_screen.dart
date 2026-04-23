import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:invisible/core/services/error_reporting_service.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/user_credentials.dart';
import 'package:invisible/utils/constants.dart';
import 'package:invisible/core/services/tos_service.dart';
import 'package:invisible/features/auth/screens/not_activated_screen.dart';
import 'package:invisible/features/onboarding/screens/tos_screen.dart';

class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _profileService = ProfileService();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final credentials = UserCredentials(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      await _profileService.createProfile(credentials);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profilo creato con successo!'),
          backgroundColor: AppConstants.success,
        ),
      );

      final tosAccepted = await TosService().hasAccepted();
      if (!mounted) return;

      if (!tosAccepted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TosScreen(
              onAccepted: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const NotActivatedScreen()),
                  (route) => false,
                );
              },
            ),
            fullscreenDialog: true,
          ),
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const NotActivatedScreen()),
          (route) => false,
        );
      }
    } catch (e, st) {
      ErrorReportingService.log(e, st, 'CreateProfileError');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crea Profilo'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.paddingLarge),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppConstants.paddingLarge),

                // Icona
                Icon(
                  Icons.person_add,
                  size: 80,
                  color: AppConstants.primaryBlue,
                ),

                const SizedBox(height: AppConstants.paddingLarge),

                Text(
                  'Crea il tuo profilo locale',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),

                const SizedBox(height: AppConstants.paddingSmall),

                Text(
                  'Scegli un username e una password.\nSaranno usati solo su questo dispositivo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

                const SizedBox(height: AppConstants.paddingXLarge),

                // Username field
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'Scegli un username',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Inserisci un username';
                    }
                    if (value.contains(' ')) {
                      return 'Lo username non può contenere spazi';
                    }
                    if (value.length < 3) {
                      return 'Username troppo corto (min 3 caratteri)';
                    }
                    if (value.length > 20) {
                      return 'Username troppo lungo (max 20 caratteri)';
                    }
                    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
                      return 'Solo lettere, numeri, punto, trattino e underscore';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppConstants.paddingMedium),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Scegli una password sicura',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Inserisci una password';
                    }
                    if (value.contains(' ')) {
                      return 'La password non può contenere spazi';
                    }
                    if (value.length < 6) {
                      return 'Password troppo corta (min 6 caratteri)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppConstants.paddingMedium),

                // Confirm password field
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Conferma Password',
                    hintText: 'Reinserisci la password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _createProfile(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Conferma la password';
                    }
                    if (value != _passwordController.text) {
                      return 'Le password non coincidono';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppConstants.paddingXLarge),

                // Info box
                Container(
                  padding: const EdgeInsets.all(AppConstants.paddingMedium),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                    border: Border.all(
                      color: AppConstants.primaryBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppConstants.primaryBlue,
                      ),
                      const SizedBox(width: AppConstants.paddingMedium),
                      Expanded(
                        child: Text(
                          'Il tuo profilo sarà criptato con la password scelta. Non dimenticarla!',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppConstants.textPrimary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppConstants.paddingXLarge),

                // Create button
                ElevatedButton(
                  onPressed: _isLoading ? null : _createProfile,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Crea Profilo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
