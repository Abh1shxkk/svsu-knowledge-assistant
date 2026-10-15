/// Tells people when a newer version of the app is published, so nobody stays on an old one.
/// New versions are GitHub Releases tagged `android-v<version>` (e.g. android-v1.1.0) with the APK attached.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

const _releases = 'https://api.github.com/repos/Abh1shxkk/svsu-knowledge-assistant/releases?per_page=20';
const tagPrefix = 'android-v';

/// "1.10.0" > "1.9.2": compares number by number.
bool isNewer(String candidate, String current) {
  List<int> parts(String v) => v.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final a = parts(candidate), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

bool _asked = false;

/// Checks once per app start; quietly does nothing when offline or when GitHub can't be reached.
Future<void> checkForUpdate(BuildContext context) async {
  if (_asked) return;
  _asked = true;
  try {
    final current = (await PackageInfo.fromPlatform()).version;
    final res = await http.get(Uri.parse(_releases), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    final latest = list.where((r) => r['draft'] != true && r['prerelease'] != true && '${r['tag_name']}'.startsWith(tagPrefix)).firstOrNull;
    if (latest == null) return;
    final version = '${latest['tag_name']}'.substring(tagPrefix.length);
    if (!isNewer(version, current)) return;
    if (!context.mounted) return;
    final page = '${latest['html_url']}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('A new version is available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          'Version $version of SVSU Assistant is ready (you have $current). Download it and open the file to update. '
          'Your sign-in and saved items stay as they are.',
          style: TextStyle(fontSize: 14, color: ctx.pal.fg2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(page), mode: LaunchMode.externalApplication);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  } catch (_) {
    // Offline, rate-limited or GitHub unreachable: try again next time the app starts.
  }
}
