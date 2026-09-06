import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';

/// GitHub Releases 에 올라온 최신 버전
class AppRelease {
  final String tagName;
  final String version;
  final String htmlUrl;
  final String? notes;
  final List<ReleaseAsset> assets;

  AppRelease({required this.tagName, required this.version, required this.htmlUrl, this.notes, required this.assets});

  ReleaseAsset? assetWhere(bool Function(String name) test) {
    for (final a in assets) {
      if (test(a.name.toLowerCase())) return a;
    }
    return null;
  }

  /// 현재 플랫폼에 맞는 설치 파일
  ReleaseAsset? get assetForThisPlatform {
    if (kIsWeb) return null;
    if (Platform.isWindows) return assetWhere((n) => n.contains('windows') && n.endsWith('.zip'));
    if (Platform.isAndroid) return assetWhere((n) => n.endsWith('.apk'));
    return null;
  }
}

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  ReleaseAsset({required this.name, required this.downloadUrl, required this.size});
}

/// GitHub Releases 기반 업데이트 확인/설치
class UpdateService {
  final String appRepo; // owner/repo
  final Dio _dio = Dio(BaseOptions(
    headers: {'Accept': 'application/vnd.github+json'},
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 5),
  ));

  UpdateService({this.appRepo = AppConstants.appRepo});

  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  /// 최신 릴리스. 릴리스가 없거나 네트워크 오류면 null.
  Future<AppRelease?> fetchLatest() async {
    try {
      final res = await _dio.get('${AppConstants.githubApiBaseUrl}/repos/$appRepo/releases/latest');
      final data = res.data as Map;
      final tag = data['tag_name'] as String? ?? '';
      final assets = ((data['assets'] as List?) ?? const [])
          .map((a) => ReleaseAsset(
                name: a['name'] as String,
                downloadUrl: a['browser_download_url'] as String,
                size: (a['size'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      return AppRelease(
        tagName: tag,
        version: normalizeVersion(tag),
        htmlUrl: data['html_url'] as String? ?? 'https://github.com/$appRepo/releases',
        notes: data['body'] as String?,
        assets: assets,
      );
    } catch (_) {
      return null;
    }
  }

  /// 현재보다 새 버전이 있으면 그 릴리스를 돌려준다
  Future<AppRelease?> checkForUpdate() async {
    final latest = await fetchLatest();
    if (latest == null) return null;
    final current = await currentVersion();
    return compareVersions(latest.version, current) > 0 ? latest : null;
  }

  static String normalizeVersion(String tag) {
    var v = tag.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    return v;
  }

  /// 1.2.10 > 1.2.9 처럼 숫자 단위 비교. a>b 면 양수.
  static int compareVersions(String a, String b) {
    final pa = normalizeVersion(a).split('.').map((s) => int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '') ?? 0).toList();
    final pb = normalizeVersion(b).split('.').map((s) => int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '') ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Windows: zip 을 내려받아 현재 설치 폴더에 덮어쓰는 스크립트를 띄우고 앱을 종료한다.
  Future<void> installWindows(ReleaseAsset asset, {void Function(double progress)? onProgress}) async {
    final exePath = Platform.resolvedExecutable;
    final installDir = p.dirname(exePath);
    final tempDir = Directory.systemTemp;
    final zipPath = p.join(tempDir.path, 'mohitto_blog_writer_update.zip');
    final scriptPath = p.join(tempDir.path, 'mohitto_blog_writer_update.ps1');

    await _dio.download(
      asset.downloadUrl,
      zipPath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    final script = '''
param([string]\$zip, [string]\$dest, [string]\$exe, [int]\$waitPid)
try { Wait-Process -Id \$waitPid -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 1
Expand-Archive -Path \$zip -DestinationPath \$dest -Force
Remove-Item \$zip -ErrorAction SilentlyContinue
Start-Process -FilePath \$exe
''';
    await File(scriptPath).writeAsString(script);

    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', scriptPath,
        '-zip', zipPath,
        '-dest', installDir,
        '-exe', exePath,
        '-waitPid', pid.toString(),
      ],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
