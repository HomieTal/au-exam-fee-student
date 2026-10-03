import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/theme.dart';
import '../../utils/notifications.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_background.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Register-number + date-of-birth sign-in.
///
/// On the first sign-in the account is provisioned automatically from the
/// exam-cell record: register number → `<regno>@au.edu.in`, initial
/// password = date of birth (DDMMYYYY). A personal email is collected and
/// verified afterwards on the dashboard.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _registerNumberController = TextEditingController();
  final _dobController = TextEditingController();

  bool _obscureDob = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _registerNumberController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.signInWithRegisterNumber(
        registerNumber: _registerNumberController.text,
        dateOfBirth: _dobController.text,
      );
      // AuthGate listens to authStateChanges and navigates automatically.
    } catch (e) {
      if (mounted) {
        AppNotifications.show(context, e.toString(), error: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: AuthBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const AuthLogoBadge(size: 118),
                  const SizedBox(height: 28),
                  Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Anna University · Exam Fee Management',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  // Form card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF34506E)
                              .withValues(alpha: 0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _registerNumberController,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          validator: Validators.registerNumber,
                          decoration: const InputDecoration(
                            labelText: 'Register Number',
                            hintText: 'As per college records',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _dobController,
                          obscureText: _obscureDob,
                          keyboardType: TextInputType.datetime,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              _isLoading ? null : _signIn(),
                          validator: (v) => AppHelpers.normalizeDob(v) == null
                              ? 'Enter your date of birth as DDMMYYYY'
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Date of Birth (Password)',
                            hintText: 'DDMMYYYY',
                            prefixIcon: const Icon(Icons.cake_outlined),
                            helperText:
                                'Your initial password is your date of birth',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureDob
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                  () => _obscureDob = !_obscureDob),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            ),
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              disabledBackgroundColor: AppTheme.primaryColor
                                  .withValues(alpha: 0.5),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Sign In',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: theme.textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        ),
                        child: const Text('Register'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const AuthFooter(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
