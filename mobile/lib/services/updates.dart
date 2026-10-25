import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

Future<String> appVersion() async {
  final p = await PackageInfo.fromPlatform();
  return '${p.version} (${p.buildNumber})';
}

/// The app isn't in Google Play or the Mac App Store, so it checks the
/// manifest CI publishes next to the APK and the DMG and offers the
/// download when a newer build is out. Android and macOS — iPhones get
/// updates however the IPA was installed.
Future<void> checkForUpdate(BuildContext context, {bool manual = false}) async {
  final mac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && !mac)) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('На iPhone оновлення встановлюються тим самим способом, що й застосунок.')),
      );
    }
    return;
  }
  Map<String, dynamic>? manifest;
  try {
    final res = await http.get(Uri.parse('$updateManifestUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
    if (res.statusCode == 200) manifest = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  } catch (_) {}
  if (!context.mounted) return;
  if (manifest == null) {
    if (manual) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не вдалося перевірити оновлення. Перевірте інтернет.')));
    }
    return;
  }
  final info = await PackageInfo.fromPlatform();
  final current = int.tryParse(info.buildNumber) ?? 0;
  final latest = (manifest['versionCode'] as num?)?.toInt() ?? 0;
  if (!context.mounted) return;
  if (latest <= current) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('У вас остання версія (${info.version}).')));
    }
    return;
  }
  final url = mac ? (manifest['dmgUrl'] as String?) ?? latestDmgUrl : (manifest['apkUrl'] as String?) ?? latestApkUrl;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Доступна нова версія', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Text(
        mac
            ? 'Stemik Admin ${manifest!['versionName'] ?? ''} готовий до встановлення. Завантажте .dmg, відкрийте його й перетягніть застосунок у «Програми» із заміною — вхід і дані збережуться.'
            : 'Stemik ${manifest!['versionName'] ?? ''} готовий до встановлення. Завантажте файл і відкрийте його — Android оновить застосунок, дані збережуться.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Пізніше')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Завантажити')),
      ],
    ),
  );
  if (go == true) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
