import 'package:url_launcher/url_launcher.dart';

import '../models/payment_settings.dart';

/// Launches the phone's UPI app chooser with a pre-filled collect request
/// (GPay / PhonePe / Paytm / any UPI-capable app installed on the device).
class UpiService {
  /// Builds the standard `upi://pay` deep link and opens it with an
  /// external application intent.
  ///
  /// Returns null on success, or a user-friendly error message.
  Future<String?> launchUpiApp({
    required PaymentSettings settings,
    required double amount,
    String? note,
  }) async {
    if (settings.upiId.trim().isEmpty) {
      return 'UPI details have not been configured by the exam cell yet.';
    }

    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': settings.upiId.trim(),
        if (settings.payeeName.trim().isNotEmpty)
          'pn': settings.payeeName.trim(),
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        if (note != null && note.trim().isNotEmpty) 'tn': note.trim(),
      },
    );

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        return 'No UPI app found on this device.';
      }
      return null;
    } catch (_) {
      return 'No UPI app found on this device. '
          'Please install GPay, PhonePe, Paytm or another UPI app.';
    }
  }
}
