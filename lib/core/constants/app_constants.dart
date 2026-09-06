/// Application-wide constants
class AppConstants {
  // GitHub API
  static const String githubApiBaseUrl = 'https://api.github.com';
  static const String githubApiVersion = '2022-11-28';

  // File paths
  static const String defaultPostsFolder = '_posts';
  static const String defaultAssetsFolder = 'assets/images';

  // Frontmatter keys mapping (Obsidian -> GitHub Blog)
  static const Map<String, String> frontmatterKeyMapping = {
    'created': 'date',
    'updated': 'modified',
    'title': 'title',
    'tags': 'tags',
    'published': 'published',
  };

  // App identity / updates
  static const String appName = 'Mohitto Blog Writer';
  /// 앱 소스 저장소 (GitHub Releases 로 자동 업데이트 확인)
  static const String appRepo = 'mohitto55/mohitto-blog-writer';

  // Settings keys
  static const String settingsStorageMode = 'storage_mode'; // auto | local | github
  static const String settingsGitHubBranch = 'github_branch';
  static const String settingsGitHubToken = 'github_token';
  static const String settingsGitHubRepo = 'github_repo';
  static const String settingsGitHubOwner = 'github_owner';
  static const String settingsObsidianVaultPath = 'obsidian_vault_path';
  static const String settingsPostsFolder = 'posts_folder';
  static const String settingsJekyllBlogPath = 'jekyll_blog_path';
  static const String settingsSelectedFiles = 'selected_files';

  // File extensions
  static const String markdownExtension = '.md';
  static const List<String> imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];

  // Jekyll
  static const String jekyllServerUrl = 'http://localhost:4000';
  static const int jekyllServerPort = 4000;

  // Error messages
  static const String errorNoGitHubToken = 'GitHub Personal Access Token이 설정되지 않았습니다.';
  static const String errorNoRepository = 'GitHub 저장소 정보가 설정되지 않았습니다.';
  static const String errorNoVaultPath = 'Obsidian Vault 경로가 설정되지 않았습니다.';
  static const String errorNoBlogPath = 'Jekyll 블로그 경로가 설정되지 않았습니다.';
  static const String errorFileNotFound = '파일을 찾을 수 없습니다.';
  static const String errorNetworkError = '네트워크 오류가 발생했습니다.';
  static const String errorJekyllServerFailed = 'Jekyll 서버 시작에 실패했습니다.';

  AppConstants._();
}
