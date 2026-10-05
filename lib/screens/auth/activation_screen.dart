import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/theme.dart';
import '../../utils/notifications.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_background.dart';

/// One-time account activation for students imported by the exam cell.
///
/// Step 1 verifies the student's identity (register number + date of birth
/// as recorded by the exam cell). Step 2 secures the account: the student's
/// personal Gmail becomes the account email (mandatory — password reset
/// links are delivered there) and they choose their own password. The date
/// of birth is used only to verify identity and is never stored as a
/// password.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _registerNumberController = TextEditingController();
  final _dobController = TextEditingController();
  final _gmailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  int _step = 0;

  @override
  void dispose() {
    _registerNumberController.dispose();
    _dobController.dispose();
    _gmailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _continueToSecurity() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final existing =
          await _authService.resolveLoginEmail(_registerNumberController.text);
      if (existing != null) {
        throw 'This register number is already activated. Please sign in, or '
            'use "Forgot Password?" on the sign-in screen.';
      }
      setState(() => _step = 1);
    } catch (e) {
      if (mounted) AppNotifications.show(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _activate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      AppNotifications.show(context, 'Passwords do not match.', error: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.activateAccount(
        registerNumber: _registerNumberController.text,
        dateOfBirth: _dobController.text,
        gmail: _gmailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      // Signed in and activated — the AuthGate behind now shows the
      // dashboard, so close the activation flow.
      AppNotifications.show(
        context,
        'Account activated! A verification link was sent to your Gmail — '
        'click it to enable password resets.',
        success: true,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) AppNotifications.show(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? 'Activate your account' : 'Secure your account'),
      ),
      body: AuthBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _progressIndicator(theme),
                  const SizedBox(height: 24),
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
                        Text(
                          _step == 0
                              ? 'Verify your identity'
                              : 'Add your Gmail & create a password',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _step == 0
                              ? 'Enter the details exactly as the exam cell '
                                  'recorded them during the fee import.'
                              : 'Your Gmail is mandatory — password reset '
                                  'links are sent there. It stays private to '
                                  'your account.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_step == 0) ...[
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
                            keyboardType: TextInputType.datetime,
                            textInputAction: TextInputAction.done,
                            validator: (v) =>
                                AppHelpers.normalizeDob(v) == null
                                    ? 'Enter your date of birth as DDMMYYYY'
                                    : null,
                            decoration: const InputDecoration(
                              labelText: 'Date of Birth',
                              hintText: 'DDMMYYYY',
                              prefixIcon: Icon(Icons.cake_outlined),
                            ),
                          ),
                        ] else ...[
                          TextFormField(
                            controller: _gmailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              final value = v?.trim().toLowerCase() ?? '';
                              if (value.isEmpty) {
                                return 'Your Gmail address is required';
                              }
                              if (!value.contains('@') ||
                                  value.endsWith(
                                      AppConstants.studentEmailDomain)) {
                                return 'Enter your personal Gmail address';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'Personal Gmail address',
                              hintText: 'you@gmail.com',
                              prefixIcon: Icon(Icons.mail_outline),
                              helperText:
                                  'Mandatory — used for password resets',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.length < 6)
                                ? 'At least 6 characters'
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Create password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(() =>
                                    _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirm,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _isLoading ? null : _activate(),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Re-enter your password'
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : (_step == 0
                                    ? _continueToSecurity
                                    : _activate),
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
                                : Text(
                                    _step == 0
                                        ? 'Continue'
                                        : 'Activate account',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                        if (_step == 1) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed:
                                _isLoading ? null : () => setState(() => _step = 0),
                            child: const Text('Back to identity details'),
                          ),
                        ],
                      ],
                    ),
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

  Widget _progressIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepDot(active: _step >= 0, theme: theme),
        _stepLine(theme),
        _stepDot(active: _step >= 1, theme: theme),
      ],
    );
  }

  Widget _stepDot({required bool active, required ThemeData theme}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppTheme.primaryColor : Colors.white,
        border: Border.all(color: AppTheme.primaryColor, width: 2),
      ),
      child: Center(
        child: Text(
          active ? '✓' : '',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _stepLine(ThemeData theme) {
    return Container(width: 48, height: 2, color: AppTheme.primaryColor);
  }
}
