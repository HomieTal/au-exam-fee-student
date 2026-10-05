import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/student.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/validators.dart';
import '../../utils/notifications.dart';
import '../../widgets/auth_background.dart';
import 'login_screen.dart';

/// Self-service student registration: creates the Auth account and the
/// `students/{uid}` profile document (only for the signer's own UID).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  final _nameController = TextEditingController();
  final _registerNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _academicYearController = TextEditingController();

  String? _department;
  int? _year;
  int? _semester;
  String? _section;

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _academicYearController.text = AppHelpers.currentAcademicYear();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _registerNumberController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _academicYearController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    UserCredential? credential;
    try {
      credential = await _authService.register(
        email: _emailController.text,
        password: _passwordController.text,
      );

      final student = Student(
        uid: credential.user!.uid,
        name: _nameController.text.trim(),
        registerNumber: _registerNumberController.text.trim().toUpperCase(),
        email: _emailController.text.trim(),
        department: _department ?? '',
        year: _year ?? 0,
        semester: _semester ?? 0,
        section: _section ?? '',
        phone: _phoneController.text.trim(),
        academicYear: _academicYearController.text.trim(),
        createdAt: DateTime.now(),
      );

      try {
        await _firestoreService.createStudentProfile(student);
      } catch (profileError) {
        // Roll the Auth account back so the student can retry cleanly.
        try {
          await credential.user!.delete();
        } catch (_) {}
        rethrow;
      }

      // Publish the login index so the student can sign in with their
      // register number and reset their password by email later.
      try {
        await _authService.publishLoginIndex(
          registerNumber: student.registerNumber,
          email: student.email,
        );
      } catch (_) {
        // Optional convenience — registration itself is already complete.
      }

      if (mounted) {
        AppNotifications.show(
          context,
          'Registration successful! Please sign in.',
          success: true,
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotifications.show(context, e.toString(), error: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Registration')),
      body: AuthBackground(
        child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Create your exam fee account',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Your academic details must match college records. They can only be corrected by the exam cell.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            _sectionHeader('Personal Details'),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              validator: Validators.name,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _registerNumberController,
              textCapitalization: TextCapitalization.characters,
              validator: Validators.registerNumber,
              decoration: const InputDecoration(
                labelText: 'Register Number *',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              decoration: const InputDecoration(
                labelText: 'Email *',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number *',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader('Academic Details'),
            DropdownButtonFormField<String>(
              initialValue: _department,
              items: const [
                'CSE', 'ECE', 'EEE', 'MECH', 'CIVIL', 'IT', 'AI & DS', 'Other',
              ]
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() => _department = v),
              validator: (v) =>
                  v == null ? 'Department is required' : null,
              decoration: const InputDecoration(
                labelText: 'Department *',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    items: const [1, 2, 3, 4]
                        .map((y) => DropdownMenuItem(
                            value: y, child: Text(AppHelpers.intToRoman(y))))
                        .toList(),
                    onChanged: (v) => setState(() => _year = v),
                    validator: (v) => v == null ? 'Required' : null,
                    decoration: const InputDecoration(labelText: 'Year *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _semester,
                    items: const [1, 2, 3, 4, 5, 6, 7, 8]
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(AppHelpers.intToRoman(s))))
                        .toList(),
                    onChanged: (v) => setState(() => _semester = v),
                    validator: (v) => v == null ? 'Required' : null,
                    decoration:
                        const InputDecoration(labelText: 'Semester *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _section,
                    items: AppConstants.sectionOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _section = v),
                    validator: (v) => v == null ? 'Required' : null,
                    decoration: const InputDecoration(labelText: 'Section *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _academicYearController,
                    validator: (v) =>
                        Validators.required(v, field: 'Academic year'),
                    decoration: const InputDecoration(
                        labelText: 'Academic Year *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionHeader('Security'),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              validator: Validators.password,
              decoration: InputDecoration(
                labelText: 'Password *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              validator: (v) =>
                  Validators.confirmPassword(v, _passwordController.text),
              decoration: const InputDecoration(
                labelText: 'Confirm Password *',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _register,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create Account'),
              ),
            ),
            const SizedBox(height: 16),
            const AuthFooter(),
            const SizedBox(height: 8),
          ],
        ),
      ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
