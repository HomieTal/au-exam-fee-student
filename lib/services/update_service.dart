import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';
import '../utils/theme.dart';

/// In-app update checking against GitHub releases.
///
/// When a release tagged newer than [AppConstants.appVersion] exists on
/// `AppConstants.githubRepo`, the app shows an update dialog with the
/// release notes and a button that opens the release page (or the APK
/// asset directly) in the browser.
class UpdateService {
  static bool _dismissedThisSession = false;

  Future<AppUpdate?> checkForUpdate() async {
    if (!AppConstants.updateCheckEnabled || _dismissedThisSession) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse(
            'https://api.github.com/repos/${AppConstants.githubRepo}/releases/latest'),
      );
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'au-exam-fee-student');
      final response = await request.close();
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final tag = (data['tag_name'] ?? '').toString().replaceFirst(
            RegExp(r'^[vV]'),
            '',
          );
      if (tag.isEmpty || !_isNewer(tag, AppConstants.appVersion)) return null;

      String? apkUrl;
      for (final asset in (data['assets'] as List? ?? [])) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = (asset['browser_download_url'] ?? '').toString();
          break;
        }
      }

      return AppUpdate(
        version: tag,
        changelog: (data['body'] ?? '').toString(),
        apkUrl: (apkUrl?.isNotEmpty ?? false) ? apkUrl : null,
        releaseUrl: (data['html_url'] ?? '').toString(),
      );
    } catch (_) {
      // Offline or repository not reachable – updates are optional.
      return null;
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

  /// Checks once per app start and shows the update dialog when a newer
  /// release exists.
  Future<void> maybeShowUpdateDialog(BuildContext context) async {
    final update = await checkForUpdate();
    if (update == null || !context.mounted) return;

    await showDialog<void>(
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
              '(you have ${AppConstants.appVersion}).',
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
            onPressed: () {
              _dismissedThisSession = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              _dismissedThisSession = true;
              Navigator.pop(dialogContext);
              final url = update.apkUrl ?? update.releaseUrl;
              if (url.isNotEmpty) {
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}

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
