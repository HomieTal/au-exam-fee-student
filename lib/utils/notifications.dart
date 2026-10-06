import 'package:flutter/material.dart';

import 'app_toast.dart';

/// Top-floating, branded notifications used across the app.
///
/// Delegates to [AppToast], whose overlay entries render above the keyboard
/// — error toasts shown while typing stay visible instead of being pushed
/// off-screen by the input view.
class AppNotifications {
  AppNotifications._();

  static void show(
    BuildContext context,
    String message, {
    bool error = false,
    bool success = false,
  }) {
    AppToast.show(context, message, error: error, success: success);
  }
}
