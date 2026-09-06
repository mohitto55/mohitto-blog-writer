import 'package:path/path.dart' as p;

/// `_posts` 폴더의 지킬 포스트 한 편.
///
/// 파일명 규칙 (블로그 폴더의 실제 사용 방식을 따름):
/// - `YYYY-MM-DD-제목.md`  : 게시되는 포스트
/// - `mYYYY-MM-DD-제목.md` : 앞에 `m`이 붙으면 Jekyll이 날짜를 인식하지 못해 사이트에서 숨겨짐 (초안)
/// - 날짜가 없는 파일 (`z템플릿.md` 등) : 템플릿
class JekyllPost {
  String subject;
  String title;
  String category;
  List<String> tags;
  String body;

  /// 앱이 직접 다루지 않는 frontmatter 줄들 (원문 그대로 보존)
  final List<String> extraFrontmatterLines;

  JekyllPost({
    this.subject = '',
    this.title = '',
    this.category = '',
    List<String>? tags,
    this.body = '',
    List<String>? extraFrontmatterLines,
  })  : tags = tags ?? [],
        extraFrontmatterLines = extraFrontmatterLines ?? [];

  static final RegExp _publishedName = RegExp(r'^\d{4}-\d{1,2}-\d{1,2}-');
  static final RegExp _draftName = RegExp(r'^m\d{4}-\d{1,2}-\d{1,2}-');
  static final RegExp _datePrefix = RegExp(r'^m?(\d{4})-(\d{1,2})-(\d{1,2})-');

  /// `[주제] 제목` 형태의 전체 제목
  String get fullTitle {
    final s = subject.trim();
    final t = title.trim();
    if (s.isEmpty) return t;
    return '[$s] $t';
  }

  set fullTitle(String value) {
    final parsed = splitTitle(value);
    subject = parsed.$1;
    title = parsed.$2;
  }

  /// `"[Subject] Title"` → (Subject, Title)
  static (String, String) splitTitle(String value) {
    final m = RegExp(r'^\s*\[([^\]]*)\]\s*(.*)$', dotAll: true).firstMatch(value);
    if (m == null) return ('', value.trim());
    return (m.group(1)!.trim(), m.group(2)!.trim());
  }

  // ---------------------------------------------------------------------------
  // Parsing / serializing
  // ---------------------------------------------------------------------------

  factory JekyllPost.parse(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final post = JekyllPost();

    if (lines.isEmpty || lines.first.trim() != '---') {
      post.body = raw;
      return post;
    }

    var end = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        end = i;
        break;
      }
    }
    if (end < 0) {
      post.body = raw;
      return post;
    }

    for (final line in lines.sublist(1, end)) {
      final idx = line.indexOf(':');
      if (idx <= 0) {
        if (line.trim().isNotEmpty) post.extraFrontmatterLines.add(line);
        continue;
      }
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      switch (key) {
        case 'title':
          post.fullTitle = _unquote(value);
        case 'categories':
        case 'category':
          final list = _parseInlineList(value);
          post.category = list.isEmpty ? '' : list.first;
        case 'tags':
          post.tags = _parseInlineList(value);
        default:
          post.extraFrontmatterLines.add(line);
      }
    }

    post.body = lines.sublist(end + 1).join('\n');
    // frontmatter 뒤의 빈 줄 하나는 serialize 시 다시 붙이므로 제거
    if (post.body.startsWith('\n')) post.body = post.body.substring(1);
    return post;
  }

  /// 최근 포스트 형식을 따른다: `date`, `published` → `title` → `categories` → `tags` → 나머지
  String serialize() {
    final buffer = StringBuffer();
    buffer.writeln('---');
    final leading = extraFrontmatterLines.where(_isLeadingKey).toList();
    final trailing = extraFrontmatterLines.where((l) => !_isLeadingKey(l)).toList();
    for (final line in leading) {
      buffer.writeln(line);
    }
    buffer.writeln('title: "${fullTitle.replaceAll('"', r'\"')}"');
    buffer.writeln('categories: ${category.trim()}');
    buffer.writeln('tags: [${tags.map((t) => t.trim()).where((t) => t.isNotEmpty).join(', ')}]');
    for (final line in trailing) {
      buffer.writeln(line);
    }
    buffer.writeln('---');
    buffer.writeln();
    buffer.write(body);
    return buffer.toString();
  }

  static bool _isLeadingKey(String line) {
    final key = line.split(':').first.trim();
    return key == 'date' || key == 'published';
  }

  bool hasFrontmatterKey(String key) {
    return extraFrontmatterLines.any((l) => l.split(':').first.trim() == key);
  }

  /// `date:` / `published:` 를 최근 포스트처럼 채운다 (이미 있으면 유지, 빈 값이면 채움)
  void ensurePublishFields(DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final idx = extraFrontmatterLines.indexWhere((l) => l.split(':').first.trim() == 'date');
    if (idx < 0) {
      extraFrontmatterLines.insert(0, 'date: $dateStr');
    } else if (extraFrontmatterLines[idx].split(':').skip(1).join(':').trim().isEmpty) {
      extraFrontmatterLines[idx] = 'date: $dateStr';
    }
    if (!hasFrontmatterKey('published')) {
      final at = extraFrontmatterLines.indexWhere((l) => l.split(':').first.trim() == 'date') + 1;
      extraFrontmatterLines.insert(at, 'published: true');
    }
  }

  JekyllPost copy() {
    return JekyllPost(
      subject: subject,
      title: title,
      category: category,
      tags: List.of(tags),
      body: body,
      extraFrontmatterLines: List.of(extraFrontmatterLines),
    );
  }

  static String _unquote(String value) {
    var v = value.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v.replaceAll(r'\"', '"');
  }

  static List<String> _parseInlineList(String value) {
    var v = value.trim();
    if (v.startsWith('[') && v.endsWith(']')) v = v.substring(1, v.length - 1);
    return v
        .split(',')
        .map((e) => _unquote(e))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // File naming
  // ---------------------------------------------------------------------------

  static bool isPublishedFileName(String fileName) => _publishedName.hasMatch(fileName);

  static bool isDraftFileName(String fileName) => _draftName.hasMatch(fileName);

  static bool isTemplateFileName(String fileName) {
    if (_datePrefix.hasMatch(fileName)) return false;
    final lower = fileName.toLowerCase();
    return lower.contains('템플릿') || lower.contains('template');
  }

  static DateTime? dateFromFileName(String fileName) {
    final m = _datePrefix.firstMatch(fileName);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// 파일명에서 날짜 접두어와 확장자를 제거한 제목 부분
  static String titlePartOfFileName(String fileName) {
    final base = p.basenameWithoutExtension(fileName);
    return base.replaceFirst(_datePrefix, '');
  }

  /// 새 포스트 파일명 생성. `2025-01-02-[주제] 제목.md`
  static String buildFileName({
    required DateTime date,
    required String fullTitle,
    bool draft = false,
  }) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    var safe = fullTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    safe = safe.replaceAll(RegExp(r'\s+'), ' ');
    if (safe.isEmpty) safe = 'untitled';
    return '${draft ? 'm' : ''}$dateStr-$safe.md';
  }

  /// 기존 파일명의 초안 여부만 바꾼 파일명
  static String toggleDraftFileName(String fileName, {required bool draft}) {
    if (draft) {
      return isPublishedFileName(fileName) ? 'm$fileName' : fileName;
    }
    return isDraftFileName(fileName) ? fileName.substring(1) : fileName;
  }

  /// Jekyll 의 `:title` 슬러그 (파일명 제목 부분 기준).
  /// 이 블로그(GitHub Pages 의 Jekyll)는 대소문자를 유지한다: `[Backend] BFF 개념` → `Backend-BFF-개념`
  static String slugFromFileName(String fileName) {
    final titlePart = titlePartOfFileName(fileName);
    final slug = titlePart
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  /// 로컬 서버에서의 포스트 URL 경로 (`/:categories/:title/` 패턴 기준)
  static String localUrlPath({
    required String fileName,
    required String category,
    String permalinkPattern = '/:categories/:title/',
  }) {
    final slug = slugFromFileName(fileName);
    final date = dateFromFileName(fileName) ?? DateTime.now();
    var pattern = permalinkPattern;
    pattern = pattern.replaceAll(':categories', category.trim());
    pattern = pattern.replaceAll(':category', category.trim());
    pattern = pattern.replaceAll(':title', slug);
    pattern = pattern.replaceAll(':year', date.year.toString());
    pattern = pattern.replaceAll(':month', date.month.toString().padLeft(2, '0'));
    pattern = pattern.replaceAll(':day', date.day.toString().padLeft(2, '0'));
    pattern = pattern.replaceAll(RegExp(r'/{2,}'), '/');
    return pattern;
  }
}
