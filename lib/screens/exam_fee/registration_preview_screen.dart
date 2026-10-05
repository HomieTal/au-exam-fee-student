import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/student.dart';
import '../../services/firestore_service.dart';
import '../../utils/helpers.dart';
import '../../utils/theme.dart';
import 'payment_submission_screen.dart';

/// Renders the Anna University "REGISTRATION PREVIEW" form (the same layout
/// as the exam cell's PDF) for the signed-in student, and leads into the
/// payment submission.
///
/// Data sources, merged in order of authority:
///   1. `students/{uid}` – the student's own profile: subjects, subject
///      count, payable amount and exam session were copied from the
///      exam-cell import at activation.
///   2. `students/{registerNumber}` – the exam-cell legacy record (college,
///      DOB, degree/branch, regulation), when still readable.
class RegistrationPreviewScreen extends StatefulWidget {
  final Student student;
  final double fallbackAmount;

  const RegistrationPreviewScreen({
    super.key,
    required this.student,
    required this.fallbackAmount,
  });

  @override
  State<RegistrationPreviewScreen> createState() =>
      _RegistrationPreviewScreenState();
}

class _RegistrationPreviewScreenState extends State<RegistrationPreviewScreen> {
  final _firestoreService = FirestoreService();

  bool _loading = true;
  Map<String, dynamic>? _legacy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic>? legacy;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.student.registerNumber)
          .get();
      if (doc.exists && !(doc.data() ?? {}).containsKey('uid')) {
        legacy = doc.data();
      }
    } catch (_) {
      // Optional data source.
    }

    if (mounted) {
      setState(() {
        _legacy = legacy;
        _loading = false;
      });
    }

    // One-time self-heal: copy the preview fields into the student's own
    // document so the form renders without the legacy read next time.
    if (widget.student.needsPreviewPopulation && legacy != null) {
      try {
        await _firestoreService.updateOwnPreview(
          uid: widget.student.uid,
          data: {
            if (legacy['university'] != null)
              'university': legacy['university'],
            if (legacy['collegeName'] != null)
              'collegeName': legacy['collegeName'],
            if (legacy['collegeCode'] != null)
              'collegeCode': legacy['collegeCode'],
            if (legacy['degree'] != null) 'degree': legacy['degree'],
            if (legacy['branch'] != null) 'branch': legacy['branch'],
            if (legacy['regulation'] != null)
              'regulation': legacy['regulation'],
            if (legacy['dateOfBirth'] != null)
              'dateOfBirth': legacy['dateOfBirth'],
            if (legacy['subjects'] != null) 'subjects': legacy['subjects'],
            if (legacy['numberOfSubjects'] != null)
              'numberOfSubjects': legacy['numberOfSubjects'],
            if (legacy['totalFee'] != null) 'totalFee': legacy['totalFee'],
          },
        );
      } catch (_) {
        // Non-fatal – the form still renders from the merged data.
      }
    }
  }

  String _str(Map<String, dynamic>? map, String key, [String fallback = '']) {
    if (map == null) return fallback;
    final v = map[key];
    if (v == null) return fallback;
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Registration Preview')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final amount = (widget.student.totalFee ?? 0) > 0
        ? widget.student.totalFee!
        : (widget.fallbackAmount > 0 ? widget.fallbackAmount : 0.0);

    final examSession = widget.student.examFeeSession.isNotEmpty
        ? widget.student.examFeeSession
        : 'Nov. / Dec. Examination, 2026 Examination';
    final college =
        '${_str(_legacy, 'collegeName', widget.student.collegeName)}'
        '${_str(_legacy, 'collegeCode', widget.student.collegeCode).isNotEmpty ? " :: ${_str(_legacy, 'collegeCode', widget.student.collegeCode)}" : ''}';
    final registerNumber = _str(_legacy, 'registerNumber',
        widget.student.registerNumber);
    final name = _str(_legacy, 'name', widget.student.name);
    final dob = widget.student.dateOfBirth;
    final dobText = dob != null
        ? '${dob.day.toString().padLeft(2, '0')}-${dob.month.toString().padLeft(2, '0')}-${dob.year}'
        : '–';
    final degreeBranch = [
      _str(_legacy, 'degree', widget.student.degree),
      _str(_legacy, 'branch', widget.student.branch),
    ].where((s) => s.isNotEmpty).join(' ');
    final regulation = _str(_legacy, 'regulation', widget.student.regulation);

    final subjects = <Map<String, dynamic>>[];
    for (final s in widget.student.subjects) {
      subjects.add({
        'sem': _str(s, 'sem').isEmpty
            ? (widget.student.semester > 0 ? widget.student.semesterLabel : '')
            : _str(s, 'sem'),
        'code': _str(s, 'code'),
        'title': _str(s, 'title'),
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Registration Preview')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.white,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Text(
                    'REGISTRATION PREVIEW',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _headerBlock(theme, examSession),
                  const SizedBox(height: 10),
                  _detailsTable(theme, college, registerNumber, name, dobText,
                      degreeBranch, regulation),
                  const SizedBox(height: 10),
                  _subjectsTable(theme, subjects),
                  const SizedBox(height: 10),
                  _totalsTable(theme, subjects.length, amount),
                  const SizedBox(height: 8),
                  Text(
                    'Verify the details above, then continue to payment. '
                    'The exam cell verifies every submission.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: amount <= 0
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentSubmissionScreen(
                                student: widget.student,
                                amount: amount,
                              ),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    disabledBackgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.5),
                  ),
                  icon: const Icon(Icons.payment_rounded),
                  label: Text(
                    amount > 0
                        ? 'Proceed to Payment – ${AppHelpers.formatAmount(amount)}'
                        : 'Fee Not Announced',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBlock(ThemeData theme, String examSession) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black87),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/anna_university_logo.png',
            width: 52,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ANNA UNIVERSITY :: CHENNAI 600025',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Application for $examSession',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsTable(
    ThemeData theme,
    String college,
    String registerNumber,
    String name,
    String dob,
    String degreeBranch,
    String regulation,
  ) {
    Widget cell(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.black54),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? '–' : value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        );

    Widget sideCell(String label, String value) => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.black54),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? '–' : value,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        );

    return Table(
      border: TableBorder.all(color: Colors.black54),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          cell('College Name & Code', college),
          sideCell('Register Number', registerNumber),
        ]),
        TableRow(children: [
          cell('Name of the Candidate', name, bold: true),
          sideCell('Date of Birth', dob),
        ]),
        TableRow(children: [
          cell('Degree & Branch', degreeBranch),
          sideCell('Regulations', regulation),
        ]),
      ],
    );
  }

  Widget _subjectsTable(ThemeData theme, List<Map<String, dynamic>> subjects) {
    final headerStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    );
    final cellStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: 12,
      color: Colors.black87,
    );

    Widget header(String text, {Alignment align = Alignment.centerLeft}) =>
        Padding(
          padding: const EdgeInsets.all(8),
          child: align == Alignment.center
              ? Center(child: Text(text, style: headerStyle))
              : Text(text, style: headerStyle),
        );

    return Table(
      border: TableBorder.all(color: Colors.black54),
      columnWidths: const {
        0: FlexColumnWidth(1.4),
        1: FlexColumnWidth(2.2),
        2: FlexColumnWidth(6.4),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF3F4F6)),
          children: [
            header('Sem No.', align: Alignment.center),
            header('Subject Code', align: Alignment.center),
            header('Subject Title'),
          ],
        ),
        for (final s in subjects)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                  child: Text(
                s['sem'].toString().isEmpty ? '–' : s['sem'],
                style: cellStyle,
              )),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                s['code'].toString(),
                style: cellStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                (s['title'] as String).isEmpty
                    ? _subjectTitle(s['code'].toString())
                    : s['title'],
                style: cellStyle,
              ),
            ),
          ]),
      ],
    );
  }

  Widget _totalsTable(ThemeData theme, int count, double amount) {
    final style = TextStyle(
      fontFamily: 'Poppins',
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    );
    return Table(
      border: TableBorder.all(color: Colors.black54),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF3F4F6)),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text('No of Subjects', style: style),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text('Total Fees (Payable)', style: style),
              ),
            ),
          ],
        ),
        TableRow(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: Text(
                '$count',
                style: style.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: Text(
                'Rs. ${amount.toStringAsFixed(0)}',
                style: style.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  static const Map<String, String> _subjectTitles = {
    'CME365': 'Renewable Energy Technologies',
    'CS3711': 'Summer internship',
    'GE3751': 'Principles of Management',
    'GE3791': 'Human Values and Ethics',
    'NM1068': 'Cloud Engineering',
    'OHS352': 'Project Report Writing',
    'OBT351': 'Food, Nutrition and Health',
    'GE3451': 'Environmental Sciences and Sustainability',
    'CCS336': 'Cloud Services Management',
    'CCS356': 'Object Oriented Software Engineering',
    'CCS375': 'Web Technologies',
    'CCW332': 'Digital Marketing',
    'CS3691': 'Embedded Systems and IoT',
  };

  static String _subjectTitle(String code) =>
      _subjectTitles[code.toUpperCase()] ?? code;
}
