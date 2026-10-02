import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/helpers.dart';

/// Status card used on the dashboard and exam fee screen. Shows the
/// state-specific message and, for rejected payments, the admin's reason.
class PaymentStatusCard extends StatelessWidget {
  final String? status; // null → not submitted
  final String? rejectionReason;
  final String? transactionId;
  final VoidCallback? onTap;

  const PaymentStatusCard({
    super.key,
    this.status,
    this.rejectionReason,
    this.transactionId,
    this.onTap,
  });

  String get _message {
    switch (status) {
      case AppConstants.statusPending:
        return AppConstants.msgPending;
      case AppConstants.statusVerified:
        return AppConstants.msgVerified;
      case AppConstants.statusRejected:
        return AppConstants.msgRejected;
      default:
        return 'You have not submitted the exam fee payment yet.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status == null
        ? const Color(0xFF757575)
        : AppHelpers.statusColor(status!);
    final icon = status == null
        ? Icons.receipt_long_rounded
        : AppHelpers.statusIcon(status!);
    final label =
        status == null ? 'Not Submitted' : AppHelpers.statusLabel(status!);

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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Payment Status',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_message, style: theme.textTheme.bodyMedium),
              if (transactionId != null && transactionId!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Transaction ID: $transactionId',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (status == AppConstants.statusRejected &&
                  rejectionReason != null &&
                  rejectionReason!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: theme.colorScheme.error),
                          const SizedBox(width: 6),
                          Text(
                            'Reason from admin',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rejectionReason!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
