import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class ReceiptOcrResult {
  final String text;
  final String transactionId;
  final double? amount;

  const ReceiptOcrResult({
    required this.text,
    required this.transactionId,
    required this.amount,
  });
}

class ReceiptOcrService {
  Future<ReceiptOcrResult> readReceipt({
    required XFile screenshot,
    required String expectedTransactionId,
    required double expectedAmount,
  }) async {
    final file = File(screenshot.path);
    if (!await file.exists()) {
      throw 'The selected screenshot could not be read. Please pick it again.';
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      final text = result.text.trim();
      final compactText = _compact(text);
      final expectedId = _compact(expectedTransactionId);

      if (text.isEmpty) {
        throw 'No readable payment details were found in the screenshot.';
      }
      if (!compactText.contains(expectedId)) {
        throw 'The transaction ID in the screenshot does not match the entered ID.';
      }

      final amount = _findAmount(text, expectedAmount);
      if (amount == null) {
        throw 'The payment amount in the screenshot does not match '
            '${_formatAmount(expectedAmount)}.';
      }

      return ReceiptOcrResult(
        text: text,
        transactionId: expectedTransactionId.trim(),
        amount: amount,
      );
    } finally {
      await recognizer.close();
    }
  }

  String _compact(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  double? _findAmount(String text, double expected) {
    final matches = RegExp(
      r'(?:₹|Rs\.?|INR)?\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?',
      caseSensitive: false,
    ).allMatches(text);
    for (final match in matches) {
      final value = double.tryParse(
        match.group(0)!.replaceAll(RegExp(r'[^0-9.]'), ''),
      );
      if (value != null && (value - expected).abs() < 0.01) return value;
    }
    return null;
  }

  String _formatAmount(double amount) =>
      '₹${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}';
}
