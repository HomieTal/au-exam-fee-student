import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/notifications.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_background.dart';

/// Blocking email verification step shown before any authenticated app tab.
class EmailVerificationScreen extends StatefulWidget {
  final User user;

  const EmailVerificationScreen({super.key, required this.user});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _emailController = TextEditingController();
  final _authService = AuthService();
  final _firestore = FirestoreService();

  bool _isSending = false;
  bool _isChecking = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    final email = widget.user.email ?? '';
    if (!email.toLowerCase().endsWith(AppConstants.studentEmailDomain)) {
      _emailController.text = email;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendVerification() async {
    final email = _emailController.text.trim();
    final validationError = Validators.email(email);
    if (validationError != null) {
      AppNotifications.show(context, validationError, error: true);
      return;
    }

    setState(() => _isSending = true);
    try {
      await _authService.sendEmailVerificationTo(email);
      await _firestore.updateOwnContact(uid: widget.user.uid, email: email);
      if (!mounted) return;
      setState(() => _sent = true);
      AppNotifications.show(
        context,
        'Verification link sent to $email.',
        success: true,
      );
    } catch (e) {
      if (mounted) AppNotifications.show(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);
    try {
      final user = await _authService.reloadCurrentUser();
      if (!mounted) return;
      if (user?.emailVerified == true &&
          !(user?.email ?? '').toLowerCase().endsWith(
            AppConstants.studentEmailDomain,
          )) {
        AppNotifications.show(
          context,
          'Email verified. Welcome to ${AppConstants.appName}!',
          success: true,
        );
      } else {
        AppNotifications.show(
          context,
          'We have not received verification yet. Open the link in your email, '
          'then try again.',
          error: true,
        );
      }
    } catch (e) {
      if (mounted) AppNotifications.show(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmailAlreadySet = !(widget.user.email ?? '').toLowerCase().endsWith(
      AppConstants.studentEmailDomain,
    );

    return Scaffold(
      body: AuthBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF34506E).withValues(alpha: 0.14),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0D8),
                      borderRadius: BorderRadius.circular(42),
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_rounded,
                      size: 70,
                      color: Color(0xFFF5A623),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'VERIFY YOUR EMAIL',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _sent
                        ? 'Check your inbox and click the verification link. '
                              'You must verify your email to continue.'
                        : isEmailAlreadySet
                        ? 'We sent a verification link to your email. '
                              'Verify it to continue securely.'
                        : 'Add your personal email to receive a one-time '
                              'verification link.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  if (!isEmailAlreadySet) ...[
                    const SizedBox(height: 22),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Personal email address',
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _sendVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5A623),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _sent
                                  ? 'Resend Verification Link'
                                  : 'Send Verification Link',
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _isChecking ? null : _checkVerification,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF5A623),
                        side: const BorderSide(color: Color(0xFFF5A623)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: _isChecking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('I Have Verified My Email'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This step is required. There is no skip option.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _authService.signOut(),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
