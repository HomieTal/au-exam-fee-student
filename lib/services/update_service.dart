import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';
import '../utils/theme.dart';
import '../utils/notifications.dart';

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
      AppNotifications.show(
        context,
        'You are using the latest version (v${AppConstants.appVersion}).',
        success: true,
      );
      return;
    }
    _startupDialogShown = true;
    showUpdateDialog(context, update);
  }

  /// The update popup - a centered white card over a dimmed screen with an
  /// icon badge, bold title and stacked full-width actions (design-matched).
  void showUpdateDialog(BuildContext context, AppUpdate update) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_alt_rounded,
                  size: 44,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'UPDATE AVAILABLE!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppTheme.textColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Version ${update.version} is available '
                '(you have v${AppConstants.appVersion}).',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.5,
                  color: AppTheme.secondaryTextColor,
                  height: 1.5,
                ),
              ),
              if (update.changelog.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  update.changelog.trim(),
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    color: AppTheme.secondaryTextColor,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _openUpdate(update);
                  },
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Update Now',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.secondaryTextColor,
                    side: const BorderSide(color: AppTheme.borderColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Later',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
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
