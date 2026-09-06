import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_github_publisher/services/jekyll_theme_service.dart';
import 'package:obsidian_github_publisher/services/local_blog_repository.dart';
import 'package:path/path.dart' as p;

const _scss = r'''
// 콜아웃
.callout {
  p{ // 콜아웃 내부 텍스트
    padding-left: 5px;
  }
}
.callout-red{
  @extend .callout;
  border-color: rgb(180, 0, 0);
  background-color: rgb(255, 216, 216);
}
.callout-expanded{
  @extend .callout;
  p{ padding: 15px; }
}
.callout-header{
  position: relative;
}
.callout-header::before{
  content:"";
}
.callout-info-expanded{
  @extend .callout-expanded;
  background-color: #fcfcfc;
  border-color: #48b3e4;
  .callout-header{
    background-color: #48b3e4;
    color: #f3f3f3;
  }
  .callout-header::before{
    background-image: url('images/info.png');
  }
}
.Reference{
  @extend .callout-expanded;
  background-color: rgba(248, 248, 248, 0.829);
  border-color: #5e6969;
  .callout-header{
    background-color: #5e6969;
    color: rgb(238, 238, 238);
  }
  .callout-header::after{
    content: "Reference";
  }
  a { display: block; }
}
.code-block1{ width: 45%; }
.code-block2{ width: 45%; }
''';

void main() {
  late Directory blog;

  setUp(() async {
    blog = await Directory.systemTemp.createTemp('blog_test_');
    await File(p.join(blog.path, '_config.yml')).writeAsString(
      'minimal_mistakes_skin    : "mint" # skin\nlocale: "ko-KR"\nurl: "https://mohitto55.github.io"\nbaseurl: # "/blog"\npermalink: /:categories/:title/\n',
    );
    final sass = Directory(p.join(blog.path, '_sass', 'minimal-mistakes'));
    await Directory(p.join(sass.path, 'skins')).create(recursive: true);
    await File(p.join(sass.path, '_base.scss')).writeAsString(_scss);
    await File(p.join(sass.path, '_variables.scss')).writeAsString(r'$mohitto-color: #34AD7D;');
    await File(p.join(sass.path, 'skins', '_mint.scss')).writeAsString(
      r'$background-color: #f3f6f6 !default;' '\n' r'$text-color: #40514e !default;' '\n' r'$primary-color: #11999e !default;',
    );

    final categories = Directory(p.join(blog.path, '_pages', 'categories'));
    await categories.create(recursive: true);
    await File(p.join(categories.path, 'c++.md')).writeAsString('---\ntitle: "C++"\nlayout: archive\npermalink: /cpp\n---\n');
    await File(p.join(categories.path, 'ue5.md')).writeAsString('---\ntitle: "UE5"\npermalink: /ue5\n---\n');

    final posts = Directory(p.join(blog.path, '_posts'));
    await posts.create();
    await File(p.join(posts.path, '2024-01-01-a.md')).writeAsString('---\ntitle : "[A] a"\ncategories: cpp\ntags: [C++, Git]\n---\n본문');
    await File(p.join(posts.path, 'm2024-01-02-b.md')).writeAsString('---\ntitle : "[B] b"\ncategories: unity\ntags: [Git]\n---\n본문');
    await File(p.join(posts.path, 'z템플릿.md')).writeAsString('---\ntitle : "[] "\ncategories: \ntags: []\n---\n\n\n<div class="Reference">\n</div>');
  });

  tearDown(() async {
    await blog.delete(recursive: true);
  });

  test('SCSS 에서 콜아웃 클래스와 색상을 읽는다', () async {
    final theme = await JekyllThemeService(repository: LocalBlogRepository(blogPath: blog.path)).scan();

    final names = theme.blockStyles.map((s) => s.className).toList();
    expect(names, containsAll(['callout-red', 'callout-info-expanded', 'Reference']));
    expect(names, isNot(contains('callout-header')));
    expect(names, isNot(contains('callout-expanded')));

    final red = theme.styleFor('callout-red')!;
    expect(red.hasHeader, isFalse);
    expect(red.borderColor, const Color(0xFFB40000));
    expect(red.backgroundColor, const Color(0xFFFFD8D8));

    final info = theme.styleFor('callout-info-expanded')!;
    expect(info.hasHeader, isTrue);
    expect(info.borderColor, const Color(0xFF48B3E4));
    expect(info.headerBackground, const Color(0xFF48B3E4));
    expect(info.headerTextColor, const Color(0xFFF3F3F3));
    expect(info.label, 'Info');

    final ref = theme.styleFor('Reference')!;
    expect(ref.autoHeaderText, 'Reference');
    expect(ref.headerBackground, const Color(0xFF5E6969));

    expect(theme.hasCodeCompareBlocks, isTrue);
    // 헤더 있는 블록이 먼저 온다
    expect(theme.blockStyles.first.hasHeader, isTrue);
  });

  test('스킨, 카테고리, 태그, 템플릿을 읽는다', () async {
    final theme = await JekyllThemeService(repository: LocalBlogRepository(blogPath: blog.path)).scan();

    expect(theme.skin.name, 'mint');
    expect(theme.skin.primary, const Color(0xFF11999E));
    expect(theme.skin.accent, const Color(0xFF34AD7D));
    expect(theme.permalinkPattern, '/:categories/:title/');
    expect(theme.siteUrl, 'https://mohitto55.github.io');

    expect(theme.categories.map((c) => c.slug), ['cpp', 'ue5', 'unity']);
    expect(theme.categories.first.title, 'C++');

    // 빈도순 → 이름순
    expect(theme.tags, ['Git', 'C++']);

    expect(theme.templates.length, 1);
    expect(theme.templates.first.name, 'z템플릿');
    expect(JekyllThemeService.templateDisplayName('템플릿 - 개념 정리.md'), '개념 정리');
    expect(JekyllThemeService.templateDisplayName('문제풀이 템플릿.md'), '문제풀이');
    expect(theme.templates.first.body, startsWith('<div class="Reference">'));
  });

  test('블로그 폴더가 없으면 기본 테마를 준다', () async {
    final theme = await JekyllThemeService(repository: LocalBlogRepository(blogPath: p.join(blog.path, 'nope'))).scan();
    expect(theme.blockStyles, isNotEmpty);
    expect(theme.categories, isEmpty);
  });
}
