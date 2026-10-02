import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/helpers.dart';

/// A student profile stored at `students/{uid}`, where `{uid}` is the
/// Firebase Auth UID. Academic fields are managed by the exam cell (Admin
/// App) and are read-only inside this app.
///
/// `year` and `semester` are stored as integers (1-4 / 1-8) so both the
/// Student App and the Admin App read the same shape; older documents with
/// roman numerals are parsed tolerantly.
class Student {
  final String uid;
  final String name;
  final String registerNumber;
  final String email;
  final String department;
  final int year;
  final int semester;
  final String section;
  final String phone;
  final String academicYear;

  /// Optional per-student fee override maintained by the admin. When no
  /// `fees` configuration matches, the dashboard falls back to this.
  final double? examFee;

  final DateTime createdAt;

  Student({
    required this.uid,
    required this.name,
    required this.registerNumber,
    required this.email,
    required this.department,
    required this.year,
    required this.semester,
    required this.section,
    required this.phone,
    required this.academicYear,
    this.examFee,
    required this.createdAt,
  });

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Student(
      uid: data['uid'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      registerNumber: data['registerNumber'] as String? ?? '',
      email: data['email'] as String? ?? '',
      department: data['department'] as String? ?? '',
      year: AppHelpers.parseSemesterOrYear(data['year']),
      semester: AppHelpers.parseSemesterOrYear(data['semester']),
      section: data['section'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      academicYear: data['academicYear'] as String? ?? '',
      examFee: data['examFee'] == null
          ? null
          : (data['examFee'] as num).toDouble(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'registerNumber': registerNumber,
      'email': email,
      'department': department,
      'year': year,
      'semester': semester,
      'section': section,
      'phone': phone,
      'academicYear': academicYear,
      if (examFee != null) 'examFee': examFee,
      'createdAt': createdAt,
    };
  }

  /// Roman-numeral display form ("VII"); "–" when unknown.
  String get semesterLabel => AppHelpers.intToRoman(semester);

  String get yearLabel => AppHelpers.intToRoman(year);

  /// True when the Auth account still uses the auto-provisioned
  /// register-number email instead of a personal, verified one.
  bool get needsEmailVerification =>
      email.isEmpty || email.toLowerCase().endsWith('@au.edu.in');

  /// Initials used for the profile avatar.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'))..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
