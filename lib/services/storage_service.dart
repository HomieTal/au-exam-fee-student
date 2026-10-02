import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/constants.dart';
import '../utils/helpers.dart';

/// Firebase Storage uploads for payment proof screenshots.
///
/// Storage layout:
///   payments/{studentUid}/{paymentId}.jpg
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads the picked screenshot and returns its download URL.
  ///
  /// Throws a user-friendly message on failure.
  Future<String> uploadPaymentScreenshot({
    required String studentUid,
    required String paymentId,
    required XFile screenshot,
  }) async {
    final file = File(screenshot.path);

    if (!file.existsSync()) {
      throw 'The selected screenshot could not be read. Please pick it again.';
    }
    if (file.lengthSync() > AppConstants.maxScreenshotBytes) {
      throw 'The screenshot is too large. Please choose an image under 5 MB.';
    }

    try {
      final ref = _storage
          .ref()
          .child(AppConstants.screenshotsFolder)
          .child(studentUid)
          .child('$paymentId.jpg');

      final metadata = SettableMetadata(
        contentType: screenshot.mimeType ?? 'image/jpeg',
        customMetadata: {
          'studentUid': studentUid,
          'paymentId': paymentId,
        },
      );

      final task = await ref.putFile(file, metadata);
      return await task.ref.getDownloadURL();
    } catch (e) {
      throw AppHelpers.friendlyError(e);
    }
  }
}
