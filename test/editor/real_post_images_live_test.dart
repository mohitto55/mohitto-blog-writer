import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_github_publisher/models/jekyll_post.dart';
import 'package:obsidian_github_publisher/models/jekyll_theme.dart';
import 'package:obsidian_github_publisher/ui/editor/blog_preview.dart';
import 'package:obsidian_github_publisher/ui/editor/live_preview_editor.dart';

/// 실제 포스트 + 실제 네트워크로 미리보기/라이브 편집기의 이미지 로딩을 재현한다 (진단용)
/// flutter test test/editor/real_post_images_live_test.dart --dart-define=LIVE=true
void main() {
  const live = bool.fromEnvironment('LIVE');
  const postPath = r'C:\Users\admin\git\blog\_posts\2025-12-02-[AWS] VPC 알아보기.md';

  Future<void> check(WidgetTester tester, Widget Function(String body) build) async {
    HttpOverrides.global = null;
    final body = JekyllPost.parse(File(postPath).readAsStringSync()).body;
    final expected = RegExp(r'!\[[^\]]*\]\(https?://[^)]+\)').allMatches(body).length;
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: build(body))));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 8)));
    await tester.pump();
    final images = find.byType(Image).evaluate().length;
    final broken = find.textContaining('불러오지 못했습니다').evaluate().length;
    // ignore: avoid_print
    print('markdown images=$expected, Image widgets=$images, broken=$broken');
    expect(broken, 0);
    expect(images, greaterThan(0));
  }

  testWidgets('BlogPreview 에서 실제 포스트 이미지가 로드된다', (tester) async {
    await check(tester, (body) => BlogPreview(markdown: body, theme: JekyllTheme.fallback(r'C:\Users\admin\git\blog')));
  }, skip: !live);

  testWidgets('LivePreviewEditor 에서 실제 포스트 이미지가 로드된다', (tester) async {
    late TextEditingController c;
    await check(tester, (body) {
      c = TextEditingController(text: body);
      return LivePreviewEditor(document: c, theme: JekyllTheme.fallback(r'C:\Users\admin\git\blog'));
    });
  }, skip: !live);
}
