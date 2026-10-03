import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/student.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

/// Firebase Authentication wrapper – register-number/DOB sign-in with
/// automatic account provisioning, email/password sign-in, password reset
/// and logout. No credentials are ever written to Firestore.
class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  /// Signs in with register number + date of birth.
  ///
  /// On the student's first sign-in the Auth account does not exist yet –
  /// it is then created automatically (register number mapped to
  /// [AppConstants.studentEmailDomain], password = DOB in DDMMYYYY form)
  /// and the `students/{uid}` profile is provisioned from the legacy
  /// exam-cell record (`students/{registerNumber}`, created by the Admin
  /// App's document-extraction flow).
  Future<UserCredential> signInWithRegisterNumber({
    required String registerNumber,
    required String dateOfBirth,
  }) async {
    final regNo = registerNumber.trim();
    final dob = AppHelpers.normalizeDob(dateOfBirth);
    if (dob == null) {
      throw 'Enter your date of birth as DDMMYYYY (e.g. 05082005).';
    }
    final email = '${regNo.toLowerCase()}${AppConstants.studentEmailDomain}';

    // 1. Existing account → straight sign-in.
    // NOTE: with email-enumeration protection enabled, signing into a
    // NON-EXISTENT account also throws invalid-credential (not just
    // user-not-found) — so never report "wrong password" here; fall
    // through to auto-provisioning and let signUp disambiguate.
    try {
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: dob,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' &&
          e.code != 'invalid-credential' &&
          e.code != 'wrong-password') {
        throw AppHelpers.friendlyError(e);
      }
      // Fall through to auto-provisioning.
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }

    // 2. Create the Auth account FIRST – the legacy record is protected by
    //    rules and can only be read by the signed-in student whose
    //    register-number email matches it.
    UserCredential credential;
    try {
      credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: dob,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // The account already exists → the DOB simply didn't match.
        throw 'Incorrect date of birth. Your initial password is your '
            'date of birth (DDMMYYYY). If you changed it, use Forgot '
            'Password or contact the exam cell.';
      }
      throw AppHelpers.friendlyError(e);
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }

    // 3. Read the exam-cell record (allowed now that we're signed in) and
    //    provision the students/{uid} profile from it.
    try {
      final legacy = await _findLegacyRecord(regNo);
      if (legacy == null) {
        await _rollbackUser(credential.user!);
        throw 'No exam-cell record was found for register number $regNo. '
            'Please contact the exam cell, or use Register to create your '
            'account.';
      }
      final data = legacy.data() ?? {};

      final student = Student(
        uid: credential.user!.uid,
        name: (data['name'] as String?) ?? '',
        registerNumber:
            (data['registerNumber'] as String?) ?? regNo.toUpperCase(),
        email: email,
        department: (data['department'] as String?) ?? '',
        year: AppHelpers.parseSemesterOrYear(data['year']),
        semester: AppHelpers.parseSemesterOrYear(data['semester']),
        section: (data['section'] as String?) ?? '',
        phone: (data['phone'] as String?) ?? '',
        academicYear: AppHelpers.currentAcademicYear(),
        createdAt: DateTime.now(),
      );
      await _db
          .collection(AppConstants.studentsCollection)
          .doc(credential.user!.uid)
          .set(student.toMap());

      return credential;
    } catch (e) {
      // Provisioning failed – roll the fresh account back so the student
      // gets a clean retry.
      await _rollbackUser(credential.user!);
      if (e is FirebaseAuthException || e is FirebaseException) {
        throw AppHelpers.friendlyError(e);
      }
      rethrow;
    }
  }

  /// Deletes a just-created Auth account (provisioning rollback).
  Future<void> _rollbackUser(User user) async {
    try {
      await user.delete();
    } catch (_) {
      // Best effort – the account stays until it signs out; the student
      // can simply retry sign-in.
    }
  }

  /// Looks up the legacy exam-cell record for a register number. Allowed
  /// by the security rules only for the signed-in student whose
  /// register-number email matches the record.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _findLegacyRecord(
      String regNo) async {
    final candidates = [
      regNo,
      regNo.toUpperCase(),
      regNo.toLowerCase(),
    ];
    for (final id in candidates) {
      final doc = await _db
          .collection(AppConstants.studentsCollection)
          .doc(id)
          .get();
      if (doc.exists && !(doc.data() ?? {}).containsKey('uid')) {
        return doc;
      }
    }
    final query = await _db
        .collection(AppConstants.studentsCollection)
        .where('registerNumber', isEqualTo: regNo.toUpperCase())
        .limit(1)
        .get();
    if (query.docs.isNotEmpty && !query.docs.first.data().containsKey('uid')) {
      return query.docs.first;
    }
    return null;
  }

  /// Sends the Firebase verification mail for a new personal email
  /// address. The auth email only becomes active once the student clicks
  /// the link in the mail (verify-before-update), so the register-number
  /// login keeps working until then.
  Future<void> sendEmailVerificationTo(String newEmail) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw 'Your session has expired. Please sign in again.';
    }
    try {
      await user.verifyBeforeUpdateEmail(newEmail.trim());
    } on FirebaseAuthException catch (e) {
      throw AppHelpers.friendlyError(e);
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
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
      await _firebaseAuth.signOut();
    } catch (_) {
      throw AppConstants.msgGenericError;
    }
  }
}
