import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/payment.dart';
import '../../models/student.dart';
import '../../services/firestore_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/loading_widget.dart';

/// Lists the student's previous payment submissions (newest first).
/// Tapping an item opens the full payment details.
class PaymentHistoryScreen extends StatelessWidget {
  final Student student;

  const PaymentHistoryScreen({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Payment History')),
      body: StreamBuilder<List<Payment>>(
        stream: firestoreService.paymentsStream(student.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorStateWidget(
              message: snapshot.error.toString(),
              onRetry: () {},
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: 'Loading payments…');
          }

          final payments = snapshot.data ?? [];
          if (payments.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.receipt_long_outlined,
              title: 'No Payments Yet',
              message:
                  'Your submitted exam fee payments will appear here with '
                  'their verification status.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final payment = payments[index];
              return _PaymentHistoryItem(
                payment: payment,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PaymentDetailsScreen(payment: payment),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PaymentHistoryItem extends StatelessWidget {
  final Payment payment;
  final VoidCallback onTap;

  const _PaymentHistoryItem({required this.payment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Semester ${payment.semester > 0 ? payment.semesterLabel : '–'}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  StatusChip(status: payment.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                AppHelpers.formatAmount(payment.amount),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _metaRow(theme, Icons.confirmation_number_outlined,
                  'Txn ID: ${payment.transactionId}'),
              const SizedBox(height: 4),
              _metaRow(theme, Icons.calendar_today_outlined,
                  'Paid on: ${AppHelpers.formatDate(payment.paymentDate)}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payment details
// ─────────────────────────────────────────────────────────────────────────────

/// Complete details of a single payment, including the uploaded screenshot
/// and the admin's rejection reason (if any).
class PaymentDetailsScreen extends StatelessWidget {
  final Payment payment;

  const PaymentDetailsScreen({super.key, required this.payment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Payment Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  StatusChip(status: payment.status),
                  const SizedBox(height: 12),
                  Text(
                    AppHelpers.formatAmount(payment.amount),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusMessage(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Information', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _detailRow(theme, 'Student Name', payment.studentName),
                  _detailRow(theme, 'Register Number', payment.registerNumber),
                  _detailRow(theme, 'Semester', payment.semester > 0 ? payment.semesterLabel : '–'),
                  _detailRow(theme, 'Amount', AppHelpers.formatAmount(payment.amount)),
                  _detailRow(theme, 'Transaction ID', payment.transactionId),
                  _detailRow(theme, 'Payment Method', payment.paymentMethod),
                  _detailRow(theme, 'Payment Date', AppHelpers.formatDate(payment.paymentDate)),
                  _detailRow(theme, 'Submitted On', AppHelpers.formatDateTime(payment.submittedAt)),
                  if (payment.verifiedAt != null)
                    _detailRow(theme, 'Verified On', AppHelpers.formatDateTime(payment.verifiedAt!)),
                  if (payment.isRejected &&
                      payment.rejectionReason?.trim().isNotEmpty == true)
                    _detailRow(theme, 'Rejection Reason', payment.rejectionReason!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Payment Proof', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (payment.screenshotUrl.isNotEmpty)
            GestureDetector(
              onTap: () => _viewScreenshotFullscreen(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: payment.screenshotUrl,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    height: 220,
                    color: theme.dividerColor.withValues(alpha: 0.3),
                    child: const LoadingWidget(),
                  ),
                  errorWidget: (_, _, _) => Container(
                    height: 160,
                    color: theme.dividerColor.withValues(alpha: 0.3),
                    child: const Icon(Icons.broken_image_outlined, size: 40),
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Receipt verified on this device',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    payment.receiptText.isEmpty
                        ? 'Receipt text is not available.'
                        : payment.receiptText,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _statusMessage() {
    switch (payment.status) {
      case 'pending':
        return 'Payment submitted. Waiting for admin verification.';
      case 'verified':
        return 'Payment verified successfully.';
      case 'rejected':
        return 'Payment was rejected. Please check the reason and submit again.';
      default:
        return 'Status unknown.';
    }
  }

  void _viewScreenshotFullscreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Payment Proof')),
          body: Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: payment.screenshotUrl,
                placeholder: (_, _) => const LoadingWidget(),
                errorWidget: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _detailRow(ThemeData theme, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '–' : value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleMedium,
          ),
        ),
      ],
    ),
  );
}
