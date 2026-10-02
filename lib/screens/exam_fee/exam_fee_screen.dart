import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/exam_fee.dart';
import '../../models/payment.dart';
import '../../models/payment_settings.dart';
import '../../models/student.dart';
import '../../services/firestore_service.dart';
import '../../services/upi_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../widgets/fee_card.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/payment_status_card.dart';
import 'payment_submission_screen.dart';

/// Shows the announced exam fee details, current payment status and the
/// Submit Payment entry point.
class ExamFeeScreen extends StatelessWidget {
  final Student student;

  const ExamFeeScreen({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Fee')),
      body: StreamBuilder<ExamFee?>(
        stream: firestoreService.examFeeStream(student),
        builder: (context, feeSnapshot) {
          final examFee = feeSnapshot.data ??
              (student.examFee != null
                  ? ExamFee.fromStudentOverride(student.examFee!)
                  : null);

          return StreamBuilder<Payment?>(
            stream: firestoreService.latestPaymentStream(student.uid),
            builder: (context, paymentSnapshot) {
              if (paymentSnapshot.hasError) {
                return ErrorStateWidget(
                  message: paymentSnapshot.error.toString(),
                  onRetry: () {},
                );
              }
              if (paymentSnapshot.connectionState == ConnectionState.waiting) {
                return const LoadingWidget(message: 'Loading exam fee…');
              }
              final payment = paymentSnapshot.data;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FeeCard(
                    examFee: examFee,
                    student: student,
                    detailed: true,
                  ),
                  const SizedBox(height: 16),
                  PaymentStatusCard(
                    status: payment?.status,
                    rejectionReason: payment?.rejectionReason,
                    transactionId: payment?.transactionId,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(context, examFee, payment),
                  const SizedBox(height: 24),
                  if (payment != null) _SubmittedDetails(payment: payment),
                  if (payment == null)
                    _UpiDetailsCard(amount: examFee?.amount ?? 0),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    ExamFee? examFee,
    Payment? payment,
  ) {
    final hasFee = examFee != null && examFee.amount > 0;

    if (payment != null && payment.isVerified) {
      return SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          onPressed: () => _showInfoDialog(
            context,
            title: 'Payment Verified',
            message: AppConstants.msgVerified,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Payment Verified'),
        ),
      );
    }

    if (payment != null && payment.isPending) {
      return SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: () => _showInfoDialog(
            context,
            title: 'Payment Under Review',
            message:
                '${AppConstants.msgPending}\n\nTransaction ID: ${payment.transactionId}',
          ),
          icon: const Icon(Icons.hourglass_top_rounded),
          label: const Text('Awaiting Verification'),
        ),
      );
    }

    // No payment yet, or the last one was rejected → allow (re)submission.
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: () {
          if (!hasFee) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(AppConstants.msgFeeNotAnnounced)),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentSubmissionScreen(
                student: student,
                amount: examFee.amount,
              ),
            ),
          );
        },
        icon: Icon(payment?.isRejected ?? false
            ? Icons.refresh_rounded
            : Icons.payment_rounded),
        label: Text(
          payment?.isRejected ?? false ? 'Resubmit Payment' : 'Submit Payment',
        ),
      ),
    );
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Summary of the most recent submission shown while it is pending/verified.
class _SubmittedDetails extends StatelessWidget {
  final Payment payment;

  const _SubmittedDetails({required this.payment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submitted Details', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _row(theme, 'Transaction ID', payment.transactionId),
            _row(theme, 'Amount', AppHelpers.formatAmount(payment.amount)),
            _row(theme, 'Payment Date', AppHelpers.formatDate(payment.paymentDate)),
            _row(theme, 'Method', payment.paymentMethod),
            _row(theme, 'Submitted On', AppHelpers.formatDateTime(payment.submittedAt)),
            if (payment.verifiedAt != null)
              _row(theme, 'Verified On', AppHelpers.formatDateTime(payment.verifiedAt!)),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional UPI collect details + QR published by the exam cell in
/// `settings/payment`, so students know where to pay before submitting proof.
class _UpiDetailsCard extends StatefulWidget {
  final double amount;

  const _UpiDetailsCard({required this.amount});

  @override
  State<_UpiDetailsCard> createState() => _UpiDetailsCardState();
}

class _UpiDetailsCardState extends State<_UpiDetailsCard> {
  final _firestoreService = FirestoreService();
  final _upiService = UpiService();
  late final Future<PaymentSettings?> _future;

  bool _openingUpi = false;

  @override
  void initState() {
    super.initState();
    _future = _firestoreService.getPaymentSettings();
  }

  Future<void> _launchUpi(PaymentSettings settings) async {
    setState(() => _openingUpi = true);
    try {
      final error = await _upiService.launchUpiApp(
        settings: settings,
        amount: widget.amount,
        note: 'Exam Fee',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ??
              'Complete the payment in your UPI app, then tap Submit Payment '
                  'to upload the transaction details.'),
          backgroundColor:
              error == null ? Colors.green : Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingUpi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<PaymentSettings?>(
      future: _future,
      builder: (context, snapshot) {
        // UPI details are optional – silently skip on missing data/errors.
        final settings = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            settings == null ||
            settings.upiId.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Pay via UPI', style: theme.textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Pay the fee using the details below, then submit the '
                  'transaction proof.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.5)),
                    ),
                    child: QrImageView(
                      data: _upiUri(settings),
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _row(theme, 'UPI ID', settings.upiId),
                if (settings.payeeName.isNotEmpty)
                  _row(theme, 'Payee Name', settings.payeeName),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed:
                        (widget.amount <= 0 || _openingUpi) ? null : () => _launchUpi(settings),
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    icon: _openingUpi
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.account_balance_wallet_rounded),
                    label: Text(
                      widget.amount <= 0
                          ? 'Fee Not Announced'
                          : _openingUpi
                              ? 'Opening UPI apps…'
                              : 'Pay via UPI App',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'After paying, tap Submit Payment and upload the '
                  'transaction proof.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _upiUri(PaymentSettings settings) {
    final payee = Uri.encodeComponent(settings.payeeName);
    return 'upi://pay?pa=${Uri.encodeComponent(settings.upiId)}'
        '${payee.isEmpty ? '' : '&pn=$payee'}'
        '&cu=INR';
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
