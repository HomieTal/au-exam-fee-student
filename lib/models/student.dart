import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/helpers.dart';

/// A student profile stored at `students/{uid}`, where `{uid}` is the
/// Firebase Auth UID. Academic fields are managed by the exam cell (Admin
/// App) and are read-only inside this app.
///
/// `year` and `semester` are stored as integers (1-4 / 1-8) so both the
/// Student App and the Admin App read the same shape; older documents with
/// roman numerals are parsed tolerantly.
///
/// The registration-preview fields (college, degree, branch, regulation,
/// DOB, subjects, totals) are copied from the exam-cell legacy record
/// (`students/{registerNumber}`) during auto-provisioning, and can also be
/// populated once by the student from that record — they power the
/// Registration Preview form shown before payment.
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
  final String university;
  final String collegeName;
  final String collegeCode;
  final String degree;
  final String branch;
  final String regulation;
  final DateTime? dateOfBirth;

  /// Registration-preview subject rows: {sem, code, title}. Tolerates the
  /// Admin App's list of subject-code strings and richer maps.
  final List<Map<String, dynamic>> subjects;
  final int numberOfSubjects;
  final double? totalFee;

  /// Optional per-student fee override maintained by the admin. When no
  /// `fees` configuration matches, the dashboard falls back to this.
  final double? examFee;

  /// Exam session label from the Registration Preview import (e.g.
  /// "Nov. / Dec. Examination, 2026"), shown on the payment form.
  final String examFeeSession;

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
    this.university = '',
    this.collegeName = '',
    this.collegeCode = '',
    this.degree = '',
    this.branch = '',
    this.regulation = '',
    this.dateOfBirth,
    this.subjects = const [],
    this.numberOfSubjects = 0,
    this.totalFee,
    this.examFee,
    this.examFeeSession = '',
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
      university: data['university'] as String? ?? '',
      collegeName: data['collegeName'] as String? ?? '',
      collegeCode: data['collegeCode'] as String? ?? '',
      degree: data['degree'] as String? ?? '',
      branch: data['branch'] as String? ?? '',
      regulation: data['regulation'] as String? ?? '',
      dateOfBirth: _parseDate(data['dateOfBirth']),
      subjects: _parseSubjects(data['subjects']),
      numberOfSubjects: AppHelpers.parseSemesterOrYear(data['numberOfSubjects']),
      totalFee: data['totalFee'] == null
          ? null
          : (data['totalFee'] as num).toDouble(),
      examFee: data['examFee'] == null
          ? null
          : (data['examFee'] as num).toDouble(),
      examFeeSession: data['examFeeSession'] as String? ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      final parts = value.trim().split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[2]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[0]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Tolerates the Admin App's list of subject-code strings and richer maps.
  static List<Map<String, dynamic>> _parseSubjects(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        out.add({
          'sem': item['sem'] ?? item['semester'] ?? item['semNo'] ?? '',
          'code': item['code'] ??
              item['subjectCode'] ??
              item['subject_code'] ??
              '',
          'title': item['title'] ??
              item['subjectTitle'] ??
              item['subjectName'] ??
              item['name'] ??
              '',
        });
      } else if (item is String && item.trim().isNotEmpty) {
        out.add({'sem': '', 'code': item.trim(), 'title': ''});
      }
    }
    return out;
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
      'university': university,
      'collegeName': collegeName,
      'collegeCode': collegeCode,
      'degree': degree,
      'branch': branch,
      'regulation': regulation,
      if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
      if (subjects.isNotEmpty)
        'subjects': subjects.map((s) => s).toList(),
      if (numberOfSubjects > 0) 'numberOfSubjects': numberOfSubjects,
      if (totalFee != null) 'totalFee': totalFee,
      if (examFee != null) 'examFee': examFee,
      if (examFeeSession.isNotEmpty) 'examFeeSession': examFeeSession,
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

  /// True when the registration-preview fields are not populated yet.
  bool get needsPreviewPopulation => subjects.isEmpty;

  /// Public wrappers used by the provisioning flow.
  static DateTime? parseDateValue(dynamic value) => _parseDate(value);
  static List<Map<String, dynamic>> parseLegacySubjects(dynamic raw) =>
      _parseSubjects(raw);

  /// Initials used for the profile avatar.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'))..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
