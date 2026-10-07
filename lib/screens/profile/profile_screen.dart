import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/student.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/update_service.dart';
import '../../utils/constants.dart';
import '../../utils/validators.dart';
import '../../utils/notifications.dart';
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
            onPressed: () => _openEditOptions(context),
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
                _CheckUpdateButton(),
                const SizedBox(height: 12),
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

  /// Bottom sheet with the three self-service edit options.
  Future<void> _openEditOptions(BuildContext context) async {
    final option = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Phone Number'),
                subtitle: Text(student.phone.isEmpty ? 'Not set' : student.phone),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, 'phone'),
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email_rounded),
                title: const Text('Email ID'),
                subtitle: Text(student.email),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, 'email'),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Change Password'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, 'password'),
              ),
            ],
          ),
        ),
      ),
    );
    if (option == 'phone' && context.mounted) _editPhone(context);
    if (option == 'email' && context.mounted) _editEmail(context);
    if (option == 'password' && context.mounted) _changePassword(context);
  }

  /// Sends the verification mail for a new personal email and records it.
  Future<void> _editEmail(BuildContext context) async {
    final controller = TextEditingController(text: student.email);
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Email ID'),
        content: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email ID',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send Verification'),
          ),
        ],
      ),
    );
    if (updated != true || !context.mounted) return;
    final email = controller.text.trim();
    if (Validators.email(email) != null) {
      AppNotifications.show(context, Validators.email(email)!, error: true);
      return;
    }
    try {
      await AuthService().sendEmailVerificationTo(email);
      await FirestoreService().updateOwnContact(uid: student.uid, email: email);
      if (context.mounted) {
        AppNotifications.show(
          context,
          'Verification mail sent to . Click the link to activate it.',
          success: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppNotifications.show(context, e.toString(), error: true);
      }
    }
  }

  /// Re-authenticates and changes the account password.
  Future<void> _changePassword(BuildContext context) async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: currentController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (updated != true || !context.mounted) return;
    if (newController.text.length < 6) {
      AppNotifications.show(
          context, 'Password must be at least 6 characters.', error: true);
      return;
    }
    try {
      await AuthService().changePassword(
        currentPassword: currentController.text,
        newPassword: newController.text,
      );
      if (context.mounted) {
        AppNotifications.show(
            context, 'Password changed successfully.', success: true);
      }
    } catch (e) {
      if (context.mounted) {
        AppNotifications.show(context, e.toString(), error: true);
      }
    }
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
                AppNotifications.show(
                  dialogContext,
                  Validators.phone(controller.text)!,
                  error: true,
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
        AppNotifications.show(context, 'Phone number updated.', success: true);
      }
    } catch (e) {
      if (context.mounted) {
        AppNotifications.show(context, e.toString(), error: true);
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

  Future<void> _confirmLogout(BuildContext context) async {    final confirmed = await showDialog<bool>(
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
      // AuthGate switches back to LoginScreen via authStateChanges. Do NOT
      // push a LoginScreen route here: pushAndRemoveUntil removes the gate's
      // route, unmounting the one listener that reacts to the next sign-in —
      // the student signs in successfully and nothing happens.
    }
  }
}

/// "Check for Update" button – runs the GitHub release check on demand.
class _CheckUpdateButton extends StatefulWidget {
  @override
  State<_CheckUpdateButton> createState() => _CheckUpdateButtonState();
}

class _CheckUpdateButtonState extends State<_CheckUpdateButton> {
  final _updateService = UpdateService();
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      await _updateService.manualCheck(context);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: _checking ? null : _check,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      icon: _checking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : const Icon(Icons.system_update_alt_rounded, size: 18),
      label: Text(
        _checking ? 'Checking…' : 'Check for Update',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
