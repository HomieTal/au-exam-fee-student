import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// One-time account activation.
  ///
  /// Identity step: the register number + date of birth establish the
  /// exam-cell identity (`regno@au.edu.in`, DOB as the temporary password) —
  /// the security rules let that identity read the imported placeholder
  /// record, where the DOB is verified for real. Legacy accounts from
  /// earlier app versions (DOB as password) are signed into and migrated in
  /// place; a resumed attempt after a partial activation is recognised by
  /// its chosen password.
  ///
  /// Claim step: the student's own Gmail becomes the auth email and their
  /// own password replaces the DOB; `loginIndex` is published so future
  /// sign-ins resolve register number → Gmail and "Forgot Password" reaches
  /// their real inbox. No verification link is sent — the Gmail is collected
  /// and confirmed by the student during activation itself.
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

    // ---- Establish the register-number identity -------------------------
    // firebase_auth 4.x has a response-decoding bug ("type 'List<Object?>'
    // is not a subtype of type 'PigeonUserDetails?'") that fires AFTER the
    // backend call has succeeded — authUser falls back to the signed-in
    // user in that case.
    Future<User?> authUser(Future<UserCredential> Function() call) async {
      try {
        return (await call()).user;
      } catch (e) {
        if (e.toString().contains('PigeonUserDetails')) {
          final current = _firebaseAuth.currentUser;
          if (current != null &&
              current.email?.toLowerCase() == _legacyEmail(regNo)) {
            debugPrint('auth call hit the Pigeon cast bug; used currentUser');
            return current;
          }
        }
        rethrow;
      }
    }

    User? user;
    var migratedLegacy = false;
    try {
      user = await authUser(() => _firebaseAuth.signInWithEmailAndPassword(
            email: _legacyEmail(regNo),
            password: dob,
          ));
      migratedLegacy = user != null;
    } on FirebaseAuthException catch (e) {
      final retryable = e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'wrong-password';
      if (!retryable) throw AppHelpers.friendlyError(e);
    }
    if (user == null) {
      try {
        user = await authUser(() =>
            _firebaseAuth.createUserWithEmailAndPassword(
              email: _legacyEmail(regNo),
              password: dob,
            ));
      } on FirebaseAuthException catch (e2) {
        // A prior attempt may already have replaced the DOB password —
        // recognise it by the chosen password instead of locking out.
        if (e2.code == 'email-already-in-use') {
          user = await authUser(() =>
              _firebaseAuth.signInWithEmailAndPassword(
                email: _legacyEmail(regNo),
                password: password,
              ));
          if (user == null) {
            throw 'Incorrect date of birth for this register number.';
          }
          migratedLegacy = true;
        } else {
          throw AppHelpers.friendlyError(e2);
        }
      }
    }
    if (user == null) {
      throw 'Activation could not sign you in. Please try again.';
    }

    // ---- Verify the DOB against the exam-cell record --------------------
    final activeUser = user;
    try {
      final data = await _examCellRecord(regNo, migratedLegacy);
      if (data == null) {
        throw 'No exam-cell record was found for register number $regNo.\n'
            'Use Register instead, or contact the exam cell.';
      }
      if (!_recordDobMatches(data, dob)) {
        throw 'Incorrect date of birth for this register number.';
      }

      // ---- Provision / refresh the students/{uid} profile ---------------
      final profile = await _studentFromRecord(
        data: data,
        uid: activeUser.uid,
        regNo: regNo,
        email: email,
      );
      await _db
          .collection(AppConstants.studentsCollection)
          .doc(activeUser.uid)
          .set(profile, SetOptions(merge: true));

      // ---- Publish the login index (owner-guarded by the rules) ---------
      // Published BEFORE the identity switch so sign-in keeps working even
      // if a later step fails and has to be retried.
      Future<void> publishIndex(String loginEmail) =>
          _db.collection('loginIndex').doc(regNo).set({
            'registerNumber': regNo,
            'email': loginEmail,
            'uid': activeUser.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await publishIndex(_legacyEmail(regNo));

      // ---- Claim the account: own password + own Gmail -------------------
      // Firebase blocks silent email changes ("Please verify the new email
      // before changing email"), so the Gmail switch happens through the
      // verification link: loginIndex keeps resolving the register number
      // to the working legacy identity, and self-heals to the Gmail once
      // the student clicks the link (see HomeScreen).
      await activeUser.updatePassword(password);
      await activeUser.verifyBeforeUpdateEmail(email);
      pingAuthRefresh();
    } catch (e) {
      debugPrint('activateAccount failed: $e');
      if (migratedLegacy) {
        // The legacy account cannot be deleted from the client; leave it in
        // a consistent state and end the session for a clean retry.
        try {
          await _firebaseAuth.signOut();
        } catch (_) {}
      } else {
        await _rollbackUser(user);
      }
      if (e is FirebaseAuthException || e is FirebaseException) {
        throw AppHelpers.friendlyError(e);
      }
      rethrow;
    }
  }

  /// Reads the exam-cell record for a register number. The placeholder
  /// document (students/{registerNumber}, written by the import) is the
  /// identity authority and is readable by the register-number identity.
  /// Legacy accounts provisioned under the old flow have their profile
  /// keyed by uid instead — used as a fallback for migrations.
  Future<Map<String, dynamic>?> _examCellRecord(
    String regNo,
    bool migratedLegacy,
  ) async {
    try {
      for (final id in [regNo, regNo.toLowerCase()]) {
        final doc = await _db
            .collection(AppConstants.studentsCollection)
            .doc(id)
            .get();
        if (doc.exists) return doc.data();
      }
      if (migratedLegacy) {
        final doc = await _db
            .collection(AppConstants.studentsCollection)
            .doc(_firebaseAuth.currentUser!.uid)
            .get();
        final data = doc.data();
        if (data == null) return null;
        final recorded = (data['registerNumber'] as String?)?.toUpperCase();
        return recorded == regNo ? data : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Compares an exam-cell record's date of birth (DD-MM-YYYY string or
  /// Firestore timestamp) with the entered DDMMYYYY value.
  bool _recordDobMatches(Map<String, dynamic> data, String dob) {
    final stored = data['dateOfBirthString'];
    if (stored is String &&
        stored.replaceAll(RegExp(r'[^0-9]'), '') == dob) {
      return true;
    }
    final timestamp = data['dateOfBirth'];
    if (timestamp is Timestamp) {
      final utc = timestamp.toDate().toUtc();
      final dd = utc.day.toString().padLeft(2, '0');
      final mm = utc.month.toString().padLeft(2, '0');
      if ('$dd$mm${utc.year}' == dob) return true;
    }
    return false;
  }

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
