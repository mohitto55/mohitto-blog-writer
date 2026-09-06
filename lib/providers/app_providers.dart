import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/jekyll_theme.dart';
import '../services/blog_repository.dart';
import '../services/github_blog_repository.dart';
import '../services/jekyll_service.dart';
import '../services/jekyll_theme_service.dart';
import '../services/local_blog_repository.dart';
import '../services/update_service.dart';

/// Provider for SharedPreferences
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

/// 데스크톱(Windows/macOS/Linux)에서 실행 중인지. 웹/모바일이면 false.
final isDesktopProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
});

/// Settings State Notifier
class SettingsNotifier extends StateNotifier<Map<String, String>> {
  final SharedPreferences? prefs;

  SettingsNotifier(this.prefs) : super(_loadSettings(prefs!));

  // 로딩 중이거나 에러 발생 시 사용할 빈 생성자
  SettingsNotifier._empty() : prefs = null, super(_emptySettings());

  static String get _defaultBlogPath {
    if (kIsWeb) return '';
    return Platform.isWindows ? r'C:\Users\admin\git\blog' : '';
  }

  static Map<String, String> _loadSettings(SharedPreferences prefs) {
    return {
      AppConstants.settingsGitHubToken: prefs.getString(AppConstants.settingsGitHubToken) ?? '',
      AppConstants.settingsGitHubOwner: prefs.getString(AppConstants.settingsGitHubOwner) ?? '',
      AppConstants.settingsGitHubRepo: prefs.getString(AppConstants.settingsGitHubRepo) ?? '',
      AppConstants.settingsGitHubBranch: prefs.getString(AppConstants.settingsGitHubBranch) ?? '',
      AppConstants.settingsStorageMode: prefs.getString(AppConstants.settingsStorageMode) ?? 'auto',
      AppConstants.settingsObsidianVaultPath: prefs.getString(AppConstants.settingsObsidianVaultPath) ?? '',
      AppConstants.settingsJekyllBlogPath: prefs.getString(AppConstants.settingsJekyllBlogPath) ?? _defaultBlogPath,
    };
  }

  static Map<String, String> _emptySettings() {
    return {
      AppConstants.settingsGitHubToken: '',
      AppConstants.settingsGitHubOwner: '',
      AppConstants.settingsGitHubRepo: '',
      AppConstants.settingsGitHubBranch: '',
      AppConstants.settingsStorageMode: 'auto',
      AppConstants.settingsObsidianVaultPath: '',
      AppConstants.settingsJekyllBlogPath: _defaultBlogPath,
    };
  }

  Future<void> updateSetting(String key, String value) async {
    if (prefs != null) {
      await prefs!.setString(key, value);
    }
    state = {...state, key: value};
  }

  Future<void> updateMultipleSettings(Map<String, String> settings) async {
    if (prefs != null) {
      for (final entry in settings.entries) {
        await prefs!.setString(entry.key, entry.value);
      }
    }
    state = {...state, ...settings};
  }

  String? getSetting(String key) {
    return state[key];
  }
}

/// Settings Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, Map<String, String>>((ref) {
  final prefsAsync = ref.watch(sharedPreferencesProvider);

  return prefsAsync.when(
    data: (prefs) => SettingsNotifier(prefs),
    loading: () => SettingsNotifier._empty(),
    error: (err, stack) => SettingsNotifier._empty(),
  );
});

/// 설정된 Jekyll 블로그 로컬 경로 (데스크톱 전용 기능에서 사용)
final jekyllBlogPathProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings[AppConstants.settingsJekyllBlogPath] ?? '';
});

/// 저장 방식 결정 결과
enum StorageKind { local, github, none }

/// 현재 설정과 플랫폼으로 결정된 블로그 저장소.
///
/// - `auto`: 데스크톱이고 로컬 경로가 있으면 로컬 폴더, 아니면 GitHub 설정이 있을 때 GitHub
/// - `local` / `github`: 강제
/// - 아무 것도 설정되지 않았으면 null
final blogRepositoryProvider = Provider<BlogRepository?>((ref) {
  final settings = ref.watch(settingsProvider);
  final isDesktop = ref.watch(isDesktopProvider);
  final prefs = ref.watch(sharedPreferencesProvider).value;

  final mode = settings[AppConstants.settingsStorageMode] ?? 'auto';
  final blogPath = settings[AppConstants.settingsJekyllBlogPath] ?? '';
  final owner = (settings[AppConstants.settingsGitHubOwner] ?? '').trim();
  final repo = (settings[AppConstants.settingsGitHubRepo] ?? '').trim();
  final token = (settings[AppConstants.settingsGitHubToken] ?? '').trim();
  final branch = (settings[AppConstants.settingsGitHubBranch] ?? '').trim();

  final localAvailable = isDesktop && blogPath.isNotEmpty && Directory(blogPath).existsSync();
  final githubAvailable = owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;

  StorageKind kind;
  switch (mode) {
    case 'local':
      kind = localAvailable ? StorageKind.local : StorageKind.none;
    case 'github':
      kind = githubAvailable ? StorageKind.github : StorageKind.none;
    default:
      kind = localAvailable
          ? StorageKind.local
          : githubAvailable
              ? StorageKind.github
              : StorageKind.none;
  }

  switch (kind) {
    case StorageKind.local:
      return LocalBlogRepository(blogPath: blogPath);
    case StorageKind.github:
      return GitHubBlogRepository(
        owner: owner,
        repo: repo,
        token: token,
        branchOverride: branch.isEmpty ? null : branch,
        prefs: prefs,
      );
    case StorageKind.none:
      return null;
  }
});

/// 연결된 블로그를 스캔한 테마 정보 (커스텀 블록, 스킨 색상, 카테고리, 태그, 템플릿)
///
/// `ref.invalidate(jekyllThemeProvider)` 로 다시 스캔한다.
final jekyllThemeProvider = FutureProvider<JekyllTheme>((ref) async {
  final repository = ref.watch(blogRepositoryProvider);
  if (repository == null) return JekyllTheme.fallback('');
  return JekyllThemeService(repository: repository).scan();
});

/// 앱 전체에서 하나만 유지되는 Jekyll 서버 관리자 (프로세스 핸들 보존, 데스크톱 전용)
final jekyllServiceProvider = Provider<JekyllService>((ref) {
  final blogPath = ref.watch(jekyllBlogPathProvider);
  final service = JekyllService(blogPath: blogPath);
  ref.onDispose(() => service.dispose());
  return service;
});

/// GitHub Releases 기반 업데이트 확인
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
