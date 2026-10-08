# AU Exam Fee – Student App

A Flutter (Android) app that lets **Anna University** students view their
semester exam fee, submit payment details with proof of payment, and track
verification status — integrated with the existing **AU Exam Fee Admin App**
through the same Firebase project (`au-fee`).

| | |
|---|---|
| Package name | `com.annauniv.auexamfee` |
| Firebase project | `au-fee` |
| Services | Firebase Authentication, Cloud Firestore, on-device OCR |
| Status flow | `pending` → `verified` \| `rejected` (set by the Admin App) |

---

## 1. Project structure

```text
lib/
├── main.dart                     # Firebase init + AuthGate + MaterialApp
├── firebase_options.dart         # FlutterFire options (already configured)
├── models/
│   ├── student.dart              # students/{uid} profile model
│   ├── payment.dart              # payments/{paymentId} model
│   ├── exam_fee.dart             # settings/examFee model
│   └── payment_settings.dart     # settings/payment (UPI details) model
├── services/
│   ├── auth_service.dart         # Firebase Auth (sign-in/register/reset/logout)
│   ├── firestore_service.dart    # profile + payments + settings access
│   └── receipt_ocr_service.dart  # local receipt extraction/validation
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart     # email/password sign-in
│   │   ├── register_screen.dart  # student self-registration
│   │   └── forgot_password_screen.dart
│   ├── home/
│   │   └── home_screen.dart      # bottom-nav shell + dashboard
│   ├── exam_fee/
│   │   ├── exam_fee_screen.dart  # fee details + status + UPI QR
│   │   └── payment_submission_screen.dart
│   ├── history/
│   │   └── payment_history_screen.dart  # list + full details
│   └── profile/
│       └── profile_screen.dart   # read-only profile + logout
├── widgets/
│   ├── fee_card.dart
│   ├── payment_status_card.dart
│   └── loading_widget.dart       # loading / empty / error / status chip
└── utils/
    ├── constants.dart
    ├── validators.dart
    ├── helpers.dart              # formatting, status colors, error mapping
    └── theme.dart                # Material 3, Poppins
```

`firestore.rules` and `storage.rules` live in the project root.

---

## 2. Install dependencies & run

```bash
flutter clean                 # required once after the package-name change
flutter pub get
flutter run                   # run on a connected device/emulator
```

---

## 3. Firebase configuration (already applied)

The repo already contains `android/app/google-services.json` and
`lib/firebase_options.dart` for the project **au-fee**. If you ever need to
reconfigure:

1. Install the FlutterFire CLI and Firebase CLI, then log in:
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   ```
2. Regenerate configuration:
   ```bash
   flutterfire configure \
     --project=au-fee \
     --android-package-name=com.annauniv.auexamfee \
     --platforms=android
   ```
   This rewrites `lib/firebase_options.dart` and `google-services.json`.

### 3.1 Enable Authentication

Firebase Console → **Authentication → Sign-in method** → enable
**Email/Password**. (No other provider is required.)

Students sign in with **register number + date of birth (DDMMYYYY)**. On the
first sign-in the account is provisioned automatically from the exam-cell
record (`students/{registerNumber}`, created by the Admin App's extraction
flow): the auth account uses `<regno>@au.edu.in` with the DOB as the initial
password, and the `students/{uid}` profile is created from the record. A
personal email is then collected on the dashboard and verified through a
Firebase verification mail (verify-before-update, so the register-number
login keeps working until the link is clicked).

### 3.2 Enable Firestore

Firebase Console → **Firestore Database** → *Create database* (production
mode), then publish the contents of **`firestore.rules`** from this repo
(Console → Firestore → Rules, or `firebase deploy --only firestore:rules`).

### 3.3 Storage

New payment submissions use on-device OCR and do not require Firebase Storage
or a billing account. The existing `storage.rules` file is retained only for
old payment records whose `screenshotUrl` points to a legacy Firebase Storage
image.

### 3.4 Admin users (needed for verification to work)

For each admin of the **Admin App**:

1. Console → Authentication → copy the admin user's **UID**.
2. Console → Firestore → create collection **`admins`** → add a document
   whose **document ID is that UID** (any field, e.g. `role: "admin"`).

Both rules files check this collection; it can only be managed from the
Console (`allow write: if false`).

---

## 4. Firestore data model

```text
students/{uid}                          # uid == Firebase Auth UID
├── uid            : string
├── name           : string
├── registerNumber : string
├── email          : string
├── department     : string           # CSE, ECE, …
├── year           : string           # I … IV
├── semester       : string           # I … VIII
├── section        : string           # A … E
├── phone          : string
├── academicYear   : string           # e.g. 2026-2027
├── examFee        : number (optional – per-student fallback fee)
└── createdAt      : timestamp

payments/{paymentId}
├── studentUid      : string          # == Auth UID of the payer
├── registerNumber  : string
├── studentName     : string          # convenience for admin lists
├── semester        : string
├── amount          : number
├── transactionId   : string          # UTR / reference number
├── paymentDate     : timestamp       # date the student paid
├── paymentMethod   : string          # UPI | Net Banking | Other
├── screenshotUrl   : string          # Storage download URL
├── status          : string          # pending | verified | rejected
├── rejectionReason : string | null   # admin-entered reason
├── submittedAt     : timestamp
└── verifiedAt      : timestamp | null

settings/examFee                        # announced fee (admin managed)
├── amount       : number
├── semester     : string (optional override)
├── academicYear : string (optional override)
└── lastDate     : timestamp (optional)

settings/payment                        # UPI collect details (admin managed)
├── enabled   : boolean
├── upiId     : string
├── payeeName : string
└── qrImageUrl: string
```

No composite indexes are required — queries filter on `studentUid` only and
sort client-side. Passwords are never stored in Firestore; Firebase Auth
manages credentials.

## 5. Receipt verification

```text
Student selects receipt screenshot
  → on-device OCR extracts receipt text
  → entered transaction ID must appear in the OCR text
  → entered fee amount must appear in the OCR text
  → verified fields + receiptText are saved to Firestore
```

New submissions do not upload or store the screenshot, so Firebase Storage is
not required for payment submission. The screenshot remains on the device only
while OCR runs. Existing payments containing `screenshotUrl` remain
backward-compatible and continue to display their old Firebase Storage image.

Transaction duplicate detection checks only the signed-in student's own
payments and normalizes letter case, spaces, and separators before comparing.
Different students may use the same identifier in their separate records.

New payment documents include `receiptText`, `verificationMethod: "local_ocr"`,
and `status: "pending"`. OCR is a convenience check; the Admin App still
approves or rejects every submission.

---

## 6. Security model (firestore.rules / storage.rules)

- Students can read **only** their own `students/{uid}` and payments
  (`studentUid == request.auth.uid`).
- Students can **create** their own profile (registration) and their own
  payment submission — but only with `status == 'pending'`.
- Students can **never** update/delete a payment → they cannot mark a payment
  verified, change verification results, or tamper with proof.
- Students can **never** update their profile — academic data is corrected by
  the exam cell.
- Only users with a document in `admins/{uid}` (Admin App exam cell) may read
  all payments/profiles and verify/reject.
- Students cannot modify another student's information — all own-data rules
  bind on `request.auth.uid`.

## 7. How student ↔ admin integration works

1. Student submits payment → `payments/{id}` created with `status: pending`
   and the OCR receipt text.
2. Admin App lists pending payments, views the transaction ID + receipt text,
   then **verifies** (sets `status: verified`, `verifiedAt`) or **rejects**
   (sets `status: rejected`, `rejectionReason`).
3. The student app listens with real-time streams (`snapshots()`), so the
   dashboard, Exam Fee and History tabs update **automatically** — no refresh
   needed. Rejected payments show the admin's reason and unlock resubmission.

### In-app updates (GitHub releases)

On every start the app checks
`https://api.github.com/repos/<owner>/<repo>/releases/latest` (see
`githubRepo` in `lib/utils/constants.dart`). When the latest release tag is
newer than `appVersion`, an update dialog shows the release notes and opens
the release APK/page. Publish updates by tagging a release (e.g. `v1.0.1`)
with an APK asset attached.

### Developer contact

`crackdevelopersdot@gmail.com` — shown on the login and profile screens
(tappable, opens the mail client).

### In-app updates (GitHub releases)

On every start the app checks
`https://api.github.com/repos/<owner>/<repo>/releases/latest` (see
`githubRepo` in `lib/utils/constants.dart`). When the latest release tag is
newer than `appVersion`, an update dialog shows the release notes and opens
the release APK/page. Publish updates by tagging a release (e.g. `v1.0.1`)
with an APK asset attached.

### Developer contact

`crackdevelopersdot@gmail.com` — shown on the login and profile screens
(tappable, opens the mail client).

### Notifications (FCM-ready)

Status changes already stream live into the UI. To add push notifications
later: add `firebase_messaging` to `pubspec.yaml`, request the token after
sign-in, store it in `students/{uid}.fcmToken` (relax the profile `update`
rule accordingly), and have the Admin App trigger Cloud Functions on
verify/reject/new-fee. The architecture (service layer + streams) requires no
refactoring for this.

---

## 8. Android configuration

- **Package name**: `com.annauniv.auexamfee` (set in
  `android/app/build.gradle.kts` `namespace` + `applicationId`, matching the
  registered Firebase Android app).
- **MainActivity**: `android/app/src/main/kotlin/com/annauniv/auexamfee/MainActivity.kt`.
- **Permissions**: `INTERNET` + `ACCESS_NETWORK_STATE` are declared in
  `android/app/src/main/AndroidManifest.xml`. `image_picker` needs no storage
  permission on Android 11+ (Photo Picker); older devices handle it via the
  plugin.
- **App icon**: configured via `flutter_launcher_icons`
  (`assets/images/anna_university_logo.png`); regenerate with
  `dart run flutter_launcher_icons`.

## 9. Build commands

```bash
# Debug APK
flutter build apk --debug

# Release APK (single fat APK)
flutter build apk --release

# Release APKs split per ABI (smaller downloads)
flutter build apk --release --split-per-abi

# App Bundle for Play Store
flutter build appbundle --release
```

For direct Android downloads, publish the ABI-split APK matching the device:
`app-arm64-v8a-release.apk` for most modern phones, `app-armeabi-v7a-release.apk`
for older 32-bit ARM phones, and `app-x86_64-release.apk` for x86_64 devices.
Do not distribute the debug APK; it is much larger and is not optimized for
release.

Release APKs are signed with the debug keystore by default. For distribution,
add a signing config in `android/app/build.gradle.kts` → `buildTypes.release`
(`signingConfigs` with your keystore), then rebuild.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Platform exception / wrong Firebase app on first run | `flutter clean && flutter pub get` after the package-name change |
| Student signs in but sees "Profile not found" | The Auth user has no `students/{uid}` doc — admin must add it, or the student registers in-app |
| `permission-denied` on submit | Rules not deployed, or the signed-in user is writing outside their own `studentUid` |
| Screenshot upload fails | Storage not enabled or `storage.rules` not published; check the 5 MB / image-only limits |
| Status never updates | Ensure the Admin App writes `status`/`rejectionReason` on the same `payments` documents |
