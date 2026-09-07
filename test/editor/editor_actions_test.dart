import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_github_publisher/models/jekyll_theme.dart';
import 'package:obsidian_github_publisher/ui/editor/editor_actions.dart';
import 'package:obsidian_github_publisher/ui/editor/editor_snippets.dart';

TextEditingValue v(String text, {int? start, int? end}) {
  final s = start ?? text.length;
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: s, extentOffset: end ?? s),
  );
}

String selected(TextEditingValue value) => value.text.substring(value.selection.start, value.selection.end);

void main() {
  group('wrap', () {
    test('선택 텍스트를 감싸고 안쪽을 선택 상태로 둔다', () {
      final r = EditorActions.wrap(v('hello world', start: 0, end: 5), '**', '**');
      expect(r.text, '**hello** world');
      expect(selected(r), 'hello');
    });

    test('선택이 없으면 placeholder 를 넣는다', () {
      final r = EditorActions.wrap(v('abc', start: 3), '**', '**', placeholder: '굵게');
      expect(r.text, 'abc**굵게**');
      expect(selected(r), '굵게');
    });

    test('이미 감싸져 있으면 해제한다 (토글)', () {
      final r = EditorActions.wrap(v('**hello** world', start: 2, end: 7), '**', '**');
      expect(r.text, 'hello world');
      expect(selected(r), 'hello');
    });
  });

  group('headings & lists', () {
    test('제목 토글', () {
      final r1 = EditorActions.toggleHeading(v('제목', start: 0), 2);
      expect(r1.text, '## 제목');
      final r2 = EditorActions.toggleHeading(r1, 2);
      expect(r2.text, '제목');
      final r3 = EditorActions.toggleHeading(r1, 3);
      expect(r3.text, '### 제목');
    });

    test('여러 줄 글머리 기호 토글', () {
      final r = EditorActions.toggleBulletList(v('a\nb\nc', start: 0, end: 5));
      expect(r.text, '- a\n- b\n- c');
      final back = EditorActions.toggleBulletList(r);
      expect(back.text, 'a\nb\nc');
    });

    test('번호 목록은 번호를 매긴다', () {
      final r = EditorActions.toggleNumberedList(v('a\nb', start: 0, end: 3));
      expect(r.text, '1. a\n2. b');
    });
  });

  group('Enter', () {
    test('목록 항목을 이어간다', () {
      final r = EditorActions.handleEnter(v('- 항목'));
      expect(r.text, '- 항목\n- ');
      expect(r.selection.baseOffset, r.text.length);
    });

    test('번호 목록은 다음 번호를 붙인다', () {
      final r = EditorActions.handleEnter(v('3. 항목'));
      expect(r.text, '3. 항목\n4. ');
    });

    test('빈 항목에서 Enter 는 목록을 끝낸다', () {
      final r = EditorActions.handleEnter(v('- a\n- '));
      expect(r.text, '- a\n');
    });

    test('문단 모드: 일반 문장에서 Enter 는 빈 줄로 새 문단을 만든다', () {
      expect(EditorActions.handleEnter(v('첫 문장'), paragraphBreak: true).text, '첫 문장\n\n');
      // 문장 중간에서 나누기
      expect(EditorActions.handleEnter(v('앞뒤', start: 1), paragraphBreak: true).text, '앞\n\n뒤');
      // 뒤에 이미 빈 줄이 있으면 하나만
      expect(EditorActions.handleEnter(v('앞\n\n뒤', start: 1), paragraphBreak: true).text, '앞\n\n\n뒤');
      // 목록/표/빈 줄은 문단 모드여도 그대로
      expect(EditorActions.handleEnter(v('- 항목'), paragraphBreak: true).text, '- 항목\n- ');
      expect(EditorActions.handleEnter(v('| a | b |'), paragraphBreak: true).text, '| a | b |\n');
      expect(EditorActions.handleEnter(v(''), paragraphBreak: true).text, '\n');
      expect(EditorActions.hardBreak(v('a')).text, 'a<br>\n');
    });

    test('일반 줄은 들여쓰기를 유지한다', () {
      final r = EditorActions.handleEnter(v('  code'));
      expect(r.text, '  code\n  ');
    });
  });

  group('indent / move / duplicate', () {
    test('Tab 은 공백을 넣고 여러 줄이면 모두 들여쓴다', () {
      expect(EditorActions.indent(v('ab', start: 1)).text, 'a  b');
      expect(EditorActions.indent(v('a\nb', start: 0, end: 3)).text, '  a\n  b');
      expect(EditorActions.outdent(v('  a\n  b', start: 0, end: 7)).text, 'a\nb');
    });

    test('Alt+↑ 로 줄을 올린다', () {
      final r = EditorActions.moveLines(v('a\nb\nc', start: 2), up: true);
      expect(r.text, 'b\na\nc');
      expect(r.selection.baseOffset, 0);
    });

    test('Alt+↓ 로 줄을 내린다', () {
      final r = EditorActions.moveLines(v('a\nb\nc', start: 0), up: false);
      expect(r.text, 'b\na\nc');
      expect(r.selection.baseOffset, 2);
    });

    test('줄 복제', () {
      expect(EditorActions.duplicateLines(v('a\nb', start: 0)).text, 'a\na\nb');
    });
  });

  group('insertBlock', () {
    test('문단 중간에 넣으면 앞뒤 빈 줄을 확보한다', () {
      final r = EditorActions.insertBlock(v('앞\n뒤', start: 1), '---');
      expect(r.text, '앞\n\n---\n\n뒤');
    });

    test('코드 펜스는 선택 텍스트를 감싼다', () {
      final r = EditorActions.codeFence(v('int a;', start: 0, end: 6), language: 'cpp');
      expect(r.text, '```cpp\nint a;\n```\n');
      expect(selected(r), 'int a;');
    });
  });

  group('snippets (블로그 커스텀 태그)', () {
    const info = BlogBlockStyle(
      className: 'callout-info-expanded',
      label: 'Info',
      borderColor: Color(0xFF48B3E4),
      backgroundColor: Color(0xFFFCFCFC),
      hasHeader: true,
    );
    const red = BlogBlockStyle(
      className: 'callout-red',
      label: 'Red',
      borderColor: Color(0xFFB40000),
      backgroundColor: Color(0xFFFFD8D8),
      hasHeader: false,
    );

    test('글자 색상 span', () {
      final r = EditorSnippets.textColor(v('중요', start: 0, end: 2), const Color(0xFFE53935));
      expect(r.text, '<span style="color:#e53935">중요</span>');
      expect(selected(r), '중요');
    });

    test('확장형 콜아웃은 블로그 템플릿과 같은 모양이고 헤더가 선택된다', () {
      final r = EditorSnippets.calloutBlock(v('설명 문장', start: 0, end: 5), info);
      expect(
        r.text,
        "<div class='callout-info-expanded'>\n"
        "<div class='callout-header'>제목</div>\n"
        '<p>\n'
        '설명 문장\n'
        '</p>\n'
        '</div>\n',
      );
      expect(selected(r), '제목');
    });

    test('단순 콜아웃은 헤더 없이 본문만 넣고 여러 줄은 <br> 로 잇는다', () {
      final r = EditorSnippets.calloutBlock(v('a\nb', start: 0, end: 3), red);
      expect(r.text, '<div class="callout-red">\n<p>\na<br>\nb\n</p>\n</div>\n');
    });

    test('Reference 블록은 선택한 URL 을 링크로 쓴다', () {
      final r = EditorSnippets.referenceBlock(v('https://a.b', start: 0, end: 11));
      expect(r.text, contains('<a href="https://a.b">https://a.b</a>'));
      expect(r.text, startsWith('<div class="Reference">\n<div class="callout-header"> </div>'));
    });

    test('기존 Reference 블록에 링크를 추가한다', () {
      const body = '본문\n\n<div class="Reference">\n<div class="callout-header"> </div>\n<p>\n<a href=""></a>\n</p>\n</div>';
      final r1 = EditorSnippets.appendReferenceLink(body, 'https://one');
      expect(r1, contains('<a href="https://one">https://one</a>'));
      expect(r1, isNot(contains('<a href=""></a>')));
      final r2 = EditorSnippets.appendReferenceLink(r1, 'https://two');
      expect(r2, contains('<a href="https://one">https://one</a>\n<a href="https://two">https://two</a>'));
    });

    test('링크: URL 을 선택하고 실행하면 라벨을 편집하게 한다', () {
      final r = EditorSnippets.link(v('https://x.y', start: 0, end: 11));
      expect(r.text, '[링크 텍스트](https://x.y)');
      expect(selected(r), '링크 텍스트');
    });
  });
}
