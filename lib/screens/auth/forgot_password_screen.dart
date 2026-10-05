import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/validators.dart';
import '../../utils/notifications.dart';
import '../../widgets/auth_background.dart';

/// Sends a password-reset link to the personal Gmail the student added at
/// activation (resolved from the register number via the login index).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _registerNumberController = TextEditingController();

  bool _isLoading = false;
  String? _sentToEmail;

  @override
  void dispose() {
    _registerNumberController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final email =
          await _authService.resolveLoginEmail(_registerNumberController.text);
      if (email == null) {
        throw 'No activated account was found for this register number.\n'
            'First time? Use "Activate your account" on the sign-in screen.';
      }
      await _authService.sendPasswordReset(email);
      if (mounted) setState(() => _sentToEmail = email);
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
      appBar: AppBar(title: const Text('Forgot Password')),
      body: AuthBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _sentToEmail != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mark_email_read_outlined,
                        size: 72,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text('Check your Gmail',
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        'We sent a password reset link to\n$_sentToEmail',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to Sign In'),
                      ),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_reset_rounded,
                          size: 72,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Reset your password',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your register number and we will send a reset '
                          'link to the Gmail you added during activation.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _registerNumberController,
                          textCapitalization: TextCapitalization.characters,
                          validator: Validators.registerNumber,
                          decoration: const InputDecoration(
                            labelText: 'Register Number',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _sendResetEmail,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Send Reset Link'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const AuthFooter(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
