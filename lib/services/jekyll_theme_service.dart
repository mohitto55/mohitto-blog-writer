import 'dart:ui';

import '../models/jekyll_post.dart';
import '../models/jekyll_theme.dart';
import 'blog_repository.dart';

/// 연결된 지킬 블로그(로컬 폴더 또는 GitHub 저장소)를 스캔해 에디터가 알아야 할 정보를 모은다.
///
/// - `_sass/**/*.scss` : 커스텀 콜아웃 클래스(`.callout-*`, `.Reference`)와 색상
/// - `_config.yml` + `_sass/minimal-mistakes/skins/_*.scss` : 스킨 색상, 사이트 URL, permalink
/// - `_pages/categories/*.md` : 카테고리 목록
/// - `_posts/*.md` : 사용 중인 태그, 템플릿 파일
class JekyllThemeService {
  final BlogRepository repository;

  JekyllThemeService({required this.repository});

  Future<JekyllTheme> scan() async {
    final blogPath = repository.isLocal ? repository.location : '';
    final fallback = JekyllTheme.fallback(blogPath);

    final config = await _readConfig();
    final skinName = config['minimal_mistakes_skin'] ?? 'default';
    final permalink = config['permalink'] ?? '/:categories/:title/';
    final siteUrl = _joinUrl(config['url'] ?? '', config['baseurl'] ?? '');

    final scssRules = await _collectScssRules();
    final skin = await _readSkin(skinName, scssRules);
    final blocks = _extractBlockStyles(scssRules);
    final hasCodeCompare = scssRules.containsKey('code-block1') && scssRules.containsKey('code-block2');

    final categories = await _readCategories();
    final postScan = await _scanPosts(categories);

    return JekyllTheme(
      blogPath: blogPath,
      skin: skin,
      blockStyles: blocks.isEmpty ? fallback.blockStyles : blocks,
      categories: postScan.categories,
      tags: postScan.tags,
      templates: postScan.templates,
      hasCodeCompareBlocks: hasCodeCompare,
      permalinkPattern: permalink,
      siteUrl: siteUrl,
      assetBaseUrl: repository.assetBaseUrl,
    );
  }

  static String _joinUrl(String url, String base) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    var b = base.trim();
    if (b.isEmpty || b == '/') return u;
    if (!b.startsWith('/')) b = '/$b';
    return '$u${b.replaceAll(RegExp(r'/+$'), '')}';
  }

  // ---------------------------------------------------------------------------
  // _config.yml
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _readConfig() async {
    final result = <String, String>{};
    final text = await repository.readTextFile('_config.yml');
    if (text == null) return result;

    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty || line.startsWith('-')) continue;
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      // 최상위 키만 (들여쓰기 없는 줄)
      if (rawLine.startsWith(' ') || rawLine.startsWith('\t')) continue;
      final key = line.substring(0, idx).trim();
      var value = line.substring(idx + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) result[key] = value;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // SCSS
  // ---------------------------------------------------------------------------

  /// `_sass` 아래 모든 scss 파일(vendor 제외)에서 단일 클래스 셀렉터 규칙을 모은다.
  Future<Map<String, _ScssRule>> _collectScssRules() async {
    final rules = <String, _ScssRule>{};
    final files = await repository.listFiles('_sass', recursive: true, extension: '.scss');
    for (final path in files) {
      if (path.contains('/vendor/')) continue;
      try {
        final source = await repository.readTextFile(path);
        if (source != null) _parseScss(source, rules);
      } catch (_) {
        // 파일 하나 실패해도 전체 스캔은 계속
      }
    }
    return rules;
  }

  static String _stripComments(String source) {
    final noBlock = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    return noBlock.replaceAll(RegExp(r'//[^\n]*'), '');
  }

  /// 최상위 `selector { ... }` 블록을 찾아 단일 클래스 셀렉터만 기록한다.
  static void _parseScss(String source, Map<String, _ScssRule> rules) {
    final text = _stripComments(source);
    var i = 0;
    while (i < text.length) {
      final open = text.indexOf('{', i);
      if (open < 0) break;
      var selStart = open - 1;
      while (selStart >= 0 && text[selStart] != ';' && text[selStart] != '}') {
        selStart--;
      }
      final selector = text.substring(selStart + 1, open).trim();
      final close = _matchingBrace(text, open);
      if (close < 0) break;
      final body = text.substring(open + 1, close);

      final classMatch = RegExp(r'^\.([A-Za-z_][\w-]*)$').firstMatch(selector);
      if (classMatch != null) {
        final rule = _ScssRule(classMatch.group(1)!);
        _parseRuleBody(body, rule);
        rules[rule.className] = rule;
      }
      i = close + 1;
    }
  }

  static int _matchingBrace(String text, int openIndex) {
    var depth = 0;
    for (var i = openIndex; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static void _parseRuleBody(String body, _ScssRule rule) {
    var i = 0;
    final buffer = StringBuffer();
    while (i < body.length) {
      final ch = body[i];
      if (ch == '{') {
        final selector = buffer.toString().trim();
        buffer.clear();
        final close = _matchingBrace(body, i);
        if (close < 0) break;
        final nested = body.substring(i + 1, close);
        if (selector.contains('callout-header')) {
          final nestedRule = _ScssRule('callout-header');
          _parseRuleBody(nested, nestedRule);
          if (selector.contains('::after')) {
            rule.headerAfterContent = nestedRule.properties['content'];
          } else if (!selector.contains('::before')) {
            rule.headerProperties.addAll(nestedRule.properties);
          }
        }
        i = close + 1;
        continue;
      }
      if (ch == ';') {
        final decl = buffer.toString().trim();
        buffer.clear();
        if (decl.startsWith('@extend')) {
          final target = decl.substring('@extend'.length).trim();
          if (target.startsWith('.')) rule.extendsClasses.add(target.substring(1));
        } else {
          final idx = decl.indexOf(':');
          if (idx > 0) {
            final key = decl.substring(0, idx).trim();
            var value = decl.substring(idx + 1).trim();
            value = value.replaceAll('!important', '').trim();
            rule.properties[key] = value;
          }
        }
        i++;
        continue;
      }
      buffer.write(ch);
      i++;
    }
  }

  List<BlogBlockStyle> _extractBlockStyles(Map<String, _ScssRule> rules) {
    const excluded = {'callout', 'callout-expanded', 'callout-header', 'callout-container'};

    final styles = <BlogBlockStyle>[];
    for (final rule in rules.values) {
      final name = rule.className;
      final isCallout = name.startsWith('callout-') && !excluded.contains(name);
      final isReference = name == 'Reference';
      if (!isCallout && !isReference) continue;

      final chain = _extendChain(rule, rules);
      final border = _resolveColor(chain, 'border-color');
      final background = _resolveColor(chain, 'background-color');
      if (border == null && background == null) continue;

      final hasHeader = isReference ||
          chain.any((r) => r.className == 'callout-expanded') ||
          rule.headerProperties.isNotEmpty;

      Color? headerBg;
      Color? headerFg;
      for (final r in chain) {
        headerBg ??= _parseColor(r.headerProperties['background-color']);
        headerFg ??= _parseColor(r.headerProperties['color']);
      }

      String? autoHeader;
      for (final r in chain) {
        final content = r.headerAfterContent;
        if (content != null) {
          autoHeader = content.replaceAll('"', '').replaceAll("'", '').trim();
          break;
        }
      }

      styles.add(BlogBlockStyle(
        className: name,
        label: _labelFor(name),
        borderColor: border ?? background ?? const Color(0xFF888888),
        backgroundColor: background ?? const Color(0xFFFFFFFF),
        headerBackground: headerBg ?? border,
        headerTextColor: headerFg ?? const Color(0xFFFFFFFF),
        hasHeader: hasHeader,
        autoHeaderText: autoHeader,
      ));
    }

    styles.sort((a, b) {
      if (a.hasHeader != b.hasHeader) return a.hasHeader ? -1 : 1;
      return a.label.compareTo(b.label);
    });
    return styles;
  }

  static List<_ScssRule> _extendChain(_ScssRule rule, Map<String, _ScssRule> rules) {
    final chain = <_ScssRule>[];
    final visited = <String>{};
    void walk(_ScssRule r) {
      if (!visited.add(r.className)) return;
      chain.add(r);
      for (final ext in r.extendsClasses) {
        final parent = rules[ext];
        if (parent != null) walk(parent);
      }
    }

    walk(rule);
    return chain;
  }

  static Color? _resolveColor(List<_ScssRule> chain, String property) {
    for (final r in chain) {
      final c = _parseColor(r.properties[property]);
      if (c != null) return c;
    }
    return null;
  }

  static String _labelFor(String className) {
    if (className == 'Reference') return 'Reference';
    var label = className;
    if (label.startsWith('callout-')) label = label.substring('callout-'.length);
    if (label.endsWith('-expanded')) label = label.substring(0, label.length - '-expanded'.length);
    if (label.isEmpty) return className;
    return label[0].toUpperCase() + label.substring(1);
  }

  static Color? _parseColor(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();

    final hex = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$').firstMatch(v);
    if (hex != null) {
      var h = hex.group(1)!;
      if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
      if (h.length == 6) h = 'ff$h';
      return Color(int.parse(h, radix: 16));
    }

    final rgb = RegExp(r'^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$').firstMatch(v);
    if (rgb != null) {
      final r = double.parse(rgb.group(1)!).round().clamp(0, 255);
      final g = double.parse(rgb.group(2)!).round().clamp(0, 255);
      final b = double.parse(rgb.group(3)!).round().clamp(0, 255);
      final a = rgb.group(4) == null ? 255 : (double.parse(rgb.group(4)!) * 255).round().clamp(0, 255);
      return Color.fromARGB(a, r, g, b);
    }

    const named = {
      'white': 0xFFFFFFFF,
      'black': 0xFF000000,
      'red': 0xFFFF0000,
      'blue': 0xFF0000FF,
      'green': 0xFF008000,
      'gray': 0xFF808080,
      'grey': 0xFF808080,
      'lightgrey': 0xFFD3D3D3,
      'lightgray': 0xFFD3D3D3,
      'orange': 0xFFFFA500,
      'yellow': 0xFFFFFF00,
    };
    final n = named[v];
    return n == null ? null : Color(n);
  }

  // ---------------------------------------------------------------------------
  // Skin
  // ---------------------------------------------------------------------------

  Future<BlogSkin> _readSkin(String skinName, Map<String, _ScssRule> rules) async {
    var skin = BlogSkin.mint.copyWith(name: skinName);
    final skinSource = await repository.readTextFile('_sass/minimal-mistakes/skins/_$skinName.scss');
    if (skinSource != null) {
      final vars = _parseVariables(skinSource);
      skin = skin.copyWith(
        background: _parseColor(vars[r'$background-color']) ?? skin.background,
        text: _parseColor(vars[r'$text-color']) ?? skin.text,
        mutedText: _parseColor(vars[r'$muted-text-color']) ?? skin.mutedText,
        primary: _parseColor(vars[r'$primary-color']) ?? skin.primary,
        link: _parseColor(vars[r'$link-color']) ?? skin.link,
        border: _parseColor(vars[r'$border-color']) ?? skin.border,
      );
    }

    final variables = await repository.readTextFile('_sass/minimal-mistakes/_variables.scss');
    if (variables != null) {
      final vars = _parseVariables(variables);
      final accent = _parseColor(vars[r'$mohitto-color']);
      if (accent != null) skin = skin.copyWith(accent: accent);
    }
    return skin;
  }

  static Map<String, String> _parseVariables(String source) {
    final result = <String, String>{};
    final text = _stripComments(source);
    for (final m in RegExp(r'(\$[\w-]+)\s*:\s*([^;]+);').allMatches(text)) {
      result[m.group(1)!] = m.group(2)!.replaceAll('!default', '').trim();
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Categories / posts
  // ---------------------------------------------------------------------------

  Future<List<BlogCategory>> _readCategories() async {
    final result = <BlogCategory>[];
    final files = await repository.listFiles('_pages/categories', extension: '.md');
    for (final path in files) {
      try {
        final text = await repository.readTextFile(path);
        if (text == null) continue;
        final fm = _readFrontmatterLines(text);
        var permalink = fm['permalink'] ?? '';
        permalink = permalink.replaceAll(RegExp(r'^/+|/+$'), '');
        if (permalink.isEmpty) continue;
        result.add(BlogCategory(slug: permalink, title: fm['title'] ?? permalink));
      } catch (_) {}
    }
    result.sort((a, b) => a.slug.compareTo(b.slug));
    return result;
  }

  Future<_PostScan> _scanPosts(List<BlogCategory> knownCategories) async {
    final tagCounts = <String, int>{};
    final categorySlugs = <String, BlogCategory>{for (final c in knownCategories) c.slug: c};
    final templates = <PostTemplate>[];

    List<PostInfo> posts;
    try {
      posts = await repository.listPosts();
    } catch (_) {
      posts = const [];
    }

    for (final post in posts) {
      for (final t in post.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
      if (post.category.isNotEmpty) {
        categorySlugs.putIfAbsent(post.category, () => BlogCategory(slug: post.category, title: post.category));
      }
      if (post.isTemplate) {
        try {
          final content = await repository.readPost(post.name);
          templates.add(PostTemplate(
            name: templateDisplayName(post.name),
            path: post.name,
            body: JekyllPost.parse(content).body.trimLeft(),
          ));
        } catch (_) {}
      }
    }

    final sortedTags = tagCounts.keys.toList()
      ..sort((a, b) {
        final byCount = tagCounts[b]!.compareTo(tagCounts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    final categories = categorySlugs.values.toList()..sort((a, b) => a.slug.compareTo(b.slug));
    templates.sort((a, b) => a.name.compareTo(b.name));

    return _PostScan(categories: categories, tags: sortedTags, templates: templates);
  }

  /// `템플릿 - 개념 정리.md` → `개념 정리`, `문제풀이 템플릿.md` → `문제풀이`
  static String templateDisplayName(String fileName) {
    var name = fileName.replaceFirst(RegExp(r'\.md$', caseSensitive: false), '');
    name = name.replaceFirst(RegExp(r'^\s*(템플릿|template)\s*[-_:]\s*', caseSensitive: false), '');
    // 접미사는 구분자나 공백이 있을 때만 뗀다 (`z템플릿` 은 그대로)
    name = name.replaceFirst(RegExp(r'(\s*[-_:]\s*|\s+)(템플릿|template)\s*$', caseSensitive: false), '');
    name = name.trim();
    return name.isEmpty ? fileName.replaceFirst(RegExp(r'\.md$'), '') : name;
  }

  static Map<String, String> _readFrontmatterLines(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final result = <String, String>{};
    if (lines.isEmpty || lines.first.trim() != '---') return result;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim() == '---') break;
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      var value = line.substring(idx + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }
}

class _ScssRule {
  final String className;
  final Map<String, String> properties = {};
  final Map<String, String> headerProperties = {};
  final List<String> extendsClasses = [];
  String? headerAfterContent;

  _ScssRule(this.className);
}

class _PostScan {
  final List<BlogCategory> categories;
  final List<String> tags;
  final List<PostTemplate> templates;

  _PostScan({required this.categories, required this.tags, required this.templates});
}
