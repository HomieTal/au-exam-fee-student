import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/student.dart';
import '../../services/firestore_service.dart';
import '../../services/receipt_ocr_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/validators.dart';
import '../../utils/notifications.dart';

/// Payment submission form: transaction ID / UTR, payment date, payment
/// method and a required screenshot of the payment proof.
///
/// On submit: receipt screenshot → on-device OCR validation → Firestore
/// payment document with `status: pending`. The screenshot is not uploaded.
class PaymentSubmissionScreen extends StatefulWidget {
  final Student student;
  final double amount;
  final String? rejectionReason;

  const PaymentSubmissionScreen({
    super.key,
    required this.student,
    required this.amount,
    this.rejectionReason,
  });

  @override
  State<PaymentSubmissionScreen> createState() =>
      _PaymentSubmissionScreenState();
}

class _PaymentSubmissionScreenState extends State<PaymentSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _receiptOcrService = ReceiptOcrService();
  final _imagePicker = ImagePicker();

  final _transactionIdController = TextEditingController();
  final _paymentDateController = TextEditingController();
  final _screenshotFieldKey = GlobalKey<FormFieldState<bool>>();

  DateTime? _paymentDate;
  String? _paymentMethod;
  XFile? _screenshot;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _transactionIdController.dispose();
    _paymentDateController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 70,
      );
      if (picked == null) return;

      if (await picked.length() > AppConstants.maxScreenshotBytes) {
        if (mounted) {
          AppNotifications.show(
            context,
            'Screenshot is too large. Please choose an image under 5 MB.',
            error: true,
          );
        }
        return;
      }

      setState(() => _screenshot = picked);
      _screenshotFieldKey.currentState?.didChange(true);
    } catch (_) {
      if (mounted) {
        AppNotifications.show(context, 'Could not pick the screenshot.', error: true);
      }
    }
  }

  Future<void> _pickPaymentDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate ?? today,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: 'Select payment date',
    );
    if (picked != null) {
      setState(() {
        _paymentDate = picked;
        _paymentDateController.text = AppHelpers.formatDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    // 1. Validate the form (transaction ID, date, method, screenshot).
    if (!_formKey.currentState!.validate()) return;

    final ok = await _confirmSubmission();
    if (!ok || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      // 2. Connectivity pre-check for a friendlier failure.
      if (!await AppHelpers.hasInternet()) {
        throw AppConstants.msgNetworkError;
      }

      // 3. Prevent reuse of a transaction ID the student already submitted.
      final duplicate = await _firestoreService.transactionIdExists(
        uid: widget.student.uid,
        transactionId: _transactionIdController.text,
      );
      if (duplicate) {
        throw 'This Transaction ID has already been submitted. '
            'Please check and enter the correct one.';
      }

      // 4. Verify the receipt locally before writing any payment document.
      final receipt = await _receiptOcrService.readReceipt(
        screenshot: _screenshot!,
        expectedTransactionId: _transactionIdController.text,
        expectedAmount: widget.amount,
      );
      final paymentId = _firestoreService.newPaymentId();

      // 5. Create the payment document only after OCR validation succeeds.
      await _firestoreService.submitPayment(
        paymentId: paymentId,
        student: widget.student,
        amount: widget.amount,
        transactionId: _transactionIdController.text,
        paymentDate: _paymentDate!,
        paymentMethod: _paymentMethod!,
        receiptText: receipt.text,
        verificationMethod: 'local_ocr',
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded,
              color: Colors.green, size: 56),
          title: const Text('Payment Submitted'),
          content: const Text(
            '${AppConstants.msgPending}\n\n'
            'You can track the verification status on the Home and History tabs.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppNotifications.show(context, e.toString(), error: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _confirmSubmission() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit Payment?'),
        content: Text(
          'Amount: ${AppHelpers.formatAmount(widget.amount)}\n'
          'Transaction ID: ${_transactionIdController.text.trim()}\n'
          'Method: $_paymentMethod\n\n'
          'Please confirm the details are correct. The exam cell will verify '
          'your payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Submit Payment')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.rejectionReason != null &&
                widget.rejectionReason!.trim().isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: theme.colorScheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Previous payment was rejected: '
                          '${widget.rejectionReason}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.payments_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Amount to Pay', style: theme.textTheme.bodySmall),
                        Text(
                          AppHelpers.formatAmount(widget.amount),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _transactionIdController,
              textCapitalization: TextCapitalization.characters,
              validator: Validators.transactionId,
              decoration: const InputDecoration(
                labelText: 'Transaction ID / UTR Number *',
                hintText: 'e.g. 402312345678',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              readOnly: true,
              controller: _paymentDateController,
              onTap: _isSubmitting ? null : _pickPaymentDate,
              validator: (_) =>
                  _paymentDate == null ? 'Payment date is required' : null,
              decoration: const InputDecoration(
                labelText: 'Payment Date *',
                hintText: 'Select the date you paid',
                prefixIcon: Icon(Icons.calendar_today_outlined),
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              items: AppConstants.paymentMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _paymentMethod = v),
              validator: (v) =>
                  v == null ? 'Please select a payment method' : null,
              decoration: const InputDecoration(
                labelText: 'Payment Method *',
                prefixIcon: Icon(Icons.credit_card_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Text('Payment Screenshot *', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Upload a clear screenshot or photo of your payment receipt '
              '(UPI confirmation, bank statement, etc.).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _ScreenshotPicker(
              screenshot: _screenshot,
              onPick: _pickScreenshot,
              onRemove: () {
                setState(() => _screenshot = null);
                _screenshotFieldKey.currentState?.didChange(false);
              },
            ),
            FormField<bool>(
              key: _screenshotFieldKey,
              initialValue: _screenshot != null,
              validator: (_) =>
                  _screenshot == null ? 'Payment screenshot is required' : null,
              builder: (state) {
                if (state.errorText == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.errorText!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_rounded),
                label: Text(
                  _isSubmitting ? 'Submitting…' : 'Submit Payment Details',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ScreenshotPicker extends StatelessWidget {
  final XFile? screenshot;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ScreenshotPicker({
    required this.screenshot,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (screenshot == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPick,
        child: Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            color: theme.colorScheme.primary.withValues(alpha: 0.04),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                'Tap to upload screenshot',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(screenshot!.path),
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _iconButton(context, Icons.refresh_rounded, 'Change', onPick),
              const SizedBox(width: 8),
              _iconButton(context, Icons.delete_outline_rounded, 'Remove',
                  onRemove),
            ],
          ),
        ),
      ],
    );
  }

  Widget _iconButton(
      BuildContext context, IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
