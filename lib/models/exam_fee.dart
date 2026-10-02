import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/helpers.dart';

/// The currently announced exam fee, read from `settings/examFee`.
/// Maintained by the Admin App. When the document is missing, the app falls
/// back to `Student.examFee` (or shows a "fee not announced" state).
class ExamFee {
  final double amount;
  final String? semester;
  final String? academicYear;
  final DateTime? lastDate;

  const ExamFee({
    required this.amount,
    this.semester,
    this.academicYear,
    this.lastDate,
  });

  factory ExamFee.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ExamFee(
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      semester: data['semester'] as String?,
      academicYear: data['academicYear'] as String?,
      lastDate: data['lastDate'] is Timestamp
          ? (data['lastDate'] as Timestamp).toDate()
          : null,
    );
  }

  /// Builds the fee shown to a student from a document of the `fees`
  /// collection – the same configuration the Admin App maintains
  /// (department + semester + academicYear, isActive).
  factory ExamFee.fromFeeData(Map<String, dynamic> data) {
    final semester = data['semester'];
    return ExamFee(
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      semester: semester == null
          ? null
          : 'Semester ${AppHelpers.intToRoman(
              semester is num ? semester.toInt() : 0,
            )}',
      academicYear: data['academicYear'] as String?,
      lastDate: data['lastDate'] is Timestamp
          ? (data['lastDate'] as Timestamp).toDate()
          : null,
    );
  }

  /// Builds a fallback fee from a per-student override when no fee
  /// configuration matches the student's department/semester yet.
  factory ExamFee.fromStudentOverride(double amount) =>
      ExamFee(amount: amount);
}
