import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/student.dart';
import '../utils/constants.dart';

/// Local exam-fee reminders.
///
/// The project is on the free (Spark) plan, so server-sent FCM pushes are
/// not available; instead the app itself checks the fee state — immediately
/// when opened and periodically in the background — and posts a system
/// notification while the exam fee is unpaid. A per-student timestamp in
/// Firestore throttles reminders to at most one per 24 hours.
class FeeNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'fee_reminders';
  static const _channelName = 'Exam fee reminders';
  static const _notificationId = 1001;

  static Future<void> init() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('launcher_icon'),
      ),
    );
    _initialized = true;
  }

  /// Android 13+ runtime permission. Safe to call repeatedly.
  static Future<void> requestPermission() async {
    await init();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Older Android versions grant by default.
    }
  }

  /// Checks the student's exam fee and posts a reminder when it is unpaid.
  /// Returns true when a notification was shown.
  static Future<bool> notifyIfFeeDue(Student student) async {
    await init();
    try {
      if (!(await _feeIsUnpaid(student))) return false;
      if (!(await _remindedRecently(student))) return false;

      final amount =
          student.totalFee == null ? '' : ' ₹${student.totalFee!.round()}';
      await _plugin.show(
        id: _notificationId,
        title: 'Exam fee pending',
        body: 'Your exam fee$amount has not been paid yet. Submit the payment '
            'in the app.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Reminders while the exam fee is unpaid',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(''),
          ),
        ),
        payload: 'exam_fee',
      );
      await FirebaseFirestore.instance
          .collection(AppConstants.studentsCollection)
          .doc(student.uid)
          .set({'lastFeeNotifiedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A fee is "to pay" while the imported amount is outstanding and the
  /// latest payment submission (if any) has not been verified.
  static Future<bool> _feeIsUnpaid(Student student) async {
    if ((student.totalFee ?? 0) <= 0) return false;
    final snapshot = await FirebaseFirestore.instance
        .collection('payments')
        .where('studentUid', isEqualTo: student.uid)
        .get();
    DateTime submittedAt(Map<String, dynamic> d) =>
        (d['submittedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
    final payments = snapshot.docs.map((d) => d.data()).toList()
      ..sort((a, b) => submittedAt(b).compareTo(submittedAt(a)));
    if (payments.isEmpty) return true;
    final status = (payments.first['status'] ?? '').toString();
    return status != 'verified' && status != 'paid';
  }

  static Future<bool> _remindedRecently(Student student) async {
    final doc = await FirebaseFirestore.instance
        .collection(AppConstants.studentsCollection)
        .doc(student.uid)
        .get();
    final last = doc.data()?['lastFeeNotifiedAt'];
    if (last is! Timestamp) return true;
    return DateTime.now().difference(last.toDate()).inHours >= 24;
  }
}
