import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/student.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/validators.dart';
import '../auth/login_screen.dart';

/// Student profile with self-service phone editing. Academic information
/// can only be corrected by the exam cell (Admin App) – enforced here and
/// by Firestore rules.
class ProfileScreen extends StatelessWidget {
  final Student student;

  const ProfileScreen({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: () => _editPhone(context),
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit phone number',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  backgroundImage:
                      const AssetImage('assets/images/anna_university_logo.png'),
                ),
                const SizedBox(height: 12),
                Text(
                  student.name.isEmpty ? 'Student' : student.name,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                if (student.registerNumber.isNotEmpty)
                  Text(
                    student.registerNumber,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Student',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  _item(context, Icons.person_outline, 'Name', student.name),
                  _divider,
                  _item(context, Icons.badge_outlined, 'Register Number',
                      student.registerNumber),
                  _divider,
                  _item(context, Icons.email_outlined, 'Email', student.email),
                  _divider,
                  _item(context, Icons.account_tree_outlined, 'Department',
                      student.department),
                  _divider,
                  _item(context, Icons.school_outlined, 'Year',
                      student.yearLabel),
                  _divider,
                  _item(context, Icons.menu_book_outlined, 'Semester',
                      student.semesterLabel),
                  _divider,
                  _item(context, Icons.groups_outlined, 'Section', student.section),
                  _divider,
                  _item(context, Icons.phone_outlined, 'Phone Number',
                      student.phone),
                  _divider,
                  _item(context, Icons.calendar_month_outlined, 'Academic Year',
                      student.academicYear),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Academic details are maintained by the exam cell. '
              'If anything looks incorrect, please contact your college office.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Text(
                  'v${AppConstants.appVersion}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Developed by ${AppConstants.developerName}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => launchUrl(
                    Uri(
                        scheme: 'mailto',
                        path: AppConstants.developerEmail,
                        query: 'subject=AU Exam Fee – Student App Support'),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.alternate_email_rounded,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          AppConstants.developerEmail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Edit dialog for the student's own phone number (contact info only –
  /// academic fields remain exam-cell managed).
  Future<void> _editPhone(BuildContext context) async {
    final controller =
        TextEditingController(text: student.phone);
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Phone Number'),
        content: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          validator: Validators.phone,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (Validators.phone(controller.text) != null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(Validators.phone(controller.text)!),
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated != true || !context.mounted) return;
    try {
      await FirestoreService()
          .updateOwnContact(uid: student.uid, phone: controller.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone number updated.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  static const _divider = Divider(height: 1, indent: 56);

  Widget _item(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label, style: theme.textTheme.bodySmall),
      subtitle: Text(
        value.isEmpty ? '–' : value,
        style: theme.textTheme.titleMedium,
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService().signOut();
      // AuthGate switches back to LoginScreen via authStateChanges.
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
