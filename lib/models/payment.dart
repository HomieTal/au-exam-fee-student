import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/helpers.dart';

/// A payment submission stored at `payments/{paymentId}`.
///
/// Status flow: `pending` → `verified` | `rejected`.
/// Only the Admin App may move a payment out of `pending` (enforced by
/// Firestore security rules); the student app reads status changes live.
class Payment {
  final String paymentId;
  final String studentUid;
  final String registerNumber;
  final String studentName;
  final int semester;
  final double amount;
  final String transactionId;
  final DateTime paymentDate;
  final String paymentMethod;
  final String screenshotUrl;
  final String receiptText;
  final String verificationMethod;
  final String status;
  final String? rejectionReason;
  final DateTime submittedAt;
  final DateTime? verifiedAt;

  Payment({
    required this.paymentId,
    required this.studentUid,
    required this.registerNumber,
    required this.studentName,
    required this.semester,
    required this.amount,
    required this.transactionId,
    required this.paymentDate,
    required this.paymentMethod,
    required this.screenshotUrl,
    this.receiptText = '',
    this.verificationMethod = '',
    required this.status,
    this.rejectionReason,
    required this.submittedAt,
    this.verifiedAt,
  });

  bool get isPending => status == 'pending';
  bool get isVerified => status == 'verified';
  bool get isRejected => status == 'rejected';

  String get semesterLabel => AppHelpers.intToRoman(semester);

  factory Payment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Payment(
      paymentId: doc.id,
      studentUid: data['studentUid'] as String? ?? '',
      registerNumber: data['registerNumber'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      semester: AppHelpers.parseSemesterOrYear(data['semester']),
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      transactionId: data['transactionId'] as String? ?? '',
      paymentDate: _toDate(data['paymentDate']),
      paymentMethod: data['paymentMethod'] as String? ?? 'UPI',
      screenshotUrl: data['screenshotUrl'] as String? ?? '',
      receiptText: data['receiptText'] as String? ?? '',
      verificationMethod: data['verificationMethod'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      rejectionReason: data['rejectionReason'] as String?,
      submittedAt: _toDate(data['submittedAt']),
      verifiedAt: data['verifiedAt'] == null
          ? null
          : _toDate(data['verifiedAt']),
    );
  }

  static DateTime _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'studentUid': studentUid,
      'registerNumber': registerNumber,
      'studentName': studentName,
      'semester': semester,
      'amount': amount,
      'transactionId': transactionId,
      'paymentDate': paymentDate,
      'paymentMethod': paymentMethod,
      'screenshotUrl': screenshotUrl,
      'receiptText': receiptText,
      'verificationMethod': verificationMethod,
      'status': status,
      'rejectionReason': rejectionReason,
      'submittedAt': submittedAt,
      'verifiedAt': verifiedAt,
    };
  }
}
