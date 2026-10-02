import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'constants.dart';

class AppHelpers {
  AppHelpers._();

  // ── Formatting ──────────────────────────────────────────────────────────
  static String formatAmount(num amount) {
    final format = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return format.format(amount);
  }

  static String formatDate(DateTime date) =>
      DateFormat('dd MMM yyyy').format(date);

  static String formatDateTime(DateTime date) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(date);

  /// Current academic year, e.g. "2026-2027" (Indian academic year starts
  /// in June).
  static String currentAcademicYear() {
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    return '$startYear-${startYear + 1}';
  }

  /// Converts a roman-numeral semester ("VII") to its integer (7). The
  /// `fees` collection stores the semester as an integer.
  static int romanToInt(String roman) {
    const values = {'I': 1, 'V': 5, 'X': 10, 'L': 50};
    final r = roman.trim().toUpperCase();
    var total = 0;
    var current = 0;
    for (var i = r.length - 1; i >= 0; i--) {
      final v = values[r[i]] ?? 0;
      if (v < current) {
        total -= v;
      } else {
        total += v;
        current = v;
      }
    }
    return total;
  }

  /// Converts an integer semester (1-10) to its roman numeral ("VII").
  static String intToRoman(int number) {
    if (number <= 0) return '–';
    const values = [10, 9, 5, 4, 1];
    const symbols = ['X', 'IX', 'V', 'IV', 'I'];
    var n = number;
    final out = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      while (n >= values[i]) {
        out.write(symbols[i]);
        n -= values[i];
      }
    }
    return out.toString();
  }

  /// Tolerant parser for year/semester fields that may be stored as an int
  /// (Admin App schema) or a roman numeral (older Student App schema).
  static int parseSemesterOrYear(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      final asInt = int.tryParse(trimmed);
      if (asInt != null) return asInt;
      return romanToInt(trimmed);
    }
    return 0;
  }

  /// Normalizes a date of birth entered as DDMMYYYY, DD/MM/YYYY or
  /// DD-MM-YYYY into the canonical `DDMMYYYY` password form. Returns null
  /// when the input cannot be interpreted.
  static String? normalizeDob(String? input) {
    if (input == null) return null;
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 8) {
      final dd = int.tryParse(digits.substring(0, 2));
      final mm = int.tryParse(digits.substring(2, 4));
      final yyyy = int.tryParse(digits.substring(4));
      if (dd != null && mm != null && yyyy != null) {
        if (dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12 && yyyy >= 1900) {
          return digits;
        }
      }
      return null;
    }
    return null;
  }

  // ── Payment status helpers (pending / verified / rejected) ──────────────
  static String statusLabel(String status) {
    switch (status) {
      case AppConstants.statusPending:
        return 'Pending';
      case AppConstants.statusVerified:
        return 'Verified';
      case AppConstants.statusRejected:
        return 'Rejected';
      default:
        return 'Unknown';
    }
  }

  static Color statusColor(String status) {
    switch (status) {
      case AppConstants.statusPending:
        return const Color(0xFFFFC107); // amber
      case AppConstants.statusVerified:
        return const Color(0xFF4CAF50); // green
      case AppConstants.statusRejected:
        return const Color(0xFFF44336); // red
      default:
        return const Color(0xFF757575); // grey
    }
  }

  static IconData statusIcon(String status) {
    switch (status) {
      case AppConstants.statusPending:
        return Icons.hourglass_top_rounded;
      case AppConstants.statusVerified:
        return Icons.verified_rounded;
      case AppConstants.statusRejected:
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  // ── Connectivity ────────────────────────────────────────────────────────
  static Future<bool> hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      // If the plugin fails, assume we are online and let Firebase report
      // the real error.
      return true;
    }
  }

  // ── Friendly Firebase error messages ────────────────────────────────────
  static String friendlyError(Object error) {
    if (error is FirebaseAuthException) return _authMessage(error.code);
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to perform this action.';
        case 'unavailable':
        case 'network-request-failed':
          return AppConstants.msgNetworkError;
        case 'deadline-exceeded':
          return 'The request timed out. Please try again.';
        case 'cancelled':
          return 'The operation was cancelled.';
        case 'object-not-found':
          return 'The requested file was not found.';
        case 'unauthenticated':
          return 'Your session has expired. Please sign in again.';
        default:
          return error.message ?? AppConstants.msgGenericError;
      }
    }
    return AppConstants.msgGenericError;
  }

  static String _authMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled. Contact the exam cell.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Please choose a stronger password (min. 6 characters).';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return AppConstants.msgNetworkError;
      case 'user-token-expired':
      case 'token-expired':
        return 'Your session has expired. Please sign in again.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
