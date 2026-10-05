import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/exam_fee.dart';
import '../models/payment.dart';
import '../models/payment_settings.dart';
import '../models/student.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

/// All Cloud Firestore access for the student app.
///
/// Layout (shared with the AU Exam Fee Admin App):
///   students/{uid}                 – student profile, keyed by Auth UID
///   payments/{paymentId}           – payment submissions
///   settings/examFee               – announced exam fee (admin managed)
///   settings/payment               – UPI collect details (admin managed)
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _students =>
      _db.collection(AppConstants.studentsCollection);
  CollectionReference<Map<String, dynamic>> get _payments =>
      _db.collection(AppConstants.paymentsCollection);

  // ── Student profile ─────────────────────────────────────────────────────

  /// One-shot fetch of the signed-in student's profile.
  Future<Student?> getStudent(String uid) async {
    try {
      final doc = await _students.doc(uid).get();
      return doc.exists ? Student.fromFirestore(doc) : null;
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }

  /// Live profile stream so admin-side edits appear without a reload.
  Stream<Student?> studentStream(String uid) {
    return _students.doc(uid).snapshots().map(
          (doc) => doc.exists ? Student.fromFirestore(doc) : null,
        );
  }

  /// Persists the profile document right after successful registration.
  /// Allowed only for the owner's own UID (see firestore.rules).
  Future<void> createStudentProfile(Student student) async {
    try {
      await _students.doc(student.uid).set(student.toMap());
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }

  /// Updates the signed-in student's own contact fields (phone and/or
  /// email). Security rules restrict student updates to exactly these keys
  /// – academic data stays exam-cell managed.
  Future<void> updateOwnContact({
    required String uid,
    String? phone,
    String? email,
  }) async {
    try {
      final updates = <String, dynamic>{
        if (phone != null) 'phone': phone.trim(),
        if (email != null) 'email': email.trim(),
      };
      if (updates.isEmpty) return;
      await _students.doc(uid).update(updates);
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }

  // ── Payments ────────────────────────────────────────────────────────────

  /// Live list of the signed-in student's payments (newest first).
  /// Filtered by `studentUid` only (single-field index is automatic) and
  /// sorted client-side, so no composite index is required.
  Stream<List<Payment>> paymentsStream(String uid) {
    return _payments
        .where('studentUid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Payment.fromFirestore).toList();
      list.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return list;
    }).handleError((e) => throw AppHelpers.friendlyError(e));
  }

  /// Live stream of the most recent payment – drives the dashboard status.
  Stream<Payment?> latestPaymentStream(String uid) {
    return paymentsStream(uid).map((list) => list.isEmpty ? null : list.first);
  }

  Future<Payment?> getLatestPayment(String uid) async {
    try {
      final snap = await _payments.where('studentUid', isEqualTo: uid).get();
      if (snap.docs.isEmpty) return null;
      final list = snap.docs.map(Payment.fromFirestore).toList()
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return list.first;
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }

  /// Returns true when this student already used [transactionId] in any of
  /// their own previous submissions (client-side duplicate check; students
  /// cannot query other students' payments).
  Future<bool> transactionIdExists({
    required String uid,
    required String transactionId,
  }) async {
    try {
      final snap = await _payments
          .where('studentUid', isEqualTo: uid)
          .get();
      final needle = transactionId.trim().toLowerCase();
      return snap.docs
          .map((d) => (d.data()['transactionId'] as String? ?? '').toLowerCase())
          .contains(needle);
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }

  /// Pre-allocates a payment document id (used for the Storage path before
  /// the payment document is written).
  String newPaymentId() => _payments.doc().id;

  /// Creates a payment document with `status: pending`.
  /// The screenshot must already be uploaded – pass its download URL.
  Future<String> submitPayment({
    String? paymentId,
    required Student student,
    required double amount,
    required String transactionId,
    required DateTime paymentDate,
    required String paymentMethod,
    required String screenshotUrl,
  }) async {
    final docRef =
        paymentId != null ? _payments.doc(paymentId) : _payments.doc();
    final payment = Payment(
      paymentId: docRef.id,
      studentUid: student.uid,
      registerNumber: student.registerNumber,
      studentName: student.name,
      semester: student.semester,
      amount: amount,
      transactionId: transactionId.trim(),
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      screenshotUrl: screenshotUrl,
      status: AppConstants.statusPending,
      submittedAt: DateTime.now(),
    );
    try {
      await docRef.set(payment.toMap());
      return docRef.id;
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }

  /// One-time population of the registration-preview fields (copied from
  /// the student's own exam-cell legacy record). Allowed once by rules —
  /// locked again once 'subjects' exists on the document.
  Future<void> updateOwnPreview({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _students.doc(uid).update(data);
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }

  // ── Settings (admin managed, student read-only) ─────────────────────────

  /// Live stream of the active exam fee for this student's department,
  /// semester and academic year from the `fees` collection – the same
  /// configuration the Admin App's "Fees" tab maintains.
  Stream<ExamFee?> examFeeStream(Student student) {
    return _db
        .collection('fees')
        .where('department', isEqualTo: student.department)
        .where('semester', isEqualTo: student.semester)
        .where('academicYear', isEqualTo: student.academicYear)
        .snapshots()
        .map((snap) {
          final active = snap.docs
              .where((doc) => doc.data()['isActive'] == true)
              .toList();
          return active.isEmpty
              ? null
              : ExamFee.fromFeeData(active.first.data());
        })
        .handleError((e) => throw AppHelpers.friendlyError(e));
  }

  /// UPI collect details shown on the payment screen (optional).
  Future<PaymentSettings?> getPaymentSettings() async {
    try {
      final doc = await _db
          .collection(AppConstants.settingsCollection)
          .doc(AppConstants.paymentSettingsDoc)
          .get();
      return doc.exists ? PaymentSettings.fromFirestore(doc) : null;
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }
}
