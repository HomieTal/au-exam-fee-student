import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'models/student.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/auth_service.dart';
import 'services/fee_notification_service.dart';
import 'services/update_service.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';
import 'widgets/loading_widget.dart';

/// FCM background handler — required for push delivery while the app is
/// terminated. Pushes can be sent to the `fee-alerts` topic from the
/// Firebase Console today, and automatically from Cloud Functions once the
/// project is upgraded to Blaze (see functions/index.js).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
}

/// Background fee check (WorkManager): runs roughly every 15 minutes while
/// the app is installed and posts a local reminder while the exam fee is
/// unpaid — including last-day urgency.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      final uid = inputData?['uid'] as String?;
      if (uid == null || uid.isEmpty) return true;
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.studentsCollection)
          .doc(uid)
          .get();
      if (!doc.exists) return true;
      await FeeNotificationService.notifyIfFeeDue(Student.fromFirestore(doc));
      return true;
    } catch (_) {
      return true;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Constructs the auth service so its permanent authStateChanges listener
  // is wired before the gate renders (the gate reads the notifier it feeds).
  AuthService();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await Workmanager().initialize(callbackDispatcher);
  runApp(const AuExamFeeApp());
}

class AuExamFeeApp extends StatelessWidget {
  const AuExamFeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: const AuthGate(),
    );
  }
}

/// Routes between the login screen and the authenticated shell based on the
/// live Firebase Auth state, so sign-in/sign-out is reflected everywhere.
/// Email verification is requested during activation; the verification
/// link arrives directly in the student's Gmail.
/// Also checks GitHub for a newer app release once per start.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _updateService = UpdateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateService.runStartupCheck(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reads the auth user from a ValueNotifier fed by ONE permanent
    // authStateChanges listener (wired in AuthService). The earlier
    // StreamBuilder-in-build approach resubscribed on every rebuild and
    // could miss the sign-in emission, leaving the login screen up after a
    // successful sign-in.
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.authResolved,
      builder: (context, resolved, _) {
        if (!resolved) {
          return const Scaffold(
            body: LoadingWidget(message: 'Starting AU Exam Fee…'),
          );
        }
        return ValueListenableBuilder<User?>(
          valueListenable: AuthService.currentUserNotifier,
          builder: (context, user, _) {
            debugPrint('gate rebuild → user=${user?.uid ?? 'null'}');
            if (user == null) return const LoginScreen();
            return HomeShell(uid: user.uid);
          },
        );
      },
    );
  }
}
