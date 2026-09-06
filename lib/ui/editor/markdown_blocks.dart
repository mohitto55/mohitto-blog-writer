/// 마크다운 문서를 "편집 단위 블록"으로 나눈다.
///
/// 라이브 편집 모드에서 한 번에 하나의 블록만 원문으로 편집하고 나머지는 렌더링한다.
enum MdBlockType { paragraph, heading, code, html, hr, br }

class MdBlock {
  /// 문서 내 시작 오프셋 (포함)
  final int start;

  /// 문서 내 끝 오프셋 (제외). 블록 뒤의 줄바꿈은 포함하지 않는다.
  final int end;
  final String text;
  final MdBlockType type;

  /// 커서가 블록 사이 빈 공간에 있을 때 만들어지는 가상의 빈 블록
  final bool virtual;

  const MdBlock({
    required this.start,
    required this.end,
    required this.text,
    required this.type,
    this.virtual = false,
  });

  int get length => end - start;

  bool contains(int offset) => offset >= start && offset <= end;

  /// `## 제목` 의 레벨, 제목이 아니면 0
  int get headingLevel {
    if (type != MdBlockType.heading) return 0;
    final m = RegExp(r'^(#{1,6})\s').firstMatch(text);
    return m?.group(1)!.length ?? 0;
  }

  /// `<div class="X">` 의 클래스명
  String? get htmlClassName {
    if (type != MdBlockType.html) return null;
    return RegExp(r'''^\s*<div\s+class=["']([\w-]+)["']''').firstMatch(text)?.group(1);
  }

  MdBlock copyWith({int? start, int? end, String? text, MdBlockType? type, bool? virtual}) {
    return MdBlock(
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      type: type ?? this.type,
      virtual: virtual ?? this.virtual,
    );
  }

  @override
  String toString() => 'MdBlock($type, $start-$end, ${text.length > 20 ? '${text.substring(0, 20)}…' : text})';
}

class MarkdownBlocks {
  MarkdownBlocks._();

  static final RegExp _fence = RegExp(r'^\s*(```|~~~)');
  static final RegExp _divOpen = RegExp(r'^\s*<div\b');
  static final RegExp _heading = RegExp(r'^#{1,6}\s');
  static final RegExp _hr = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
  static final RegExp _brLine = RegExp(r'^\s*(<br\s*/?>\s*)+$', caseSensitive: false);

  static List<MdBlock> split(String text) {
    final blocks = <MdBlock>[];
    final lines = _lines(text);
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      if (line.text.trim().isEmpty) {
        i++;
        continue;
      }

      // 코드 펜스
      final fence = _fence.firstMatch(line.text);
      if (fence != null) {
        final marker = fence.group(1)!;
        var j = i + 1;
        while (j < lines.length && !lines[j].text.trim().startsWith(marker)) {
          j++;
        }
        final last = j < lines.length ? j : lines.length - 1;
        blocks.add(_make(text, lines[i].start, lines[last].end, MdBlockType.code));
        i = last + 1;
        continue;
      }

      // HTML div 블록 (짝이 맞는 </div> 까지)
      if (_divOpen.hasMatch(line.text)) {
        var depth = 0;
        var j = i;
        while (j < lines.length) {
          depth += RegExp(r'<div\b').allMatches(lines[j].text).length;
          depth -= RegExp(r'</div\s*>').allMatches(lines[j].text).length;
          if (depth <= 0) break;
          j++;
        }
        final last = j < lines.length ? j : lines.length - 1;
        blocks.add(_make(text, lines[i].start, lines[last].end, MdBlockType.html));
        i = last + 1;
        continue;
      }

      if (_heading.hasMatch(line.text)) {
        blocks.add(_make(text, line.start, line.end, MdBlockType.heading));
        i++;
        continue;
      }

      if (_brLine.hasMatch(line.text)) {
        blocks.add(_make(text, line.start, line.end, MdBlockType.br));
        i++;
        continue;
      }

      if (_hr.hasMatch(line.text)) {
        blocks.add(_make(text, line.start, line.end, MdBlockType.hr));
        i++;
        continue;
      }

      // 문단: 빈 줄 또는 다른 블록 시작 전까지
      var j = i;
      while (j + 1 < lines.length) {
        final next = lines[j + 1].text;
        if (next.trim().isEmpty || _fence.hasMatch(next) || _divOpen.hasMatch(next) || _heading.hasMatch(next)) {
          break;
        }
        j++;
      }
      blocks.add(_make(text, lines[i].start, lines[j].end, MdBlockType.paragraph));
      i = j + 1;
    }

    return blocks;
  }

  static MdBlock _make(String text, int start, int end, MdBlockType type) {
    // 끝의 \r 제거
    var e = end;
    while (e > start && (text[e - 1] == '\r')) {
      e--;
    }
    return MdBlock(start: start, end: e, text: text.substring(start, e), type: type);
  }

  static List<_Line> _lines(String text) {
    final result = <_Line>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\n') {
        result.add(_Line(start, i, text.substring(start, i)));
        start = i + 1;
      }
    }
    result.add(_Line(start, text.length, text.substring(start)));
    return result;
  }

  /// [offset] 을 포함하는 블록의 인덱스. 없으면 -1.
  static int indexAt(List<MdBlock> blocks, int offset) {
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].contains(offset)) return i;
    }
    return -1;
  }

  /// [offset] 위치에 가상의 빈 블록을 끼워 넣은 새 목록과 그 인덱스
  static (List<MdBlock>, int) withVirtualAt(List<MdBlock> blocks, int offset) {
    final result = <MdBlock>[];
    var inserted = -1;
    for (final b in blocks) {
      if (inserted < 0 && b.start > offset) {
        inserted = result.length;
        result.add(MdBlock(start: offset, end: offset, text: '', type: MdBlockType.paragraph, virtual: true));
      }
      result.add(b);
    }
    if (inserted < 0) {
      inserted = result.length;
      result.add(MdBlock(start: offset, end: offset, text: '', type: MdBlockType.paragraph, virtual: true));
    }
    return (result, inserted);
  }
}

class _Line {
  final int start;
  final int end;
  final String text;
  _Line(this.start, this.end, this.text);
}
