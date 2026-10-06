import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/student.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

/// Firebase Authentication wrapper – register-number + password sign-in,
/// one-time account activation (register number + DOB + personal Gmail +
/// own password), password reset and logout. No credentials are ever
/// written to Firestore; the public `loginIndex/{registerNumber}` document
/// only maps a register number to its auth email so sign-in and password
/// reset can resolve before the student is authenticated.
class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// The live auth user, updated by a single permanent listener that is
  /// wired once per app run. The AuthGate reads this instead of subscribing
  /// to authStateChanges itself — a StreamBuilder that resubscribes on every
  /// rebuild can miss emissions during the resubscription window, which made
  /// successful sign-ins appear to "do nothing".
  static final ValueNotifier<User?> currentUserNotifier =
      ValueNotifier(null);
  static final ValueNotifier<bool> authResolved = ValueNotifier(false);
  static bool _notifierWired = false;

  /// Bumped on every auth-relevant action (activation, sign-in, sign-out).
  /// Kept as an extra trigger for listeners; the currentUserNotifier above
  /// is updated by the permanent authStateChanges listener.
  static final ValueNotifier<int> authRefreshTick = ValueNotifier(0);

  static void pingAuthRefresh() => authRefreshTick.value++;

  void _wireNotifier() {
    if (_notifierWired) return;
    _notifierWired = true;
    currentUserNotifier.value = _firebaseAuth.currentUser;
    _firebaseAuth.authStateChanges().listen((user) {
      debugPrint('authStateChanges → ${user?.uid ?? 'null'}');
      currentUserNotifier.value = user;
      authResolved.value = true;
    });
  }

  AuthService() {
    _wireNotifier();
  }

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  String _legacyEmail(String regNo) =>
      '${regNo.toLowerCase()}${AppConstants.studentEmailDomain}';

  /// Resolves the auth email for a register number from the public
  /// `loginIndex` collection. Returns null when the register number has no
  /// activated account yet.
  Future<String?> resolveLoginEmail(String registerNumber) async {
    final regNo = registerNumber.trim().toUpperCase();
    try {
      final doc = await _db.collection('loginIndex').doc(regNo).get();
      final email = doc.data()?['email'] as String?;
      return (email == null || email.isEmpty) ? null : email;
    } catch (_) {
      return null;
    }
  }

  /// Signs in with register number + the password chosen at activation.
  ///
  /// Tries the login-index email first, then the exam-cell identity as a
  /// fallback — covering the window where the verification link has already
  /// switched the account email but the index has not been refreshed yet.
  Future<UserCredential> signInWithRegisterNumber({
    required String registerNumber,
    required String password,
  }) async {
    final regNo = registerNumber.trim().toUpperCase();
    debugPrint('signIn: resolving login index for $regNo');
    final indexEmail = await resolveLoginEmail(regNo);
    debugPrint('signIn: resolved email ${indexEmail ?? '<none>'}');

    final candidates = <String>[
      ?indexEmail,
      _legacyEmail(regNo),
    ];
    Object? lastError;
    for (final email in candidates) {
      try {
        final credential = await _firebaseAuth
            .signInWithEmailAndPassword(email: email, password: password)
            .timeout(const Duration(seconds: 25));
        debugPrint('signIn: success via $email for ${credential.user?.uid}');
        pingAuthRefresh();
        return credential;
      } on FirebaseAuthException catch (e) {
        debugPrint('signIn: FirebaseAuthException ${e.code} for $email');
        // Wrong password → stop immediately; the other identity would fail
        // with the same password anyway.
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          lastError = e;
          break;
        }
        if (e.code == 'user-not-found' || e.code == 'too-many-requests') {
          lastError = e;
          continue;
        }
        throw AppHelpers.friendlyError(e);
      } on TimeoutException {
        lastError = TimeoutException(
            'The sign-in request timed out. Check your internet connection '
            'and try again.');
        continue;
      } catch (e) {
        debugPrint('signIn: unexpected error $e');
        lastError = e;
      }
    }
    if (lastError is FirebaseAuthException) {
      throw 'Sign-in failed. Please check your password, or use "Forgot '
          'Password?" if you cannot remember it.';
    }
    if (lastError is TimeoutException) throw lastError.message ?? lastError;
    if (lastError != null) throw AppHelpers.friendlyError(lastError);
    throw 'No activated account was found for this register number.\n'
        'First time? Use "Activate your account" below.';
  }

  /// One-time account activation — gmail-first.
  ///
  /// The register number + date of birth are verified against a hashed DOB
  /// record the exam cell published at import (`activation/{registerNumber}`,
  /// publicly readable, hash only — the DOB itself never leaves the form).
  /// The Auth account is then created DIRECTLY with the student's personal
  /// Gmail and chosen password, so Firebase stores the Gmail as the login
  /// identity from the start — no `@au.edu.in` placeholder identity, no
  /// verification-link click, and "Forgot Password" reaches their real
  /// inbox immediately. `loginIndex` is published for sign-in resolution.
  Future<void> activateAccount({
    required String registerNumber,
    required String dateOfBirth,
    required String gmail,
    required String password,
  }) async {
    final regNo = registerNumber.trim().toUpperCase();
    final dob = AppHelpers.normalizeDob(dateOfBirth);
    if (dob == null) {
      throw 'Enter your date of birth as DDMMYYYY (e.g. 05082005).';
    }
    final email = gmail.trim().toLowerCase();
    if (!email.contains('@') ||
        email.endsWith(AppConstants.studentEmailDomain)) {
      throw 'Enter your personal Gmail address (not a college address).';
    }
    if (password.length < 6) {
      throw 'Choose a password with at least 6 characters.';
    }

    // Already activated? Point the student to sign-in / reset instead of
    // silently creating a second account for the same register number.
    final existing = await resolveLoginEmail(regNo);
    if (existing != null) {
      throw 'This register number is already activated. Please sign in, or '
          'use "Forgot Password?" if you cannot remember your password.';
    }

    // ---- Verify the DOB against the hashed activation record ------------
    final activation = await _db.collection('activation').doc(regNo).get();
    if (!activation.exists) {
      throw 'No exam-cell record was found for register number $regNo. '
          'Use Register instead, or contact the exam cell.';
    }
    final expectedHash =
        (activation.data()?['dobHash'] as String?)?.toLowerCase() ?? '';
    final enteredHash = _activationDobHash(regNo, dob);
    if (expectedHash != enteredHash) {
      throw 'Incorrect date of birth for this register number.';
    }

    // ---- Create the Auth account with the student's own credentials -----
    UserCredential credential;
    try {
      credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // A previous attempt already created this account — sign in and
        // finish the activation instead of failing.
        try {
          credential = await _firebaseAuth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException {
          throw 'This Gmail is already registered to another account.';
        }
      } else {
        throw AppHelpers.friendlyError(e);
      }
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
    final user = credential.user!;

    // ---- Provision the profile + publish the login index ----------------
    // The activation record (read earlier, before the account existed)
    // carries the full exam-cell profile data, so nothing here depends on
    // another read and no rules race can occur.
    try {
      final profile = await _studentFromRecord(
        data: activation.data() ?? {},
        uid: user.uid,
        regNo: regNo,
        email: email,
      );
      await _db
          .collection(AppConstants.studentsCollection)
          .doc(user.uid)
          .set(profile, SetOptions(merge: true));

      await _db.collection('loginIndex').doc(regNo).set({
        'registerNumber': regNo,
        'email': email,
        'personalEmail': email,
        'uid': user.uid,
        'activatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      pingAuthRefresh();
    } catch (e) {
      debugPrint('activateAccount failed: $e');
      // Roll back the fresh account AND its login index so a retry starts
      // clean instead of being blocked by the already-activated guard.
      await _rollbackUser(user);
      try {
        await _db.collection('loginIndex').doc(regNo).delete();
      } catch (_) {}
      if (e is FirebaseAuthException || e is FirebaseException) {
        throw AppHelpers.friendlyError(e);
      }
      rethrow;
    }
  }

  /// SHA-256 of the register number + DOB digits — must match the hash the
  /// Admin App's import writes into `activation/{registerNumber}`.
  static String _activationDobHash(String regNo, String dobDigits) =>
      sha256.convert(utf8.encode('AUFEE|$regNo|$dobDigits')).toString();

  /// Builds the `students/{uid}` profile map from the exam-cell record
  /// (students/{registerNumber} placeholder written by the Registration
  /// Preview import — it carries subjects, counts and the total fee).
  Future<Map<String, dynamic>> _studentFromRecord({
    required Map<String, dynamic> data,
    required String uid,
    required String regNo,
    required String email,
  }) async {
    final student = Student(
      uid: uid,
      name: (data['name'] as String?) ?? '',
      registerNumber: (data['registerNumber'] as String?) ?? regNo,
      email: email,
      department: (data['department'] as String?) ?? '',
      year: AppHelpers.parseSemesterOrYear(data['year']),
      semester: AppHelpers.parseSemesterOrYear(data['semester']),
      section: (data['section'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      academicYear: (data['academicYear'] as String?) ??
          AppHelpers.currentAcademicYear(),
      university: (data['university'] as String?) ?? '',
      collegeName: (data['collegeName'] as String?) ?? '',
      collegeCode: (data['collegeCode'] as String?) ?? '',
      degree: (data['degree'] as String?) ?? '',
      branch: (data['branch'] as String?) ?? '',
      regulation: (data['regulation'] as String?) ?? '',
      dateOfBirth: Student.parseDateValue(data['dateOfBirth']),
      subjects: Student.parseLegacySubjects(data['subjects']),
      numberOfSubjects: AppHelpers.parseSemesterOrYear(
        data['numberOfSubjects'] ?? 0,
      ),
      totalFee: (data['totalFee'] as num?)?.toDouble(),
      examFeeSession: (data['examFeeSession'] as String?) ?? '',
      createdAt: DateTime.now(),
    );
    return student.toMap()
      ..['accountStatus'] = 'active'
      ..['authProvisioned'] = true
      ..['accountSource'] = 'activation'
      ..['updatedAt'] = FieldValue.serverTimestamp();
  }

  /// Deletes a just-created Auth account (activation rollback).
  Future<void> _rollbackUser(User user) async {
    try {
      await user.delete();
    } catch (_) {
      // Best effort – the account stays until it signs out; the student
      // can simply retry sign-in.
    }
  }

  /// Sends the Firebase verification mail for a new personal email
  /// address. For an existing register-number account this uses
  /// verify-before-update; for an account that already has the target email,
  /// it sends the standard Firebase verification mail.
  Future<void> sendEmailVerificationTo(String newEmail) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw 'Your session has expired. Please sign in again.';
    }
    final email = newEmail.trim();
    if (email.isEmpty) {
      throw 'Enter a valid email address.';
    }
    try {
      if (user.email?.trim().toLowerCase() == email.toLowerCase()) {
        await user.sendEmailVerification();
      } else {
        await user.verifyBeforeUpdateEmail(email);
      }
    } on FirebaseAuthException catch (e) {
      throw AppHelpers.friendlyError(e);
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
  }

  /// Refreshes the current Firebase user so email verification changes are
  /// reflected immediately in the auth gate.
  Future<User?> reloadCurrentUser() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    await user.reload();
    return _firebaseAuth.currentUser;
  }

  /// Standard email/password sign-in.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AppHelpers.friendlyError(e);
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
  }

  /// Creates the Auth account. The caller must afterwards persist the
  /// student profile document (`students/{uid}`) via [FirestoreService].
  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    try {
      return await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AppHelpers.friendlyError(e);
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AppHelpers.friendlyError(e);
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
  }

  /// Publishes the register number → auth email mapping used by sign-in
  /// and password reset. Owner-guarded: the rules only allow the signed-in
  /// student to publish their own index entry.
  Future<void> publishLoginIndex({
    required String registerNumber,
    required String email,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw 'Your session has expired. Please sign in again.';
    }
    final regNo = registerNumber.trim().toUpperCase();
    if (regNo.isEmpty) return;
    await _db.collection('loginIndex').doc(regNo).set({
      'registerNumber': regNo,
      'email': email.trim().toLowerCase(),
      'uid': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sends a password-reset email to the personal Gmail registered for
  /// [registerNumber] at activation (resolved via the login index).
  Future<void> sendPasswordResetForRegisterNumber(
    String registerNumber,
  ) async {
    final email = await resolveLoginEmail(registerNumber);
    if (email == null) {
      throw 'No activated account was found for this register number.\n'
          'First time? Use "Activate your account" on the sign-in screen.';
    }
    await sendPasswordReset(email);
  }

  /// Changes the signed-in student's password after re-authenticating.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw 'Your session has expired. Please sign in again.';
    }
    final email = user.email;
    if (email == null) {
      throw 'This account has no email address.';
    }
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw 'Your current password is incorrect.';
        case 'weak-password':
          throw 'Please choose a stronger password (min. 6 characters).';
        case 'requires-recent-login':
          throw 'Your session is too old. Please sign in again and retry.';
        case 'network-request-failed':
          throw AppConstants.msgNetworkError;
        default:
          throw AppHelpers.friendlyError(e);
      }
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
  }

  Future<void> signOut() async {
    try {
      // Capture the account's current email into the login index before the
      // session ends: after the verification link is clicked, the auth email
      // is the personal Gmail, and sign-in / password reset must resolve to
      // it even if the in-app self-heal never ran.
      final user = _firebaseAuth.currentUser;
      final email = user?.email?.toLowerCase() ?? '';
      if (user != null &&
          email.isNotEmpty &&
          !email.endsWith(AppConstants.studentEmailDomain)) {
        try {
          final profile = await _db
              .collection(AppConstants.studentsCollection)
              .doc(user.uid)
              .get();
          final regNo =
              (profile.data()?['registerNumber'] as String?)?.toUpperCase();
          if (regNo != null && regNo.isNotEmpty) {
            await publishLoginIndex(registerNumber: regNo, email: email);
          }
        } catch (_) {
          // Best effort — the dashboard self-heal covers it later.
        }
      }
      await _firebaseAuth.signOut();
      pingAuthRefresh();
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
  }
}
