/// Form validation helpers. Every validator returns null when the input is
/// valid, or a user-friendly error message otherwise.
class Validators {
  Validators._();

  static const String _emailPattern =
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
  static const String _transactionPattern = r'^[A-Za-z0-9\-]{6,40}$';
  static const String _registerPattern = r'^[A-Za-z0-9]{6,20}$';

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!RegExp(_emailPattern).hasMatch(v)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? confirmPassword(String? value, String? original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 3) return 'Enter your full name';
    return null;
  }

  static String? registerNumber(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Register number is required';
    if (!RegExp(_registerPattern).hasMatch(v)) {
      return 'Enter a valid register number (6–20 letters/digits)';
    }
    return null;
  }

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    final digits = v.replaceAll(RegExp(r'[\s\-+]'), '');
    if (digits.length != 10 || int.tryParse(digits) == null) {
      return 'Enter a valid 10-digit phone number';
    }
    return null;
  }

  /// Transaction ID / UTR number: 6–40 letters, digits or dashes.
  static String? transactionId(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Transaction ID / UTR number is required';
    if (!RegExp(_transactionPattern).hasMatch(v)) {
      return 'Enter a valid transaction ID (6–40 letters/digits)';
    }
    return null;
  }
}
