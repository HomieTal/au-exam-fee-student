import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentSettings {
  final bool enabled;
  final String upiId;
  final String payeeName;
  final String qrImageUrl;

  PaymentSettings({
    required this.enabled,
    required this.upiId,
    required this.payeeName,
    required this.qrImageUrl,
  });

  factory PaymentSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentSettings(
      enabled: data['enabled'] ?? false,
      upiId: data['upiId'] ?? '',
      payeeName: data['payeeName'] ?? '',
      qrImageUrl: data['qrImageUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'upiId': upiId,
      'payeeName': payeeName,
      'qrImageUrl': qrImageUrl,
    };
  }
}
