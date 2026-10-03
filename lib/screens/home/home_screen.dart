import 'package:flutter/material.dart';

import '../../models/exam_fee.dart';
import '../../models/payment.dart';
import '../../models/student.dart';
import '../../services/firestore_service.dart';
import '../../services/upi_service.dart';
import '../../services/update_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/theme.dart';
import '../../utils/validators.dart';
import '../../utils/notifications.dart';
import '../../widgets/fee_card.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/payment_status_card.dart';
import '../exam_fee/exam_fee_screen.dart';
import '../exam_fee/registration_preview_screen.dart';
import '../history/payment_history_screen.dart';
import '../profile/profile_screen.dart';
import '../../services/auth_service.dart';

/// Bottom-navigation shell: Home · Exam Fee · History · Profile.
///
/// Also guards the signed-in state: if the Auth user has no
/// `students/{uid}` profile document, a friendly error with sign-out is
/// shown instead of the tabs.
class HomeShell extends StatelessWidget {
  final String uid;

  const HomeShell({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<Student?>(
      stream: firestoreService.studentStream(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ProfileErrorScreen(message: snapshot.error.toString());
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: LoadingWidget(message: 'Loading…'));
        }
        final student = snapshot.data;
        if (student == null) {
          return const _ProfileErrorScreen(
            message:
                'Your student profile could not be found. Please contact the '
                'exam cell so your account can be linked to a student record.',
          );
        }
        return _HomeShellBody(student: student);
      },
    );
  }
}

class _HomeShellBody extends StatefulWidget {
  final Student student;

  const _HomeShellBody({required this.student});

  @override
  State<_HomeShellBody> createState() => _HomeShellBodyState();
}

class _HomeShellBodyState extends State<_HomeShellBody> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            student: widget.student,
            onNavigate: (tab) => setState(() => _currentIndex = tab),
          ),
          ExamFeeScreen(student: widget.student),
          PaymentHistoryScreen(student: widget.student),
          ProfileScreen(student: widget.student),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Exam Fee',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────

/// Dashboard: welcome header, fee card, quick stats (semester / fee / status /
/// transaction), status card and the prominent Pay Exam Fee button.
class HomeScreen extends StatelessWidget {
  final Student student;
  final ValueChanged<int> onNavigate;

  const HomeScreen({
    super.key,
    required this.student,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // Streams keep data live; a short delay lets the indicator settle.
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _Header(
              student: student,
              onProfileTap: () => onNavigate(3),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<AppUpdate?>(
              valueListenable: UpdateService.updateNotifier,
              builder: (context, update, _) => update == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _UpdateCard(update: update),
                    ),
            ),
            if (student.needsEmailVerification) ...[
              _EmailVerificationCard(student: student),
              const SizedBox(height: 16),
            ],
            FutureBuilder<Map<String, dynamic>?>(
              future: firestoreService.studentFeeRowFuture(
                  student.registerNumber),
              builder: (context, rowSnapshot) {
                // The per-student registration-preview row (admin import)
                // carries the exact payable amount for this student.
                final rowAmount =
                    (rowSnapshot.data?['amount'] as num?)?.toDouble() ?? 0;
                return StreamBuilder<ExamFee?>(
                  stream: firestoreService.examFeeStream(student),
                  builder: (context, feeSnapshot) {
                    ExamFee? examFee = feeSnapshot.data ??
                        (student.examFee != null
                            ? ExamFee.fromStudentOverride(student.examFee!)
                            : null);
                    if (rowAmount > 0) {
                      examFee = ExamFee(
                        amount: rowAmount,
                        semester:
                            student.semester > 0 ? student.semesterLabel : null,
                        academicYear: student.academicYear,
                        lastDate: feeSnapshot.data?.lastDate,
                      );
                    }
                    return StreamBuilder<Payment?>(
                      stream: firestoreService.latestPaymentStream(student.uid),
                      builder: (context, paymentSnapshot) {
                        if (paymentSnapshot.hasError) {
                          return ErrorStateWidget(
                              message: paymentSnapshot.error.toString());
                        }
                        if (paymentSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const LoadingWidget();
                        }
                        final payment = paymentSnapshot.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FeeCard(examFee: examFee, student: student),
                            const SizedBox(height: 12),
                            _StatsGrid(
                              student: student,
                              examFee: examFee,
                              payment: payment,
                            ),
                            if (payment != null) ...[
                              const SizedBox(height: 12),
                              PaymentStatusCard(
                                status: payment.status,
                                rejectionReason: payment.rejectionReason,
                                transactionId: payment.transactionId,
                              ),
                            ],
                            const SizedBox(height: 20),
                            _PayButton(
                              student: student,
                              examFee: examFee,
                              payment: payment,
                              onNavigate: onNavigate,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Student student;
  final VoidCallback onProfileTap;

  const _Header({required this.student, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryColor, AppTheme.primaryDark],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 22),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  student.academicYear.isEmpty
                      ? 'Student'
                      : 'AY ${student.academicYear}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  // University icon placed right next to the welcome text.
                  Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(
                      'assets/images/anna_university_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          student.name.isEmpty ? 'Student' : student.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  // Profile shortcut icon.
                  IconButton(
                    onPressed: onProfileTap,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                    ),
                    icon: const Icon(Icons.person_rounded,
                        color: Colors.white, size: 22),
                    tooltip: 'Profile',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.badge_outlined,
                      size: 14, color: Colors.white.withValues(alpha: 0.85)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      student.registerNumber.isEmpty
                          ? '—'
                          : 'Reg. No. ${student.registerNumber}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (student.department.isNotEmpty) ...[
                    const SizedBox(width: 14),
                    Icon(Icons.school_outlined,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.85)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        [
                          student.department,
                          if (student.semester > 0)
                            'Sem ${student.semesterLabel}',
                        ].join(' · '),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final Student student;
  final ExamFee? examFee;
  final Payment? payment;

  const _StatsGrid({
    required this.student,
    required this.examFee,
    required this.payment,
  });

  @override
  Widget build(BuildContext context) {

    final p = payment;
    final fee = examFee;
    final hasFee = fee != null && fee.amount > 0;
    final statusLabel =
        p == null ? 'Not Submitted' : AppHelpers.statusLabel(p.status);
    final statusColor =
        p == null ? const Color(0xFF757575) : AppHelpers.statusColor(p.status);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.school_rounded,
                label: 'Current Semester',
                value: student.semester > 0 ? student.semesterLabel : '–',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.payments_rounded,
                label: 'Exam Fee',
                value: hasFee
                    ? AppHelpers.formatAmount(fee.amount)
                    : 'Not Announced',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.sync_rounded,
                label: 'Payment Status',
                value: statusLabel,
                valueColor: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.confirmation_number_outlined,
                label: 'Transaction ID',
                value: p == null || p.transactionId.isEmpty
                    ? 'Not Submitted'
                    : p.transactionId,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 18,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PayButton extends StatefulWidget {
  final Student student;
  final ExamFee? examFee;
  final Payment? payment;
  final ValueChanged<int> onNavigate;

  const _PayButton({
    required this.student,
    required this.examFee,
    required this.payment,
    required this.onNavigate,
  });

  @override
  State<_PayButton> createState() => _PayButtonState();
}

class _PayButtonState extends State<_PayButton> {
  final _firestoreService = FirestoreService();
  final _upiService = UpiService();

  bool _openingUpi = false;

  Future<void> _launchUpi() async {
    final fee = widget.examFee;
    if (fee == null || fee.amount <= 0) return;

    setState(() => _openingUpi = true);
    try {
      final settings = await _firestoreService.getPaymentSettings();
      if (settings == null) {
        if (mounted) {
          AppNotifications.show(
            context,
            'UPI details have not been configured yet.',
            error: true,
          );
        }
        return;
      }
      final error = await _upiService.launchUpiApp(
        settings: settings,
        amount: fee.amount,
        note: 'Exam Fee ${widget.student.registerNumber}',
      );
      if (!mounted) return;
      if (error != null) {
        AppNotifications.show(context, error, error: true);
      } else {
        AppNotifications.show(
          context,
          'Complete the payment in your UPI app, then tap Submit Payment '
          'to submit the transaction details.',
          success: true,
        );
      }
    } finally {
      if (mounted) setState(() => _openingUpi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final fee = widget.examFee;
    final hasFee = fee != null && fee.amount > 0;
    // UPI quick-pay is useful before a submission exists (or to retry one
    // that was rejected); once submitted/verified there is nothing to pay.
    final showUpi = hasFee && (p == null || p.isRejected);

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (!hasFee) {
                AppNotifications.show(context, AppConstants.msgFeeNotAnnounced);
                return;
              }
              if (p != null && p.isVerified) {
                widget.onNavigate(2); // History – view the verified receipt
                return;
              }
              if (p != null && p.isPending) {
                widget.onNavigate(1); // Exam Fee – shows submitted status
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RegistrationPreviewScreen(
                    student: widget.student,
                    fallbackAmount: fee.amount,
                  ),
                ),
              );
            },
            icon: Icon(
              p?.isVerified ?? false
                  ? Icons.receipt_long_rounded
                  : Icons.payment_rounded,
            ),
            label: Text(
              p == null
                  ? 'Submit Payment'
                  : p.isVerified
                      ? 'View Payment Receipt'
                      : p.isPending
                          ? 'View Submitted Payment'
                          : 'Resubmit Payment',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (showUpi) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _openingUpi ? null : _launchUpi,
              icon: _openingUpi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.qr_code_2_rounded),
              label: Text(
                _openingUpi ? 'Opening UPI apps…' : 'Pay via UPI App',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Shown when the Auth account exists but has no matching student profile.
class _ProfileErrorScreen extends StatelessWidget {
  final String message;

  const _ProfileErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: EmptyStateWidget(
          icon: Icons.account_circle_outlined,
          title: 'Profile not found',
          message: message,
          action: OutlinedButton.icon(
            onPressed: () => AuthService().signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign Out'),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// In-app update card
// ─────────────────────────────────────────────────────────────────────────────

/// Auto-popup card shown on the dashboard when a newer GitHub release is
/// available. Stays until the student taps Later or updates.
class _UpdateCard extends StatelessWidget {
  final AppUpdate update;

  const _UpdateCard({required this.update});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_alt_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Update available – v${update.version}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      UpdateService.updateNotifier.value = null,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Dismiss',
                ),
              ],
            ),
            if (update.changelog.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                update.changelog.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: () => UpdateService().showUpdateDialog(
                    context, update),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Update Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// First-login email verification
// ─────────────────────────────────────────────────────────────────────────────

/// Card popup shown after the first (auto-provisioned) login: the student
/// adds their personal email and receives the Firebase verification mail.
/// The register-number login keeps working until the link is clicked.
class _EmailVerificationCard extends StatefulWidget {
  final Student student;

  const _EmailVerificationCard({required this.student});

  @override
  State<_EmailVerificationCard> createState() =>
      _EmailVerificationCardState();
}

class _EmailVerificationCardState extends State<_EmailVerificationCard> {
  final _authService = AuthService();
  final _emailController = TextEditingController();

  bool _sending = false;
  bool _dismissed = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (Validators.email(email) != null) {
      AppNotifications.show(context, 'Enter a valid email address.', error: true);
      return;
    }

    setState(() => _sending = true);
    try {
      await _authService.sendEmailVerificationTo(email);
      // Record the pending email so the card does not reappear.
      await FirestoreService().updateOwnContact(
          uid: widget.student.uid, email: email);
      if (!mounted) return;
      setState(() => _sent = true);
      AppNotifications.show(
        context,
        'Verification mail sent to $email. Click the link to activate '
        'it — you can then sign in with this email.',
        success: true,
      );
    } catch (e) {
      if (mounted) {
        AppNotifications.show(context, e.toString(), error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mark_email_unread_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Verify your email',
                      style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Later',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _sent
                  ? 'Verification mail sent! Click the link in your inbox to '
                      'activate this email for sign-in.'
                  : 'Add your personal email ID — we will send a one-time '
                      'verification link. This keeps your account secure.',
              style: theme.textTheme.bodyMedium,
            ),
            if (!_sent) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send Verification Link'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
