import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_github_publisher/main.dart';
import 'package:obsidian_github_publisher/providers/app_providers.dart';
import 'package:obsidian_github_publisher/services/blog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 파일 시스템/네트워크 없이 동작하는 메모리 저장소
class FakeRepository implements BlogRepository {
  final Map<String, String> files = {
    '2025-01-01-[Test] 첫 글.md': '---\ntitle: "[Test] 첫 글"\ncategories: test\ntags: [a]\n---\n\n본문',
  };

  @override
  String get label => 'Fake';
  @override
  String get location => 'memory';
  @override
  bool get isLocal => false;
  @override
  String? get assetBaseUrl => null;

  @override
  Future<List<PostInfo>> listPosts() async =>
      files.entries.map((e) => PostInfo.fromContent(e.key, e.value, modified: DateTime(2025))).toList();
  @override
  Future<String> readPost(String name) async => files[name]!;
  @override
  Future<bool> postExists(String name) async => files.containsKey(name);
  @override
  Future<void> writePost(String name, String content, {String? previousName}) async {
    files[name] = content;
    if (previousName != null && previousName != name) files.remove(previousName);
  }

  @override
  Future<void> deletePost(String name) async => files.remove(name);
  @override
  Future<String> uploadImage(String fileName, Uint8List bytes) async => '/assets/images/$fileName';
  @override
  Future<String?> readTextFile(String path) async => null;
  @override
  Future<List<String>> listFiles(String dirPath, {bool recursive = false, String? extension}) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets('워크스페이스가 뜨고 글을 열어 저장할 수 있다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    final repo = FakeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [blogRepositoryProvider.overrideWithValue(repo)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('포스트'), findsWidgets);
    expect(find.text('[Test] 첫 글'), findsOneWidget);

    // 글 열기
    await tester.tap(find.text('[Test] 첫 글'));
    await tester.pumpAndSettle();
    expect(find.text('블로그 블록'), findsOneWidget);
    expect(find.text('Reference'), findsOneWidget);

    // 새 글: 제목 없이 저장하면 막힌다
    await tester.tap(find.byTooltip('새 글'));
    await tester.pumpAndSettle();
    expect(find.text('제목을 입력하세요'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '제목을 입력하세요'), '두 번째 글');
    await tester.tap(find.text('커밋'));
    await tester.pumpAndSettle();

    expect(repo.files.keys.any((k) => k.endsWith('-두 번째 글.md')), isTrue);
    final saved = repo.files.entries.firstWhere((e) => e.key.endsWith('-두 번째 글.md')).value;
    expect(saved, contains('published: true'));
    expect(saved, contains('title: "두 번째 글"'));
  });

  testWidgets('좁은 화면에서는 하단 탭과 목록만 보인다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 860));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [blogRepositoryProvider.overrideWithValue(FakeRepository())],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('[Test] 첫 글'), findsOneWidget);
    expect(find.text('새 글'), findsOneWidget);
  });
}
