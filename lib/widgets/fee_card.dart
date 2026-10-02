import 'package:flutter/material.dart';

import '../models/exam_fee.dart';
import '../models/student.dart';
import '../utils/helpers.dart';

/// Primary card showing the announced exam fee amount with key context.
/// Used on the dashboard (compact) and the Exam Fee screen (detailed).
class FeeCard extends StatelessWidget {
  final ExamFee? examFee;
  final Student? student;
  final bool detailed;

  const FeeCard({
    super.key,
    required this.examFee,
    this.student,
    this.detailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = student;
    final hasFee = examFee != null && examFee!.amount > 0;
    final semester = examFee?.semester ??
        (s != null && s.semester > 0 ? s.semesterLabel : '');
    final academicYear = examFee?.academicYear ?? s?.academicYear ?? '';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payments_rounded,
                      color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Exam Fee',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (hasFee) ...[
              Text(
                AppHelpers.formatAmount(examFee!.amount),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (semester.isNotEmpty || academicYear.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (semester.isNotEmpty) 'Semester $semester',
                    if (academicYear.isNotEmpty) academicYear,
                  ].join('  •  '),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (examFee!.lastDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.event_rounded,
                        size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 6),
                    Text(
                      'Last date: ${AppHelpers.formatDate(examFee!.lastDate!)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (detailed) ...[
                const Divider(height: 24),
                _detailRow(theme, 'Semester',
                    semester.isNotEmpty ? semester : '–'),
                _detailRow(theme, 'Department',
                    (student?.department.isNotEmpty ?? false)
                        ? student!.department
                        : '–'),
                _detailRow(
                    theme, 'Academic Year',
                    academicYear.isNotEmpty ? academicYear : '–'),
              ],            ] else
              Text(
                'Fee details will appear here once the exam cell announces them.',
                style: theme.textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
