import 'package:flutter/widgets.dart';

import '../../models/jekyll_theme.dart';
import 'editor_actions.dart';

/// 툴바 버튼 하나가 수행하는 편집 동작.
typedef SnippetApply = TextEditingValue Function(TextEditingValue value);

/// 지킬 블로그 폴더에서 발견한 커스텀 태그를 에디터 스니펫으로 만든다.
class EditorSnippets {
  EditorSnippets._();

  /// 색상 팔레트 (선택 텍스트를 `<span style="color:…">` 로 감싼다)
  static const List<PaletteColor> textColors = [
    PaletteColor('빨강', Color(0xFFE53935)),
    PaletteColor('주황', Color(0xFFF57C00)),
    PaletteColor('노랑', Color(0xFFC8A600)),
    PaletteColor('초록', Color(0xFF34AD7D)),
    PaletteColor('민트', Color(0xFF11999E)),
    PaletteColor('파랑', Color(0xFF1E88E5)),
    PaletteColor('남색', Color(0xFF253047)),
    PaletteColor('보라', Color(0xFF8E24AA)),
    PaletteColor('분홍', Color(0xFFD81B60)),
    PaletteColor('회색', Color(0xFF757575)),
  ];

  static const List<PaletteColor> highlightColors = [
    PaletteColor('노랑 형광', Color(0xFFFFF59D)),
    PaletteColor('초록 형광', Color(0xFFC8E6C9)),
    PaletteColor('파랑 형광', Color(0xFFBBDEFB)),
    PaletteColor('분홍 형광', Color(0xFFF8BBD0)),
    PaletteColor('회색 형광', Color(0xFFE0E0E0)),
  ];

  static String hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  static TextEditingValue textColor(TextEditingValue v, Color color) {
    return EditorActions.surround(v, '<span style="color:${hex(color)}">', '</span>');
  }

  static TextEditingValue highlight(TextEditingValue v, Color color) {
    return EditorActions.surround(v, '<span style="background-color:${hex(color)}">', '</span>');
  }

  static TextEditingValue mark(TextEditingValue v) {
    return EditorActions.wrap(v, '<mark>', '</mark>');
  }

  static TextEditingValue underline(TextEditingValue v) {
    return EditorActions.wrap(v, '<u>', '</u>');
  }

  // ---------------------------------------------------------------------------
  // 블로그 커스텀 블록 (SCSS 에서 발견한 클래스 기반)
  // ---------------------------------------------------------------------------

  /// 콜아웃/Reference 블록 삽입. 선택 텍스트가 있으면 본문으로 사용한다.
  static TextEditingValue calloutBlock(TextEditingValue v, BlogBlockStyle style) {
    final sel = v.selection.isValid
        ? TextSelection(baseOffset: v.selection.start, extentOffset: v.selection.end)
        : const TextSelection.collapsed(offset: 0);
    final selected = v.text.substring(sel.start, sel.end).trim();

    if (style.isReference) {
      return referenceBlock(v, url: selected);
    }

    final bodyText = selected.isEmpty ? '내용' : selected.replaceAll('\n', '<br>\n');
    final quote = style.className.contains('-expanded') ? "'" : '"';

    if (style.hasHeader) {
      final header = style.autoHeaderText == null ? '제목' : ' ';
      final block = "<div class=$quote${style.className}$quote>\n"
          "<div class=${quote}callout-header$quote>$header</div>\n"
          '<p>\n'
          '$bodyText\n'
          '</p>\n'
          '</div>';
      // 헤더 텍스트를 선택 상태로
      final headerStart = "<div class=$quote${style.className}$quote>\n<div class=${quote}callout-header$quote>".length;
      final cleared = _replaceSelection(v, sel, '');
      return EditorActions.insertBlock(
        cleared,
        block,
        selectionInBlock: TextRange(start: headerStart, end: headerStart + header.length),
      );
    }

    final block = "<div class=$quote${style.className}$quote>\n"
        '<p>\n'
        '$bodyText\n'
        '</p>\n'
        '</div>';
    final bodyStart = "<div class=$quote${style.className}$quote>\n<p>\n".length;
    final cleared = _replaceSelection(v, sel, '');
    return EditorActions.insertBlock(
      cleared,
      block,
      selectionInBlock: TextRange(start: bodyStart, end: bodyStart + bodyText.length),
    );
  }

  /// Reference (참고 링크) 블록
  static TextEditingValue referenceBlock(TextEditingValue v, {String url = ''}) {
    final sel = v.selection.isValid
        ? TextSelection(baseOffset: v.selection.start, extentOffset: v.selection.end)
        : const TextSelection.collapsed(offset: 0);
    var link = url.trim();
    if (link.isEmpty) {
      // 선택한 텍스트가 URL 이면 그대로 링크로 사용
      final selectedText = v.text.substring(sel.start, sel.end).trim();
      if (RegExp(r'^https?://\S+$').hasMatch(selectedText)) link = selectedText;
    }
    final block = '<div class="Reference">\n'
        '<div class="callout-header"> </div>\n'
        '<p>\n'
        '<a href="$link">$link</a>\n'
        '</p>\n'
        '</div>';
    final urlStart = '<div class="Reference">\n<div class="callout-header"> </div>\n<p>\n<a href="'.length;
    final cleared = _replaceSelection(v, sel, '');
    return EditorActions.insertBlock(
      cleared,
      block,
      selectionInBlock: TextRange(start: urlStart, end: urlStart + link.length),
    );
  }

  /// 기존 Reference 블록에 링크를 한 줄 추가한다. 블록이 없으면 새로 만든다.
  static String appendReferenceLink(String body, String url) {
    final link = url.trim();
    final pattern = RegExp(
      r'''(<div class=["']Reference["']>[\s\S]*?<p>)([\s\S]*?)(</p>[\s\S]*?</div>)''',
    );
    final m = pattern.firstMatch(body);
    if (m != null) {
      final existing = m.group(2)!;
      final trimmed = existing.trimRight();
      final hasEmptyAnchor = RegExp(r'<a href=""></a>').hasMatch(trimmed);
      final newInner = hasEmptyAnchor
          ? trimmed.replaceFirst(RegExp(r'<a href=""></a>'), '<a href="$link">$link</a>')
          : '$trimmed\n<a href="$link">$link</a>';
      return body.replaceRange(m.start, m.end, '${m.group(1)!}$newInner\n${m.group(3)!}');
    }
    final block = '\n\n<div class="Reference">\n'
        '<div class="callout-header"> </div>\n'
        '<p>\n'
        '<a href="$link">$link</a>\n'
        '</p>\n'
        '</div>\n';
    return body.trimRight() + block;
  }

  /// 예제 입력/출력 나란히 보여주는 코드 비교 블록 (`code-block1` / `code-block2`)
  static TextEditingValue codeCompareBlock(TextEditingValue v, {String language = 'cpp'}) {
    String one(String cls, String label) => '<div class="$cls">\n'
        '$label\n'
        '<div class="language-$language highlighter-rouge"><div class="highlight"><pre class="highlight">\n'
        '<code></code></pre></div></div></div>';
    final block = '${one('code-block1', '예제 입력')}\n\n${one('code-block2', '예제 출력')}';
    final firstCode = block.indexOf('<code>') + '<code>'.length;
    return EditorActions.insertBlock(
      v,
      block,
      selectionInBlock: TextRange(start: firstCode, end: firstCode),
    );
  }

  // ---------------------------------------------------------------------------
  // 일반 마크다운
  // ---------------------------------------------------------------------------

  static TextEditingValue bold(TextEditingValue v) => EditorActions.wrap(v, '**', '**', placeholder: '굵게');
  static TextEditingValue italic(TextEditingValue v) => EditorActions.wrap(v, '*', '*', placeholder: '기울임');
  static TextEditingValue strike(TextEditingValue v) => EditorActions.wrap(v, '~~', '~~', placeholder: '취소선');
  static TextEditingValue inlineCode(TextEditingValue v) => EditorActions.wrap(v, '`', '`', placeholder: 'code');

  static TextEditingValue link(TextEditingValue v, {String url = ''}) {
    final sel = v.selection.isValid
        ? TextSelection(baseOffset: v.selection.start, extentOffset: v.selection.end)
        : const TextSelection.collapsed(offset: 0);
    final selected = v.text.substring(sel.start, sel.end);
    final looksLikeUrl = RegExp(r'^https?://').hasMatch(selected.trim());
    final label = looksLikeUrl || selected.isEmpty ? '링크 텍스트' : selected;
    final href = looksLikeUrl ? selected.trim() : url;
    final text = '[$label]($href)';
    final replaced = _replaceSelection(v, sel, text);
    if (looksLikeUrl || selected.isEmpty) {
      // 라벨 선택
      return replaced.copyWith(
        selection: TextSelection(baseOffset: sel.start + 1, extentOffset: sel.start + 1 + label.length),
      );
    }
    // URL 위치에 커서
    final urlPos = sel.start + '[$label]('.length;
    return replaced.copyWith(
      selection: TextSelection(baseOffset: urlPos, extentOffset: urlPos + href.length),
    );
  }

  static TextEditingValue image(TextEditingValue v, {required String src, String alt = ''}) {
    return EditorActions.insert(v, '![$alt]($src)');
  }

  static TextEditingValue table(TextEditingValue v, {int columns = 3, int rows = 2}) {
    final header = '| ${List.generate(columns, (i) => '열 ${i + 1}').join(' | ')} |';
    final sep = '|${List.filled(columns, ' --- ').join('|')}|';
    final body = List.generate(rows, (_) => '|${List.filled(columns, '     ').join('|')}|').join('\n');
    return EditorActions.insertBlock(v, '$header\n$sep\n$body',
        selectionInBlock: const TextRange(start: 2, end: 5));
  }

  static TextEditingValue horizontalRule(TextEditingValue v) => EditorActions.insertBlock(v, '---');

  static TextEditingValue lineBreak(TextEditingValue v) => EditorActions.insert(v, '<br>');

  static TextEditingValue _replaceSelection(TextEditingValue v, TextSelection sel, String text) {
    final newText = v.text.replaceRange(sel.start, sel.end, text);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
  }
}

class PaletteColor {
  final String name;
  final Color color;
  const PaletteColor(this.name, this.color);
}
