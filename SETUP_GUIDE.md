# AU Fee Student - Setup & Deployment Guide

## Quick Start

### 1. Firebase Project Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select or create project: **au-fee**
3. Enable services:
   - Authentication (Email/Password)
   - Firestore Database (Production Mode)
   - Storage

### 2. Firebase Configuration

#### Android Configuration
1. In Firebase Console → Project Settings → Android
2. Add your app package name: `com.crackdevelopers.au_fee`
3. Download `google-services.json`
4. Place in: `android/app/google-services.json`

#### Update Firebase Options
Edit `lib/firebase_options.dart` with your Firebase credentials:
- API Key
- App ID
- Messaging Sender ID
- Project ID
- Database URL
- Storage Bucket

### 3. Firestore Database Setup

#### Create Collections
```
✓ students
✓ payments
✓ settings
```

#### Create `settings/payment` Document
```javascript
{
  "enabled": true,
  "upiId": "examfee@aubank",
  "payeeName": "Anna University Exam Cell",
  "qrImageUrl": "https://storage.googleapis.com/..." // Firebase Storage URL
}
```

#### Create Sample Student Document
Path: `students/{registerNumber}`
```javascript
{
  "registerNumber": "AU2024001",
  "name": "John Doe",
  "dateOfBirth": Timestamp.now(),
  "dobYear": "2000",
  "university": "Anna University",
  "collegeName": "Engineering College",
  "collegeCode": "EC001",
  "degree": "B.Tech",
  "branch": "Computer Science",
  "department": "CSE",
  "regulation": "2021",
  "year": "2024",
  "semester": "7",
  "subjects": [
    {
      "code": "CS701",
      "title": "Advanced Algorithms",
      "semester": "7"
    }
  ],
  "numberOfSubjects": 1,
  "totalFee": 5000,
  "currency": "INR",
  "paymentStatus": "pending",
  "paymentId": null,
  "sourceDocumentName": "FeeStructure2024",
  "createdAt": Timestamp.now(),
  "updatedAt": Timestamp.now()
}
```

### 4. Firebase Security Rules

Configure Firestore security rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Students can read their own data
    match /students/{registerNumber} {
      allow read: if request.auth != null;
      allow write: if false; // Admin only
      
      // Allow create payment
      match /payments/{paymentId} {
        allow read, write: if request.auth != null;
      }
    }
    
    // Payments
    match /payments/{paymentId} {
      allow create: if request.auth != null;
      allow read: if request.resource.data.registerNumber == extractRegisterNumber();
      allow update, delete: if false; // Admin only
    }
    
    // Settings
    match /settings/{document=**} {
      allow read: if true; // Public read
      allow write: if false; // Admin only
    }
  }
  
  // Helper functions
  function extractRegisterNumber() {
    return request.auth.token.email.split('@')[0];
  }
}
```

### 5. Flutter Configuration

#### Update pubspec.yaml
Already configured with all dependencies. Run:
```bash
flutter pub get
```

#### Update Firebase Options
Edit `lib/firebase_options.dart` with your project credentials from Firebase Console.

### 6. Build & Deploy

#### Android
```bash
# Debug
flutter build apk --debug

# Release
flutter build apk --release
# Outputs: build/app/outputs/flutter-apk/app-release.apk
```

#### Windows (Development)
```bash
flutter build windows --debug
# Note: May require additional Firebase SDK setup
```

## Testing

### Credentials for Testing
1. Create test user in Firebase Console → Authentication
   - Email: `AU2024001@au.edu.in`
   - Password: `Test@123456`

2. Create matching student record in Firestore:
   - Collection: `students`
   - Document ID: `AU2024001`
   - (Use sample data above)

### Test Flow
1. Splash screen loads (2 sec auto-redirect)
2. Login with: `AU2024001` / `Test@123456`
3. Dashboard shows student info
4. Click "Pay Fee" to test payment flow
5. QR code displays (for testing)
6. Submit transaction ID (test: `TXN000001`)
7. Payment submitted for verification

## Production Deployment

### Before Release
- [ ] Update `firebase_options.dart` with production keys
- [ ] Test on real Android device
- [ ] Update app version in `pubspec.yaml`
- [ ] Update Anna University logo
- [ ] Test all payment flows
- [ ] Configure Firebase backups

### Release Process

1. **Create Release APK**
   ```bash
   flutter build apk --release
   ```

2. **Create App Bundle** (for Play Store)
   ```bash
   flutter build appbundle --release
   ```

3. **Sign APK** (if needed)
   - Already configured in Android build.gradle

4. **Upload to Play Store**
   - Google Play Console → Create Release
   - Upload signed APK/AAB

### Post-Deployment
- Monitor Firebase console for errors
- Check Firestore data integrity
- Monitor payment submissions
- Setup admin verification workflow

## Admin Panel Setup

For payment verification, create a separate Admin Dashboard app or web interface with:
- List of pending payments
- Approve/Reject functionality
- Update `payments/{paymentId}.status = "paid"`
- Update `students/{registerNumber}.paymentStatus = "paid"`

## Troubleshooting

### Firebase Connection Issues
- Verify `google-services.json` is in correct location
- Check Firebase project ID in `firebase_options.dart`
- Ensure Firestore database is enabled
- Check security rules allow read operations

### Login Issues
- Verify email format: `{registerNumber}@au.edu.in`
- Ensure student document exists in Firestore
- Check password reset email configuration

### Payment Submission Fails
- Verify `settings/payment` document exists
- Check payment collection has write permissions
- Ensure student document can be updated

### QR Code Not Displaying
- Verify `qrImageUrl` in `settings/payment`
- Ensure Firebase Storage bucket is accessible
- Check image URL format

## Support Contacts

- **Technical Support**: support@crackdevelopers.com
- **Anna University**: examcell@au.edu.in
- **Firebase Support**: [Firebase Docs](https://firebase.google.com/docs)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-08-30 | Initial release |

## License

© 2026 CrackDevelopers. All rights reserved.
