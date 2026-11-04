import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_version.dart';

/// Checks GitHub Releases for a newer APK.
///
/// Because DailyHub is distributed outside the Play Store, this is the only
/// way users learn an update exists. It deliberately does NOT install the APK
/// itself — it opens the release page so the user downloads normally. That
/// avoids the REQUEST_INSTALL_PACKAGES permission and the "install unknown
/// apps" prompt, at the cost of one extra tap.
class UpdateInfo {
  final String version;
  final String notes;
  final String pageUrl;
  final String? apkUrl;

  UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _skipKey = 'skippedUpdateVersion';

  /// Returns update details if GitHub has a newer release, else null.
  Future<UpdateInfo?> check({bool ignoreSkipped = false}) async {
    try {
      final res = await http
          .get(Uri.parse(AppVersion.releasesApi), headers: {
            'Accept': 'application/vnd.github+json',
          })
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;

      final tag = (json['tag_name'] ?? '').toString();
      if (tag.isEmpty) return null;
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;

      if (!_isNewer(latest, AppVersion.appVersion)) return null;

      if (!ignoreSkipped) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_skipKey) == latest) return null;
      }

      // Find the .apk asset if the release has one.
      String? apkUrl;
      final assets = json['assets'];
      if (assets is List) {
        for (final a in assets) {
          final name = (a['name'] ?? '').toString().toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = a['browser_download_url']?.toString();
            break;
          }
        }
      }

      return UpdateInfo(
        version: latest,
        notes: (json['body'] ?? '').toString(),
        pageUrl: (json['html_url'] ?? AppVersion.releasesPage).toString(),
        apkUrl: apkUrl,
      );
    } catch (e) {
      // Offline, rate-limited, or repo not found — fail quietly. An update
      // check should never interrupt the app.
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Remember that the user dismissed this version, so we stop nagging.
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipKey, version);
  }

  /// Semantic-ish comparison: 1.10.0 is correctly newer than 1.9.0.
  static bool _isNewer(String latest, String current) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+-]'))
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parts(latest);
    final b = parts(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x > y) return true;
      if (x < y) return false;
    }
    return false;
  }
}
