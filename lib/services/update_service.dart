import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';
import '../utils/theme.dart';

/// A newer release found on GitHub.
class AppUpdate {
  final String version;
  final String changelog;
  final String? apkUrl;
  final String releaseUrl;

  const AppUpdate({
    required this.version,
    required this.changelog,
    this.apkUrl,
    required this.releaseUrl,
  });
}

/// In-app update checking against GitHub releases.
///
/// When a release tagged newer than [AppConstants.appVersion] exists on
/// `AppConstants.githubRepo`:
///   • an update card appears automatically on the dashboard when the app
///     opens (see [updateNotifier]),
///   • a popup also shows once per session,
///   • the Profile screen's "Check for Update" button runs the check on
///     demand.
class UpdateService {
  /// Latest update found this session – listened to by the dashboard card.
  static final ValueNotifier<AppUpdate?> updateNotifier =
      ValueNotifier<AppUpdate?>(null);

  static bool _checkedThisSession = false;
  static bool _startupDialogShown = false;

  /// Queries GitHub for the latest release. Results are cached in
  /// [updateNotifier] for the whole session.
  Future<AppUpdate?> checkForUpdate({bool force = false}) async {
    if (!AppConstants.updateCheckEnabled) return null;
    if (_checkedThisSession && !force) return updateNotifier.value;
    _checkedThisSession = true;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse(
            'https://api.github.com/repos/${AppConstants.githubRepo}/releases/latest'),
      );
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'au-exam-fee-student');
      final response = await request.close();
      if (response.statusCode != 200) return updateNotifier.value;

      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final tag = (data['tag_name'] ?? '').toString().replaceFirst(
            RegExp(r'^[vV]'),
            '',
          );
      if (tag.isEmpty || !_isNewer(tag, AppConstants.appVersion)) {
        return updateNotifier.value;
      }

      String? apkUrl;
      for (final asset in (data['assets'] as List? ?? [])) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = (asset['browser_download_url'] ?? '').toString();
          break;
        }
      }

      final update = AppUpdate(
        version: tag,
        changelog: (data['body'] ?? '').toString(),
        apkUrl: (apkUrl?.isNotEmpty ?? false) ? apkUrl : null,
        releaseUrl: (data['html_url'] ?? '').toString(),
      );
      updateNotifier.value = update;
      return update;
    } catch (_) {
      // Offline, rate-limited or repository not reachable – updates are
      // optional and fail silently.
      return updateNotifier.value;
    } finally {
      client?.close();
    }
  }

  /// Runs once when the app opens: refreshes [updateNotifier] and pops up
  /// the update dialog (unless already shown this session).
  Future<void> runStartupCheck(BuildContext context) async {
    final update = await checkForUpdate();
    if (update != null && !_startupDialogShown && context.mounted) {
      _startupDialogShown = true;
      showUpdateDialog(context, update);
    }
  }

  /// Manual check (Profile button): shows the update dialog when a newer
  /// release exists, otherwise confirms the app is current.
  Future<void> manualCheck(BuildContext context) async {
    final update = await checkForUpdate(force: true);
    if (!context.mounted) return;
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'You are using the latest version (v${AppConstants.appVersion}).'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }
    _startupDialogShown = true;
    showUpdateDialog(context, update);
  }

  /// The update dialog with release notes and an Update Now action.
  void showUpdateDialog(BuildContext context, AppUpdate update) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${update.version} is available '
              '(you have v${AppConstants.appVersion}).',
            ),
            if (update.changelog.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                update.changelog.trim(),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: AppTheme.secondaryTextColor,
                    height: 1.5),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openUpdate(update);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  void _openUpdate(AppUpdate update) {
    final url = update.apkUrl ?? update.releaseUrl;
    if (url.isNotEmpty) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  /// Semantic-ish comparison of "MAJOR.MINOR.PATCH" strings.
  bool _isNewer(String remote, String local) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final r = parse(remote);
    final l = parse(local);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }
}
