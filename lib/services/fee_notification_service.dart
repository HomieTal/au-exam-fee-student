import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/student.dart';
import '../utils/constants.dart';

/// Exam-fee notifications for the Student App.
///
/// Two delivery paths:
///  1. Local reminders — the app checks the fee state when opened and
///     periodically in the background (WorkManager) and posts a system
///     notification while the exam fee is unpaid, with last-date urgency
///     tiers (normal / due tomorrow / LAST DAY).
///  2. FCM — the device's push token is registered on the student's profile
///     and subscribed to the `fee-alerts` topic so the exam cell can send
///     pushes from the Firebase Console (or a Cloud Function once the
///     project is upgraded to Blaze).
class FeeNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'fee_reminders';
  static const _channelName = 'Exam fee reminders';
  static const _notificationId = 1001;
  static const _urgentNotificationId = 1002;

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
      await FirebaseMessaging.instance.requestPermission(
        criticalAlert: false,
        provisional: false,
      );
    } catch (_) {}
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Older Android versions grant by default.
    }
  }

  /// Registers this device for FCM pushes: saves the token on the student's
  /// profile (a map, so several devices per student are supported) and
  /// subscribes to the broadcast + per-student topics.
  static Future<void> registerPush(Student student) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await FirebaseFirestore.instance
          .collection(AppConstants.studentsCollection)
          .doc(student.uid)
          .set({
            'fcmTokens': {token: FieldValue.serverTimestamp()},
          }, SetOptions(merge: true));
      await FirebaseMessaging.instance.subscribeToTopic('fee-alerts');
      await FirebaseMessaging.instance
          .subscribeToTopic('student-${student.registerNumber}');
    } catch (_) {
      // Push registration is best effort — local reminders still work.
    }
  }

  /// Checks the student's exam fee and posts a reminder when it is unpaid.
  /// Returns true when a notification was shown.
  static Future<bool> notifyIfFeeDue(Student student) async {
    await init();
    try {
      final due = await _feeDueInfo(student);
      if (due == null) return false;
      final urgent = due.urgency != Urgency.normal;
      if (!(await _remindedRecently(student, urgent))) return false;

      final amount = student.totalFee == null
          ? ''
          : ' ₹${student.totalFee!.round()}';
      final (title, body) = switch (due.urgency) {
        Urgency.lastDay => (
            'LAST DAY to pay the exam fee',
            'Today is the last date$amount. Submit the payment in the app '
                'right away.'
          ),
        Urgency.dueTomorrow => (
            'Exam fee due tomorrow',
            'The last date to pay the exam fee$amount is tomorrow. Submit '
                'the payment in the app.'
          ),
        Urgency.normal => (
            'Exam fee pending',
            'Your exam fee$amount has not been paid yet. Submit the payment '
                'in the app.'
          ),
      };
      await _plugin.show(
        id: urgent ? _urgentNotificationId : _notificationId,
        title: title,
        body: body,
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
          .set({
            urgent
                ? 'lastUrgentFeeNotifiedAt'
                : 'lastFeeNotifiedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A fee is "to pay" while the imported amount is outstanding and the
  /// latest payment submission (if any) has not been verified. Returns the
  /// amount-due info with its urgency based on the fee's last date.
  static Future<({double amount, DateTime? lastDate, Urgency urgency})?>
      _feeDueInfo(Student student) async {
    if ((student.totalFee ?? 0) <= 0) return null;
    final snapshot = await FirebaseFirestore.instance
        .collection('payments')
        .where('studentUid', isEqualTo: student.uid)
        .get();
    DateTime submittedAt(Map<String, dynamic> d) =>
        (d['submittedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
    final payments = snapshot.docs.map((d) => d.data()).toList()
      ..sort((a, b) => submittedAt(b).compareTo(submittedAt(a)));
    if (payments.isNotEmpty) {
      final status = (payments.first['status'] ?? '').toString();
      if (status == 'verified' || status == 'paid') return null;
    }

    // Last date from the active fee configuration for this department,
    // semester and academic year.
    DateTime? lastDate;
    final feeConfig = await FirebaseFirestore.instance
        .collection('fees')
        .where('department', isEqualTo: student.department)
        .where('semester', isEqualTo: student.semester)
        .where('academicYear', isEqualTo: student.academicYear)
        .get();
    for (final doc in feeConfig.docs) {
      if (doc.data()['isActive'] != true) continue;
      final raw = doc.data()['lastDate'];
      if (raw is Timestamp) lastDate = raw.toDate();
    }

    final urgency = _urgencyFor(lastDate);
    return (amount: student.totalFee!, lastDate: lastDate, urgency: urgency);
  }

  static Urgency _urgencyFor(DateTime? lastDate) {
    if (lastDate == null) return Urgency.normal;
    final today = DateTime.now();
    final last = DateTime(lastDate.year, lastDate.month, lastDate.day);
    final today0 = DateTime(today.year, today.month, today.day);
    final days = last.difference(today0).inDays;
    if (days <= 0) return Urgency.lastDay;
    if (days == 1) return Urgency.dueTomorrow;
    return Urgency.normal;
  }

  /// Normal reminders: at most one per 24 h. Urgent (last-day / due-
  /// tomorrow) reminders: at most one per 12 h, tracked separately.
  static Future<bool> _remindedRecently(Student student, bool urgent) async {
    final doc = await FirebaseFirestore.instance
        .collection(AppConstants.studentsCollection)
        .doc(student.uid)
        .get();
    final key = urgent ? 'lastUrgentFeeNotifiedAt' : 'lastFeeNotifiedAt';
    final last = doc.data()?[key];
    if (last is! Timestamp) return true;
    return DateTime.now().difference(last.toDate()).inHours >= (urgent ? 12 : 24);
  }
}

enum Urgency { normal, dueTomorrow, lastDay }
