import 'package:flutter/material.dart';

import 'theme.dart';

/// Top-floating, branded notifications used across the app.
///
/// Snackbars slide in near the top of the screen (below the status bar) and
/// are themed: maroon for neutral, red for errors, green for success.
class AppNotifications {
  AppNotifications._();

  static void show(
    BuildContext context,
    String message, {
    bool error = false,
    bool success = false,
  }) {
    final height = MediaQuery.of(context).size.height;
    final color = error
        ? AppTheme.errorColor
        : success
            ? AppTheme.successColor
            : AppTheme.primaryColor;
    final icon = error
        ? Icons.error_outline_rounded
        : success
            ? Icons.check_circle_outline_rounded
            : Icons.info_outline_rounded;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          elevation: 6,
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          // Push the floating snackbar to the top of the screen.
          margin: EdgeInsets.fromLTRB(16, 0, 16, height - 150),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
