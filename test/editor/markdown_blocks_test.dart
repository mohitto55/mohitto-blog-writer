import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_github_publisher/ui/editor/markdown_blocks.dart';

void main() {
  test('문단, 제목, 코드, html, 구분선, br 을 블록으로 나눈다', () {
    const doc = '# 제목\n'
        '첫 문단 첫 줄\n'
        '첫 문단 둘째 줄\n'
        '\n'
        '```cpp\n'
        'int a;\n'
        '\n'
        '```\n'
        '\n'
        "<div class='callout-info-expanded'>\n"
        "<div class='callout-header'>h</div>\n"
        '<p>\n'
        '내용\n'
        '</p>\n'
        '</div>\n'
        '\n'
        '---\n'
        '<br>\n'
        '- a\n'
        '- b';

    final blocks = MarkdownBlocks.split(doc);
    expect(blocks.map((b) => b.type).toList(), [
      MdBlockType.heading,
      MdBlockType.paragraph,
      MdBlockType.code,
      MdBlockType.html,
      MdBlockType.hr,
      MdBlockType.br,
      MdBlockType.paragraph,
    ]);
    expect(blocks[0].text, '# 제목');
    expect(blocks[0].headingLevel, 1);
    expect(blocks[1].text, '첫 문단 첫 줄\n첫 문단 둘째 줄');
    expect(blocks[2].text, '```cpp\nint a;\n\n```');
    expect(blocks[3].htmlClassName, 'callout-info-expanded');
    expect(blocks[3].text, endsWith('</div>'));
    expect(blocks[6].text, '- a\n- b');

    // 오프셋이 원문과 일치한다
    for (final b in blocks) {
      expect(doc.substring(b.start, b.end), b.text);
    }
  });

  test('닫히지 않은 코드 펜스는 끝까지 한 블록', () {
    final blocks = MarkdownBlocks.split('```\nabc\ndef');
    expect(blocks.length, 1);
    expect(blocks.first.type, MdBlockType.code);
  });

  test('CRLF 문서도 처리한다', () {
    final blocks = MarkdownBlocks.split('a\r\n\r\nb');
    expect(blocks.map((b) => b.text).toList(), ['a', 'b']);
  });

  test('indexAt / withVirtualAt', () {
    const doc = 'aa\n\nbb';
    final blocks = MarkdownBlocks.split(doc);
    expect(MarkdownBlocks.indexAt(blocks, 1), 0);
    expect(MarkdownBlocks.indexAt(blocks, 2), 0); // 블록 끝 포함
    expect(MarkdownBlocks.indexAt(blocks, 3), -1); // 빈 줄
    expect(MarkdownBlocks.indexAt(blocks, 5), 1);

    final (withVirtual, idx) = MarkdownBlocks.withVirtualAt(blocks, 3);
    expect(idx, 1);
    expect(withVirtual[1].virtual, isTrue);
    expect(withVirtual.length, 3);

    final (atEnd, endIdx) = MarkdownBlocks.withVirtualAt(blocks, 10);
    expect(endIdx, 2);
    expect(atEnd.last.virtual, isTrue);
  });
}
