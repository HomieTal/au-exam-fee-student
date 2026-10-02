/// App-wide constants for the AU Exam Fee student app.
///
/// Collection and status names must stay in sync with the AU Exam Fee
/// Admin App – both apps read/write the same Firestore project.
class AppConstants {
  AppConstants._();

  // ── App info ────────────────────────────────────────────────────────────
  static const String appName = 'AU Exam Fee';
  static const String appTagline = 'Anna University – Exam Fee Portal';
  static const String appVersion = '1.0.0';
  static const String developerName = 'CrackDevelopers';
  static const String developerEmail = 'crackdevelopersdot@gmail.com';

  // ── Auto-provisioned student accounts ───────────────────────────────────
  // Students sign in with their register number + date of birth; the auth
  // account is created on first sign-in with the register number mapped to
  // this domain. Their personal email is collected (and verified) after
  // the first login.
  static const String studentEmailDomain = '@au.edu.in';

  // ── In-app updates (GitHub releases) ────────────────────────────────────
  // Set to your GitHub "owner/repo". The app checks the latest release and
  // prompts the student when its tag is newer than appVersion.
  static const String githubRepo = 'HomieTal/au-exam-fee-student';
  static const bool updateCheckEnabled = true;

  // ── Payment statuses (shared with the Admin App) ────────────────────────
  static const String statusPending = 'pending';
  static const String statusVerified = 'verified';
  static const String statusRejected = 'rejected';

  // ── Payment methods ─────────────────────────────────────────────────────
  static const List<String> paymentMethods = ['UPI', 'Net Banking', 'Other'];

  // ── Firestore collections / documents ───────────────────────────────────
  static const String studentsCollection = 'students';
  static const String paymentsCollection = 'payments';
  static const String settingsCollection = 'settings';
  static const String examFeeSettingsDoc = 'examFee';
  static const String paymentSettingsDoc = 'payment';
  static const String adminsCollection = 'admins';

  // ── Firebase Storage ────────────────────────────────────────────────────
  static const String screenshotsFolder = 'payments';

  /// Max allowed payment screenshot size (5 MB).
  static const int maxScreenshotBytes = 5 * 1024 * 1024;

  // ── Student form choices ────────────────────────────────────────────────
  static const List<String> yearOptions = ['I', 'II', 'III', 'IV'];
  static const List<String> semesterOptions = [
    'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII',
  ];
  static const List<String> sectionOptions = [
    'A', 'B', 'C', 'D', 'E',
  ];

  // ── User-facing messages ────────────────────────────────────────────────
  static const String msgPending =
      'Payment submitted. Waiting for admin verification.';
  static const String msgVerified = 'Payment verified successfully.';
  static const String msgRejected =
      'Payment was rejected. Please check the reason and submit again.';
  static const String msgNotSubmitted = 'Not Submitted';
  static const String msgNetworkError =
      'No internet connection. Please check your network and try again.';
  static const String msgGenericError =
      'Something went wrong. Please try again.';
  static const String msgFeeNotAnnounced =
      'The exam fee has not been announced yet. Please check back later.';
}
