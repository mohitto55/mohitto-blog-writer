import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 텍스트 편집기 동작을 `TextEditingValue` 위의 순수 함수로 구현한다.
///
/// 모든 함수는 새 값을 돌려주며 컨트롤러는 건드리지 않는다.
class EditorActions {
  EditorActions._();

  static const String indentUnit = '  ';

  static TextSelection _normalized(TextEditingValue v) {
    final sel = v.selection;
    if (!sel.isValid) {
      return TextSelection.collapsed(offset: v.text.length);
    }
    return TextSelection(baseOffset: sel.start, extentOffset: sel.end);
  }

  // ---------------------------------------------------------------------------
  // Inline wrapping
  // ---------------------------------------------------------------------------

  /// 선택 영역을 [prefix]/[suffix]로 감싼다. 선택이 없으면 [placeholder]를 넣고 선택한다.
  /// 이미 감싸져 있으면 감싸기를 해제한다 (토글).
  static TextEditingValue wrap(
    TextEditingValue v,
    String prefix,
    String suffix, {
    String placeholder = '텍스트',
    bool toggle = true,
  }) {
    final sel = _normalized(v);
    final text = v.text;
    final selected = text.substring(sel.start, sel.end);

    // 1) 선택 텍스트 자체가 prefix..suffix 로 둘러싸인 경우 → 해제
    if (toggle &&
        selected.length >= prefix.length + suffix.length &&
        selected.startsWith(prefix) &&
        selected.endsWith(suffix)) {
      final inner = selected.substring(prefix.length, selected.length - suffix.length);
      return TextEditingValue(
        text: text.replaceRange(sel.start, sel.end, inner),
        selection: TextSelection(baseOffset: sel.start, extentOffset: sel.start + inner.length),
      );
    }

    // 2) 선택 바깥이 prefix..suffix 인 경우 → 해제
    if (toggle &&
        sel.start >= prefix.length &&
        sel.end + suffix.length <= text.length &&
        text.substring(sel.start - prefix.length, sel.start) == prefix &&
        text.substring(sel.end, sel.end + suffix.length) == suffix) {
      final newText = text.replaceRange(sel.end, sel.end + suffix.length, '') // suffix 먼저
          .replaceRange(sel.start - prefix.length, sel.start, '');
      return TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start - prefix.length,
          extentOffset: sel.end - prefix.length,
        ),
      );
    }

    // 3) 감싸기
    final inner = selected.isEmpty ? placeholder : selected;
    final replacement = '$prefix$inner$suffix';
    final newText = text.replaceRange(sel.start, sel.end, replacement);
    final innerStart = sel.start + prefix.length;
    return TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: innerStart, extentOffset: innerStart + inner.length),
    );
  }

  /// 선택 영역을 [prefix]/[suffix]로 감싸되 토글하지 않는다 (HTML 태그 등).
  static TextEditingValue surround(TextEditingValue v, String prefix, String suffix,
      {String placeholder = '텍스트'}) {
    return wrap(v, prefix, suffix, placeholder: placeholder, toggle: false);
  }

  /// 커서 위치에 텍스트를 삽입한다 (선택 영역은 대체).
  static TextEditingValue insert(TextEditingValue v, String text, {int? cursorOffset}) {
    final sel = _normalized(v);
    final newText = v.text.replaceRange(sel.start, sel.end, text);
    final cursor = sel.start + (cursorOffset ?? text.length);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, newText.length)),
    );
  }

  // ---------------------------------------------------------------------------
  // Line helpers
  // ---------------------------------------------------------------------------

  static int lineStart(String text, int offset) {
    final idx = text.lastIndexOf('\n', math.max(0, offset - 1));
    if (offset == 0) return 0;
    return idx < 0 ? 0 : idx + 1;
  }

  static int lineEnd(String text, int offset) {
    final idx = text.indexOf('\n', offset);
    return idx < 0 ? text.length : idx;
  }

  /// 선택 영역이 걸친 모든 줄의 [start, end) 범위
  static (int, int) selectedLinesRange(TextEditingValue v) {
    final sel = _normalized(v);
    final start = lineStart(v.text, sel.start);
    // 선택 끝이 줄 시작에 정확히 걸쳐 있으면 그 줄은 제외
    final endAnchor = (sel.end > sel.start && sel.end > 0 && v.text[sel.end - 1] == '\n')
        ? sel.end - 1
        : sel.end;
    final end = lineEnd(v.text, endAnchor);
    return (start, end);
  }

  /// 선택된 줄들을 [transform]으로 바꾼다. 선택 영역은 바뀐 줄 전체로 확장된다.
  static TextEditingValue mapSelectedLines(
    TextEditingValue v,
    String Function(String line) transform, {
    bool selectAll = true,
  }) {
    final (start, end) = selectedLinesRange(v);
    final block = v.text.substring(start, end);
    final lines = block.split('\n').map(transform).toList();
    final replaced = lines.join('\n');
    final newText = v.text.replaceRange(start, end, replaced);

    if (selectAll && v.selection.isValid && !v.selection.isCollapsed) {
      return TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: start, extentOffset: start + replaced.length),
      );
    }
    // 커서만 있는 경우 원래 위치를 최대한 유지
    final delta = replaced.length - block.length;
    final cursor = (_normalized(v).start + delta).clamp(start, start + replaced.length);
    return TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: cursor));
  }

  /// 제목 레벨 토글. 같은 레벨이면 제거, 다르면 교체.
  static TextEditingValue toggleHeading(TextEditingValue v, int level) {
    final marker = '${'#' * level} ';
    return mapSelectedLines(v, (line) {
      final m = RegExp(r'^(#{1,6})\s+').firstMatch(line);
      if (m != null) {
        final rest = line.substring(m.end);
        return m.group(1)!.length == level ? rest : '$marker$rest';
      }
      return '$marker$line';
    });
  }

  /// 줄 접두어 토글 (`- `, `> `, `1. ` 등).
  static TextEditingValue toggleLinePrefix(
    TextEditingValue v,
    String prefix, {
    RegExp? matcher,
    bool numbered = false,
  }) {
    final match = matcher ?? RegExp('^\\s*${RegExp.escape(prefix)}');
    final (start, end) = selectedLinesRange(v);
    final block = v.text.substring(start, end);
    final lines = block.split('\n');
    final allHave = lines.where((l) => l.trim().isNotEmpty).every(match.hasMatch);

    var n = 0;
    return mapSelectedLines(v, (line) {
      if (allHave) {
        return line.replaceFirst(match, '');
      }
      if (line.trim().isEmpty) return line;
      final indentMatch = RegExp(r'^\s*').firstMatch(line)!;
      final indent = indentMatch.group(0)!;
      final rest = line.substring(indent.length);
      if (numbered) {
        n++;
        return '$indent$n. $rest';
      }
      return '$indent$prefix$rest';
    });
  }

  static TextEditingValue toggleBulletList(TextEditingValue v) =>
      toggleLinePrefix(v, '- ', matcher: RegExp(r'^\s*[-*+]\s+'));

  static TextEditingValue toggleNumberedList(TextEditingValue v) =>
      toggleLinePrefix(v, '1. ', matcher: RegExp(r'^\s*\d+\.\s+'), numbered: true);

  static TextEditingValue toggleTaskList(TextEditingValue v) =>
      toggleLinePrefix(v, '- [ ] ', matcher: RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s+'));

  static TextEditingValue toggleQuote(TextEditingValue v) =>
      toggleLinePrefix(v, '> ', matcher: RegExp(r'^\s*>\s?'));

  // ---------------------------------------------------------------------------
  // Block insertion
  // ---------------------------------------------------------------------------

  /// 블록 텍스트를 커서 위치에 "자기 줄"로 삽입한다.
  ///
  /// [selectionInBlock]이 있으면 삽입된 블록 안의 해당 범위를 선택한다.
  static TextEditingValue insertBlock(
    TextEditingValue v,
    String block, {
    TextRange? selectionInBlock,
    bool blankLineAround = true,
  }) {
    final sel = _normalized(v);
    final text = v.text;
    final before = text.substring(0, sel.start);
    final after = text.substring(sel.end);

    var prefix = '';
    if (before.isNotEmpty && !before.endsWith('\n')) {
      prefix = '\n';
    }
    if (blankLineAround && before.isNotEmpty && !before.endsWith('\n\n') && !before.endsWith('\n')) {
      prefix = '\n\n';
    } else if (blankLineAround && before.endsWith('\n') && !before.endsWith('\n\n') && before.trim().isNotEmpty) {
      prefix = '\n';
    }

    var suffix = '';
    if (after.isNotEmpty && !after.startsWith('\n')) {
      suffix = blankLineAround ? '\n\n' : '\n';
    } else if (blankLineAround && after.startsWith('\n') && !after.startsWith('\n\n')) {
      suffix = '\n';
    } else if (after.isEmpty) {
      suffix = '\n';
    }

    final inserted = '$prefix$block$suffix';
    final newText = text.replaceRange(sel.start, sel.end, inserted);
    final blockStart = sel.start + prefix.length;

    if (selectionInBlock != null) {
      return TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: blockStart + selectionInBlock.start,
          extentOffset: blockStart + selectionInBlock.end,
        ),
      );
    }
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: blockStart + block.length),
    );
  }

  /// 선택 텍스트를 코드 펜스로 감싼다.
  static TextEditingValue codeFence(TextEditingValue v, {String language = ''}) {
    final sel = _normalized(v);
    final selected = v.text.substring(sel.start, sel.end);
    final body = selected.isEmpty ? '' : selected;
    final block = '```$language\n$body\n```';
    final cursorLine = '```$language\n'.length;
    return insertBlock(
      v,
      block,
      selectionInBlock: TextRange(start: cursorLine, end: cursorLine + body.length),
    );
  }

  // ---------------------------------------------------------------------------
  // Keyboard behaviours
  // ---------------------------------------------------------------------------

  static final RegExp _listMarker = RegExp(r'^(\s*)([-*+]\s+(?:\[[ xX]\]\s+)?|\d+\.\s+|>\s?)');

  /// Enter: 목록/인용 마커를 다음 줄로 이어간다. 빈 항목이면 마커를 제거한다.
  ///
  /// [paragraphBreak] 가 true 면 일반 문장에서 Enter 는 새 문단(빈 줄 포함)을 만든다.
  /// kramdown 은 줄바꿈 하나를 띄어쓰기로 보기 때문에, 블로그에서 보이는 줄바꿈은 빈 줄이어야 한다.
  static TextEditingValue handleEnter(TextEditingValue v, {bool paragraphBreak = false}) {
    final sel = _normalized(v);
    final text = v.text;
    final ls = lineStart(text, sel.start);
    final line = text.substring(ls, sel.start);
    final m = _listMarker.firstMatch(line);

    if (m != null) {
      final indent = m.group(1)!;
      var marker = m.group(2)!;
      final content = line.substring(m.end);

      // 내용이 없는 항목에서 Enter → 목록 종료
      if (content.trim().isEmpty) {
        final newText = text.replaceRange(ls, sel.end, indent);
        return TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: ls + indent.length),
        );
      }

      final num = RegExp(r'^(\d+)\.\s+').firstMatch(marker);
      if (num != null) {
        marker = '${int.parse(num.group(1)!) + 1}. ';
      } else if (RegExp(r'^[-*+]\s+\[[ xX]\]\s+').hasMatch(marker)) {
        marker = marker.replaceFirst(RegExp(r'\[[ xX]\]'), '[ ]');
      }
      return insert(v, '\n$indent$marker');
    }

    // 일반 줄: 들여쓰기 유지
    final indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
    if (paragraphBreak) {
      final isTableRow = line.trimLeft().startsWith('|');
      final after = text.substring(sel.end);
      if (line.trim().isNotEmpty && !isTableRow && indent.isEmpty) {
        // 뒤에 이미 빈 줄이 있으면 하나만 추가
        return insert(v, after.startsWith('\n\n') ? '\n' : '\n\n');
      }
    }
    return insert(v, '\n$indent');
  }

  /// Shift+Enter: 블로그에서 실제로 줄이 바뀌는 `<br>` 하드 브레이크
  static TextEditingValue hardBreak(TextEditingValue v) => insert(v, '<br>\n');

  /// Tab: 선택이 여러 줄이면 모두 들여쓰기, 아니면 공백 삽입
  static TextEditingValue indent(TextEditingValue v) {
    final sel = _normalized(v);
    final multiLine = !sel.isCollapsed && v.text.substring(sel.start, sel.end).contains('\n');
    final onListLine = _listMarker.hasMatch(v.text.substring(lineStart(v.text, sel.start), lineEnd(v.text, sel.start)));
    if (multiLine || onListLine) {
      return mapSelectedLines(v, (line) => line.isEmpty ? line : '$indentUnit$line');
    }
    return insert(v, indentUnit);
  }

  /// Shift+Tab: 선택된 줄 내어쓰기
  static TextEditingValue outdent(TextEditingValue v) {
    return mapSelectedLines(v, (line) {
      if (line.startsWith(indentUnit)) return line.substring(indentUnit.length);
      if (line.startsWith('\t')) return line.substring(1);
      if (line.startsWith(' ')) return line.substring(1);
      return line;
    });
  }

  /// Alt+Up/Down: 선택된 줄들을 위/아래로 이동
  static TextEditingValue moveLines(TextEditingValue v, {required bool up}) {
    final text = v.text;
    final (start, end) = selectedLinesRange(v);
    final sel = _normalized(v);

    if (up) {
      if (start == 0) return v;
      final prevStart = lineStart(text, start - 1);
      final prevLine = text.substring(prevStart, start - 1);
      final block = text.substring(start, end);
      final newText = text.replaceRange(prevStart, end, '$block\n$prevLine');
      final shift = -(prevLine.length + 1);
      return TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: sel.start + shift, extentOffset: sel.end + shift),
      );
    } else {
      if (end >= text.length) return v;
      final nextEnd = lineEnd(text, end + 1);
      final nextLine = text.substring(end + 1, nextEnd);
      final block = text.substring(start, end);
      final newText = text.replaceRange(start, nextEnd, '$nextLine\n$block');
      final shift = nextLine.length + 1;
      return TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: sel.start + shift, extentOffset: sel.end + shift),
      );
    }
  }

  /// 현재 줄 복제 (Ctrl+Shift+D)
  static TextEditingValue duplicateLines(TextEditingValue v) {
    final (start, end) = selectedLinesRange(v);
    final block = v.text.substring(start, end);
    final newText = v.text.replaceRange(end, end, '\n$block');
    final sel = _normalized(v);
    final shift = block.length + 1;
    return TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: sel.start + shift, extentOffset: sel.end + shift),
    );
  }

  /// 커서의 (줄, 열) — 1부터 시작
  static (int, int) cursorPosition(TextEditingValue v) {
    final sel = _normalized(v);
    final before = v.text.substring(0, sel.extentOffset.clamp(0, v.text.length));
    final line = '\n'.allMatches(before).length + 1;
    final col = before.length - lineStart(before, before.length) + 1;
    return (line, col);
  }
}
