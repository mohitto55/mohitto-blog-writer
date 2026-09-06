@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_github_publisher/services/github_blog_repository.dart';
import 'package:obsidian_github_publisher/services/jekyll_theme_service.dart';

/// 실제 GitHub 저장소를 읽는 스모크 테스트. 토큰이 있어야 API 한도(시간당 5000)를 쓴다.
/// 실행: flutter test test/services/github_blog_repository_live_test.dart --dart-define=GITHUB_TOKEN=github_pat_...
void main() {
  const token = String.fromEnvironment('GITHUB_TOKEN');

  test('블로그 저장소에서 포스트 목록과 테마를 읽는다', () async {
    final repo = GitHubBlogRepository(owner: 'mohitto55', repo: 'mohitto55.github.io', token: token);

    final posts = await repo.listPosts();
    expect(posts, isNotEmpty);
    expect(posts.any((p) => p.title.contains('[')), isTrue);
    expect(repo.location, 'mohitto55/mohitto55.github.io@main');

    final theme = await JekyllThemeService(repository: repo).scan();
    expect(theme.skin.name, 'mint');
    expect(theme.blockStyles.map((b) => b.className), contains('Reference'));
    expect(theme.categories.map((c) => c.slug), contains('cpp'));
    expect(theme.siteUrl, 'https://mohitto55.github.io');
    expect(theme.assetBaseUrl, 'https://raw.githubusercontent.com/mohitto55/mohitto55.github.io/main');

    final first = posts.firstWhere((p) => p.isPublished);
    final content = await repo.readPost(first.name);
    expect(content, startsWith('---'));
  }, skip: token.isEmpty ? 'GITHUB_TOKEN 이 없어 건너뜀' : false, timeout: const Timeout(Duration(minutes: 3)));
}
