import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// In-app updater — checks GitHub releases for a newer VideoTool version,
/// downloads the APK, and opens it for install.
/// No more manual downloads from the browser.
class UpdateService {
  static const _owner = 'Testme6464';
  static const _repo = 'videotool';
  static const _api =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Returns the latest release info, or null on failure.
  Future<_Release?> checkLatest() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. 0.4.4
      final res = await http
          .get(Uri.parse(_api),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String?) ?? '';
      final latest =
          tag.startsWith('v') ? tag.substring(1) : tag;
      if (latest.isEmpty) return null;
      // Find the APK asset.
      String? apkUrl;
      int apkSize = 0;
      for (final a in (j['assets'] as List? ?? [])) {
        final m = a as Map<String, dynamic>;
        final name = (m['name'] as String?) ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = m['browser_download_url'] as String?;
          apkSize = (m['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }
      return _Release(
        current: current,
        latest: latest,
        tag: tag,
        apkUrl: apkUrl,
        apkSize: apkSize,
        hasUpdate: _isNewer(latest, current),
      );
    } catch (_) {
      return null;
    }
  }

  /// Compare semantic versions: true if [latest] > [current].
  bool _isNewer(String latest, String current) {
    List<int> parse(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final l = parse(latest);
    final c = parse(current);
    for (var i = 0;
        i < l.length || i < c.length;
        i++) {
      final li = i < l.length ? l[i] : 0;
      final ci = i < c.length ? c[i] : 0;
      if (li > ci) return true;
      if (li < ci) return false;
    }
    return false;
  }

  /// Downloads the APK with progress. Returns the file path.
  Future<String> download(
    String url,
    void Function(double) onProgress,
  ) async {
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/videotool-update.apk');
    final req = http.Request('GET', Uri.parse(url));
    final streamed =
        await http.Client().send(req).timeout(
              const Duration(minutes: 30),
            );
    if (streamed.statusCode != 200) {
      throw Exception(
          'Download failed (HTTP ${streamed.statusCode})');
    }
    final total = streamed.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
    return file.path;
  }

  /// Opens the APK → system install prompt.
  /// (User must allow "Install unknown apps" for VideoTool once.)
  Future<void> installApk(String path) async {
    await OpenFile.open(path,
        type: 'application/vnd.android.package-archive');
  }
}

class _Release {
  final String current;
  final String latest;
  final String tag;
  final String? apkUrl;
  final int apkSize;
  final bool hasUpdate;
  _Release({
    required this.current,
    required this.latest,
    required this.tag,
    required this.apkUrl,
    required this.apkSize,
    required this.hasUpdate,
  });

  String get sizeText => apkSize <= 0
      ? ''
      : ' (${(apkSize / 1048576).toStringAsFixed(0)} MB)';
}
