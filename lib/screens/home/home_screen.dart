import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import '../../services/fee_notification_service.dart';

import '../../models/exam_fee.dart';
import '../../models/payment.dart';
import '../../models/student.dart';
import '../../services/firestore_service.dart';
import '../../services/update_service.dart';
import '../../utils/helpers.dart';
import '../../utils/theme.dart';
import '../../widgets/fee_card.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/payment_status_card.dart';
import '../exam_fee/exam_fee_screen.dart';
import '../exam_fee/payment_submission_screen.dart';
import '../exam_fee/registration_preview_screen.dart';
import '../history/payment_history_screen.dart';
import '../profile/profile_screen.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';

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
class HomeScreen extends StatefulWidget {
  final Student student;
  final ValueChanged<int> onNavigate;

  const HomeScreen({
    super.key,
    required this.student,
    required this.onNavigate,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _firestoreService = FirestoreService();
  late final Stream<ExamFee?> _examFeeStream;
  late final Stream<Payment?> _paymentStream;

  @override
  void initState() {
    super.initState();
    _examFeeStream = _firestoreService.examFeeStream(widget.student);
    _paymentStream = _firestoreService.latestPaymentStream(widget.student.uid);
    _healLoginIndex();
    _setupFeeReminders();
  }

  /// Local fee reminders + FCM registration: ask for the notification
  /// permission, register the device for pushes, remind once now if the
  /// exam fee is unpaid, and keep a 15-minute background check running
  /// while the app is installed.
  Future<void> _setupFeeReminders() async {
    try {
      await FeeNotificationService.requestPermission();
      await FeeNotificationService.registerPush(widget.student);
      await FeeNotificationService.notifyIfFeeDue(widget.student);
      await Workmanager().registerPeriodicTask(
        'fee-check-${widget.student.uid}',
        'feeCheckTask',
        inputData: {'uid': widget.student.uid},
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {
      // Reminders are best effort.
    }
  }

  /// After the student clicks the verification link from activation,
  /// Firebase switches the account email to their personal Gmail — refresh
  /// the login index so sign-in and password resets resolve to the working
  /// address. No-op while the account still uses the exam-cell identity.
  Future<void> _healLoginIndex() async {
    try {
      final user = AuthService().currentUser;
      final email = user?.email?.toLowerCase() ?? '';
      if (user == null ||
          email.isEmpty ||
          email.endsWith(AppConstants.studentEmailDomain)) {
        return;
      }
      await AuthService().publishLoginIndex(
        registerNumber: widget.student.registerNumber,
        email: email,
      );
    } catch (_) {
      // Best effort — retried on the next app start.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _Header(
              student: widget.student,
              onProfileTap: () => widget.onNavigate(3),
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
            Builder(
              builder: (context) {
                // The student's own profile carries the exact payable
                // amount from the exam-cell import.
                final rowAmount = widget.student.totalFee ?? 0;
                return StreamBuilder<ExamFee?>(
                  stream: _examFeeStream,
                  builder: (context, feeSnapshot) {
                    ExamFee? examFee = feeSnapshot.data;
                    if (examFee != null && rowAmount > 0) {
                      examFee = ExamFee(
                        amount: rowAmount,
                        semester: widget.student.semester > 0
                            ? widget.student.semesterLabel
                            : null,
                        academicYear: widget.student.academicYear,
                        lastDate: feeSnapshot.data?.lastDate,
                      );
                    }
                    return StreamBuilder<Payment?>(
                      stream: _paymentStream,
                      builder: (context, paymentSnapshot) {
                        if (paymentSnapshot.hasError) {
                          return ErrorStateWidget(
                            message: paymentSnapshot.error.toString(),
                          );
                        }
                        if (paymentSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const LoadingWidget();
                        }
                        final payment = paymentSnapshot.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FeeCard(examFee: examFee, student: widget.student),
                            const SizedBox(height: 12),
                            _StatsGrid(
                              student: widget.student,
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
                              student: widget.student,
                              examFee: examFee,
                              payment: payment,
                              onNavigate: widget.onNavigate,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                    icon: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    tooltip: 'Profile',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
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
                    Icon(
                      Icons.school_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
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
    final statusLabel = p == null
        ? 'Not Submitted'
        : AppHelpers.statusLabel(p.status);
    final statusColor = p == null
        ? const Color(0xFF757575)
        : AppHelpers.statusColor(p.status);

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
  void _openPreview() {
    final fee = widget.examFee;
    if (fee == null || fee.amount <= 0) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrationPreviewScreen(
          student: widget.student,
          fallbackAmount: fee.amount,
        ),
      ),
    );
  }

  void _openSubmission() {
    final fee = widget.examFee;
    if (fee == null || fee.amount <= 0) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSubmissionScreen(
          student: widget.student,
          amount: fee.amount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final fee = widget.examFee;
    final hasFee = fee != null && fee.amount > 0;
    // UPI quick-pay is useful before a submission exists (or to retry one
    // that was rejected); once submitted/verified there is nothing to pay.
    final showUpi = hasFee && (p == null || p.isRejected);

    final primaryButton = SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          disabledBackgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.5),
        ),
        onPressed: !hasFee
            ? null
            : () {
                if (p != null && p.isVerified) {
                  widget.onNavigate(2); // History - view the verified receipt
                  return;
                }
                if (p != null && p.isPending) {
                  widget.onNavigate(1); // Exam Fee - shows submitted status
                  return;
                }
                _openSubmission();
              },
        icon: Icon(
          p?.isVerified ?? false
              ? Icons.receipt_long_rounded
              : Icons.payment_rounded,
        ),
        label: Text(
          !hasFee
              ? 'Fee Not Announced'
              : p == null
              ? 'Submit Payment'
              : p.isVerified
              ? 'View Payment Receipt'
              : p.isPending
              ? 'View Submitted Payment'
              : 'Resubmit Payment',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );

    final upiButton = showUpi
        ? SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _openPreview,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Pay', style: TextStyle(fontSize: 14)),
            ),
          )
        : null;

    // Pay opens the preview; Submit Payment opens the payment-details form.
    return Column(
      children: [
        if (upiButton != null) ...[upiButton, const SizedBox(height: 10)],
        primaryButton,
      ],
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
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Update available – v${update.version}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => UpdateService.updateNotifier.value = null,
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
                onPressed: () =>
                    UpdateService().showUpdateDialog(context, update),
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
