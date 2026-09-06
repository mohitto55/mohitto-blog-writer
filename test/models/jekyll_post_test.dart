import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_github_publisher/models/jekyll_post.dart';

void main() {
  group('JekyllPost.parse', () {
    test('블로그 포스트 형식의 frontmatter 를 읽는다', () {
      const raw = '---\n'
          'title : "[C++] C스타일 캐스팅 부터 bit_cast까지"\n'
          'categories: cpp\n'
          'tags: [C++, C, UnrealEngine]\n'
          'toc: true\n'
          '---\n'
          '\n'
          '## 발생과정\n'
          '본문';

      final post = JekyllPost.parse(raw);
      expect(post.subject, 'C++');
      expect(post.title, 'C스타일 캐스팅 부터 bit_cast까지');
      expect(post.fullTitle, '[C++] C스타일 캐스팅 부터 bit_cast까지');
      expect(post.category, 'cpp');
      expect(post.tags, ['C++', 'C', 'UnrealEngine']);
      expect(post.extraFrontmatterLines, ['toc: true']);
      expect(post.body, '## 발생과정\n본문');
    });

    test('빈 categories / tags 를 처리한다', () {
      const raw = '---\ntitle : "[] "\ncategories: \ntags: []\n---\n\n\n본문';
      final post = JekyllPost.parse(raw);
      expect(post.subject, '');
      expect(post.title, '');
      expect(post.category, '');
      expect(post.tags, isEmpty);
    });

    test('frontmatter 가 없으면 전체를 본문으로 본다', () {
      final post = JekyllPost.parse('그냥 글');
      expect(post.body, '그냥 글');
      expect(post.fullTitle, '');
    });
  });

  group('JekyllPost.serialize', () {
    test('title / categories / tags / 추가 키 순서로 쓴다', () {
      final post = JekyllPost(
        subject: 'Jira',
        title: 'Jira 시작하기',
        category: 'jira',
        tags: ['Jira', '협업'],
        body: '본문',
        extraFrontmatterLines: ['toc: true'],
      );
      expect(
        post.serialize(),
        '---\n'
        'title: "[Jira] Jira 시작하기"\n'
        'categories: jira\n'
        'tags: [Jira, 협업]\n'
        'toc: true\n'
        '---\n'
        '\n'
        '본문',
      );
    });

    test('date / published 는 최근 포스트처럼 title 앞에 온다', () {
      final post = JekyllPost(subject: 'AWS', title: 'VPC', category: 'network', tags: ['VPC'], body: '본문');
      post.ensurePublishFields(DateTime(2025, 12, 2));
      expect(
        post.serialize(),
        '---\n'
        'date: 2025-12-02\n'
        'published: true\n'
        'title: "[AWS] VPC"\n'
        'categories: network\n'
        'tags: [VPC]\n'
        '---\n'
        '\n'
        '본문',
      );

      // 템플릿처럼 빈 date 가 있으면 채우고, 기존 값은 유지한다
      final fromTemplate = JekyllPost.parse('---\ndate: \npublished: true\ntitle: "[] "\ncategories: \ntags: []\n---\n\nx');
      fromTemplate.ensurePublishFields(DateTime(2026, 1, 1));
      expect(fromTemplate.extraFrontmatterLines, ['date: 2026-01-01', 'published: true']);

      final existing = JekyllPost.parse('---\ndate: 2024-01-01\ntitle: "a"\n---\nx');
      existing.ensurePublishFields(DateTime(2026, 1, 1));
      expect(existing.extraFrontmatterLines, ['date: 2024-01-01', 'published: true']);
    });

    test('parse → serialize 왕복 시 본문이 보존된다', () {
      const body = '<div class="Reference">\n<div class="callout-header"> </div>\n<p>\n<a href="https://x">https://x</a>\n</p>\n</div>';
      final raw = JekyllPost(subject: 'A', title: 'B', body: body).serialize();
      expect(JekyllPost.parse(raw).body, body);
    });
  });

  group('파일명 규칙', () {
    test('게시 / 초안 / 템플릿을 구분한다', () {
      expect(JekyllPost.isPublishedFileName('2024-03-13-지라사용법.md'), isTrue);
      expect(JekyllPost.isDraftFileName('2024-03-13-지라사용법.md'), isFalse);
      expect(JekyllPost.isDraftFileName('m2024-03-13-지라사용법.md'), isTrue);
      expect(JekyllPost.isPublishedFileName('m2024-03-13-지라사용법.md'), isFalse);
      expect(JekyllPost.isTemplateFileName('z템플릿.md'), isTrue);
      expect(JekyllPost.isTemplateFileName('문제풀이 템플릿.md'), isTrue);
      expect(JekyllPost.isTemplateFileName('2024-03-13-템플릿 사용법.md'), isFalse);
    });

    test('새 파일명을 만든다', () {
      final name = JekyllPost.buildFileName(date: DateTime(2025, 1, 2), fullTitle: '[UE5] 액터: 컴포넌트?');
      expect(name, '2025-01-02-[UE5] 액터 컴포넌트.md');
      expect(JekyllPost.buildFileName(date: DateTime(2025, 1, 2), fullTitle: 'x', draft: true), 'm2025-01-02-x.md');
    });

    test('초안 토글은 m 접두어만 바꾼다', () {
      expect(JekyllPost.toggleDraftFileName('2024-03-13-a.md', draft: true), 'm2024-03-13-a.md');
      expect(JekyllPost.toggleDraftFileName('m2024-03-13-a.md', draft: false), '2024-03-13-a.md');
      expect(JekyllPost.toggleDraftFileName('m2024-03-13-a.md', draft: true), 'm2024-03-13-a.md');
    });

    test('Jekyll 슬러그와 로컬 URL 을 만든다', () {
      expect(JekyllPost.slugFromFileName('2024-12-12-[Geometry]Line Intersection.md'), 'Geometry-Line-Intersection');
      expect(JekyllPost.slugFromFileName('2026-06-05-[Backend] BFF 개념과 서비스 적용에 대한 생각.md'), 'Backend-BFF-개념과-서비스-적용에-대한-생각');
      expect(JekyllPost.slugFromFileName('2024-03-13-시간 복잡도 BigO.md'), '시간-복잡도-BigO');
      expect(
        JekyllPost.localUrlPath(fileName: '2024-03-13-지라사용법.md', category: 'jira'),
        '/jira/지라사용법/',
      );
      expect(
        JekyllPost.localUrlPath(fileName: '2024-03-13-지라사용법.md', category: ''),
        '/지라사용법/',
      );
    });
  });
}
