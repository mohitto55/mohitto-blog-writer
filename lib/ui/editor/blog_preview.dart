import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../models/jekyll_theme.dart';

/// 지킬 블로그(minimal-mistakes)처럼 보이도록 마크다운을 렌더링하는 미리보기.
///
/// 블로그의 커스텀 HTML 블록(`<div class="callout-…">`, `<div class="Reference">`,
/// `code-block1/2`)과 인라인 태그(`<span style="color:…">`, `<mark>`, `<br>`, `<a>`)를
/// 실제 SCSS 에서 읽어온 색상으로 그린다.
class BlogPreview extends StatelessWidget {
  final String markdown;
  final JekyllTheme theme;
  final String? title;
  final String? category;
  final List<String> tags;
  final DateTime? date;
  final ScrollController? scrollController;

  const BlogPreview({
    super.key,
    required this.markdown,
    required this.theme,
    this.title,
    this.category,
    this.tags = const [],
    this.date,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final skin = theme.skin;
    return Container(
      color: skin.background,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null && title!.trim().isNotEmpty) BlogPostHeader(theme: theme, title: title!, category: category, tags: tags, date: date),
                BlogMarkdownBody(markdown: markdown, theme: theme),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 블로그 포스트 상단 (제목, 카테고리, 태그, 날짜)
class BlogPostHeader extends StatelessWidget {
  final JekyllTheme theme;
  final String title;
  final String? category;
  final List<String> tags;
  final DateTime? date;

  const BlogPostHeader({super.key, required this.theme, required this.title, this.category, this.tags = const [], this.date});

  @override
  Widget build(BuildContext context) {
    final skin = theme.skin;
    final dateText = date == null
        ? null
        : '${date!.year}. ${date!.month.toString().padLeft(2, '0')}. ${date!.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: skin.text, height: 1.25),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (category != null && category!.isNotEmpty)
                _Pill(text: category!, background: skin.primary, foreground: Colors.white),
              for (final t in tags) _Pill(text: '#$t', background: skin.primary.withValues(alpha: 0.12), foreground: skin.primary),
              if (dateText != null)
                Text(dateText, style: TextStyle(color: skin.mutedText, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: skin.border, height: 1),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  const _Pill({required this.text, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// 헤더 없이 본문만 렌더링하는 마크다운 위젯 (콜아웃 내부 등에서 재귀적으로 사용)
class BlogMarkdownBody extends StatelessWidget {
  final String markdown;
  final JekyllTheme theme;
  final double fontSize;

  const BlogMarkdownBody({super.key, required this.markdown, required this.theme, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    final skin = theme.skin;
    final base = TextStyle(fontSize: fontSize, color: skin.text, height: 1.75);
    final mono = TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['Courier New', 'monospace'], fontSize: fontSize - 1.5, color: const Color(0xFF3B3B3B));

    final styleSheet = MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 4),
      a: TextStyle(color: skin.link, decoration: TextDecoration.underline, decorationColor: skin.link.withValues(alpha: 0.5)),
      h1: TextStyle(fontSize: fontSize * 1.9, fontWeight: FontWeight.w700, color: skin.text, height: 1.3),
      h2: TextStyle(fontSize: fontSize * 1.55, fontWeight: FontWeight.w700, color: skin.text, height: 1.3),
      h3: TextStyle(fontSize: fontSize * 1.3, fontWeight: FontWeight.w700, color: skin.text, height: 1.3),
      h4: TextStyle(fontSize: fontSize * 1.12, fontWeight: FontWeight.w700, color: skin.text),
      h5: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: skin.text),
      h6: TextStyle(fontSize: fontSize * 0.9, fontWeight: FontWeight.w700, color: skin.mutedText),
      h1Padding: const EdgeInsets.only(top: 22, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 6),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 4),
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      code: mono.copyWith(backgroundColor: const Color(0xFFEAEDEC)),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF263238),
        borderRadius: BorderRadius.circular(4),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      blockquote: base.copyWith(color: skin.mutedText, fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(left: BorderSide(color: skin.primary.withValues(alpha: 0.6), width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      listBullet: base,
      listIndent: 24,
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base.copyWith(fontSize: fontSize - 1),
      tableBorder: TableBorder.all(color: skin.border, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableHeadAlign: TextAlign.left,
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: skin.border, width: 1))),
      img: base,
      checkbox: base,
    );

    return MarkdownBody(
      data: markdown,
      selectable: false,
      softLineBreak: false,
      styleSheet: styleSheet,
      extensionSet: md.ExtensionSet.gitHubWeb,
      blockSyntaxes: [BlogHtmlBlockSyntax(), BareBrLineSyntax()],
      inlineSyntaxes: [
        InlineBrSyntax(),
        HtmlAnchorSyntax(),
        HtmlImgSyntax(),
        StyledSpanSyntax(),
      ],
      builders: {
        'blogblock': _BlogBlockBuilder(theme: theme, fontSize: fontSize),
        'brline': _BrLineBuilder(),
        'cspan': _StyledSpanBuilder(),
        'pre': _CodeBlockBuilder(mono: mono.copyWith(color: const Color(0xFFECEFF1))),
      },
      sizedImageBuilder: (config) => _buildImage(config.uri, config.alt),
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  Widget _buildImage(Uri uri, String? alt) {
    Widget image;
    final raw = uri.toString().trim();
    if (raw.isEmpty) {
      return _placeholder(Icons.add_photo_alternate_outlined, '이미지 주소를 넣으세요: ![${alt ?? '설명'}](주소)');
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      // 웹에서는 CORS 헤더가 없는 외부 이미지(GitHub 첨부 등)를 <img> 태그로 대신 불러온다
      image = Image.network(
        raw,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, __, ___) => _brokenImage(raw),
      );
    } else if (theme.blogPath.isNotEmpty) {
      final rel = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
      final file = File(p.join(theme.blogPath, rel.replaceAll('/', p.separator)));
      if (file.existsSync()) {
        image = Image.file(file);
      } else {
        image = _brokenImage(raw);
      }
    } else if (theme.assetBaseUrl != null) {
      final rel = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
      image = Image.network(
        '${theme.assetBaseUrl}$rel',
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, __, ___) => _brokenImage(raw),
      );
    } else {
      image = _brokenImage(raw);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: image),
    );
  }

  Widget _placeholder(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFD0D5D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF8A9491)),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF8A9491)))),
        ],
      ),
    );
  }

  Widget _brokenImage(String? src) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFD0D5D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 18, color: Color(0xFF8A9491)),
          const SizedBox(width: 8),
          Flexible(child: Text('이미지를 불러오지 못했습니다: ${src ?? ''}', style: const TextStyle(fontSize: 12, color: Color(0xFF8A9491)))),
        ],
      ),
    );
  }
}

// =============================================================================
// Block syntax: <div class="..."> ... </div>
// =============================================================================

/// `<div class="X">` 로 시작해 짝이 맞는 `</div>` 까지를 하나의 블록으로 잡는다.
class BlogHtmlBlockSyntax extends md.BlockSyntax {
  static final RegExp _open = RegExp(r'''^\s*<div\s+class=["']([\w-]+)["']\s*>''');

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) => _open.hasMatch(parser.current.content);

  @override
  md.Node? parse(md.BlockParser parser) {
    final first = parser.current.content;
    final className = _open.firstMatch(first)!.group(1)!;
    final lines = <String>[];
    var depth = 0;

    while (!parser.isDone) {
      final line = parser.current.content;
      depth += RegExp(r'<div\b').allMatches(line).length;
      depth -= RegExp(r'</div\s*>').allMatches(line).length;
      lines.add(line);
      parser.advance();
      if (depth <= 0) break;
    }

    final raw = lines.join('\n');
    final element = md.Element('blogblock', []);
    element.attributes['class'] = className;
    element.attributes['raw'] = raw;
    return element;
  }
}

/// 한 줄이 `<br>` 만으로 이루어진 경우 → 세로 여백
class BareBrLineSyntax extends md.BlockSyntax {
  static final RegExp _br = RegExp(r'^\s*(<br\s*/?>\s*)+$', caseSensitive: false);

  @override
  RegExp get pattern => _br;

  @override
  md.Node? parse(md.BlockParser parser) {
    var count = 0;
    while (!parser.isDone && _br.hasMatch(parser.current.content)) {
      count += RegExp(r'<br', caseSensitive: false).allMatches(parser.current.content).length;
      parser.advance();
    }
    final element = md.Element('brline', []);
    element.attributes['count'] = count.toString();
    return element;
  }
}

// =============================================================================
// Inline syntaxes
// =============================================================================

class InlineBrSyntax extends md.InlineSyntax {
  InlineBrSyntax() : super(r'<br\s*/?>', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

class HtmlAnchorSyntax extends md.InlineSyntax {
  HtmlAnchorSyntax() : super(r'''<a\s+[^>]*href=["']([^"']*)["'][^>]*>([\s\S]*?)</a>''', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final href = match.group(1)!;
    var label = match.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (label.isEmpty) label = href;
    if (label.isEmpty) label = '(빈 링크)';
    final element = md.Element('a', [md.Text(label)]);
    element.attributes['href'] = href;
    parser.addNode(element);
    return true;
  }
}

class HtmlImgSyntax extends md.InlineSyntax {
  HtmlImgSyntax() : super(r'''<img\s+[^>]*src=["']([^"']*)["'][^>]*/?>''', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.empty('img');
    element.attributes['src'] = match.group(1)!;
    final alt = RegExp(r'''alt=["']([^"']*)["']''').firstMatch(match.group(0)!);
    element.attributes['alt'] = alt?.group(1) ?? '';
    parser.addNode(element);
    return true;
  }
}

/// `<span style="color:#f00">…</span>`, `<mark>…</mark>`, `<u>`, `<b>`, `<i>`, `<font color>`
class StyledSpanSyntax extends md.InlineSyntax {
  StyledSpanSyntax()
      : super(
          r'<(span|mark|u|b|strong|i|em|font|sub|sup)\b([^>]*)>([\s\S]*?)</\1\s*>',
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tag = match.group(1)!.toLowerCase();
    final attrs = match.group(2) ?? '';
    final inner = match.group(3)!;

    final element = md.Element('cspan', [md.Text(inner)]);
    element.attributes['tag'] = tag;
    final style = RegExp(r'''style=["']([^"']*)["']''').firstMatch(attrs)?.group(1);
    if (style != null) element.attributes['style'] = style;
    final color = RegExp(r'''color=["']([^"']*)["']''').firstMatch(attrs)?.group(1);
    if (color != null) element.attributes['fontcolor'] = color;
    parser.addNode(element);
    return true;
  }
}

// =============================================================================
// Builders
// =============================================================================

Color? parseCssColor(String? value) {
  if (value == null) return null;
  final v = value.trim().toLowerCase();
  final hex = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(v);
  if (hex != null) {
    var h = hex.group(1)!;
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    return Color(int.parse('ff$h', radix: 16));
  }
  final rgb = RegExp(r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(v);
  if (rgb != null) {
    return Color.fromARGB(255, int.parse(rgb.group(1)!), int.parse(rgb.group(2)!), int.parse(rgb.group(3)!));
  }
  const named = {
    'red': Colors.red,
    'blue': Colors.blue,
    'green': Colors.green,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'gray': Colors.grey,
    'grey': Colors.grey,
    'black': Colors.black,
    'white': Colors.white,
    'yellow': Colors.yellow,
    'pink': Colors.pink,
  };
  return named[v];
}

class _StyledSpanBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    var style = parentStyle ?? preferredStyle ?? const TextStyle();
    final tag = element.attributes['tag'];
    switch (tag) {
      case 'mark':
        style = style.copyWith(backgroundColor: const Color(0xFFFFF59D));
      case 'u':
        style = style.copyWith(decoration: TextDecoration.underline);
      case 'b':
      case 'strong':
        style = style.copyWith(fontWeight: FontWeight.w700);
      case 'i':
      case 'em':
        style = style.copyWith(fontStyle: FontStyle.italic);
      case 'sub':
      case 'sup':
        style = style.copyWith(fontSize: (style.fontSize ?? 14) * 0.75);
    }

    final fontColor = parseCssColor(element.attributes['fontcolor']);
    if (fontColor != null) style = style.copyWith(color: fontColor);

    final css = element.attributes['style'];
    if (css != null) {
      for (final decl in css.split(';')) {
        final idx = decl.indexOf(':');
        if (idx <= 0) continue;
        final key = decl.substring(0, idx).trim().toLowerCase();
        final value = decl.substring(idx + 1).trim();
        switch (key) {
          case 'color':
            final c = parseCssColor(value);
            if (c != null) style = style.copyWith(color: c);
          case 'background-color':
          case 'background':
            final c = parseCssColor(value);
            if (c != null) style = style.copyWith(backgroundColor: c);
          case 'font-weight':
            if (value == 'bold' || (int.tryParse(value) ?? 0) >= 600) style = style.copyWith(fontWeight: FontWeight.w700);
          case 'font-style':
            if (value == 'italic') style = style.copyWith(fontStyle: FontStyle.italic);
          case 'text-decoration':
            if (value.contains('underline')) style = style.copyWith(decoration: TextDecoration.underline);
            if (value.contains('line-through')) style = style.copyWith(decoration: TextDecoration.lineThrough);
          case 'font-size':
            final px = RegExp(r'([\d.]+)px').firstMatch(value);
            if (px != null) style = style.copyWith(fontSize: double.parse(px.group(1)!));
        }
      }
    }

    // RichText 를 돌려주어야 flutter_markdown 이 인접 텍스트와 하나의 문단으로 합친다.
    return RichText(text: TextSpan(text: element.textContent, style: style));
  }
}

class _BrLineBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final count = int.tryParse(element.attributes['count'] ?? '1') ?? 1;
    return SizedBox(height: 12.0 * count);
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final TextStyle mono;
  _CodeBlockBuilder({required this.mono});

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    String language = '';
    String code = element.textContent;
    if (element.children != null && element.children!.isNotEmpty) {
      final first = element.children!.first;
      if (first is md.Element && first.tag == 'code') {
        final cls = first.attributes['class'] ?? '';
        final m = RegExp(r'language-([\w+#-]+)').firstMatch(cls);
        if (m != null) language = m.group(1)!;
        code = first.textContent;
      }
    }
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF263238), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (language.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF1E272C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Text(language, style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11, letterSpacing: 0.5)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: SelectableText(code, style: mono),
          ),
        ],
      ),
    );
  }
}

/// 콜아웃 / Reference / code-block 블록 렌더링
class _BlogBlockBuilder extends MarkdownElementBuilder {
  final JekyllTheme theme;
  final double fontSize;

  _BlogBlockBuilder({required this.theme, required this.fontSize});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final className = element.attributes['class'] ?? '';
    final raw = element.attributes['raw'] ?? '';

    if (className == 'code-block1' || className == 'code-block2') {
      return _buildCodeCompare(className, raw);
    }

    final style = theme.styleFor(className);
    if (style == null) {
      return _buildGenericDiv(className, raw);
    }
    return _buildCallout(style, raw);
  }

  /// `<div class="X">` 와 마지막 `</div>` 를 벗겨낸 내부
  static String _inner(String raw) {
    var s = raw.trim();
    s = s.replaceFirst(RegExp(r'''^<div\s+class=["'][\w-]+["']\s*>'''), '');
    s = s.replaceFirst(RegExp(r'</div\s*>\s*$'), '');
    return s;
  }

  static String? _takeHeader(String inner, void Function(String rest) onRest) {
    final m = RegExp(r'''<div\s+class=["']callout-header["']\s*>([\s\S]*?)</div\s*>''').firstMatch(inner);
    if (m == null) {
      onRest(inner);
      return null;
    }
    onRest(inner.replaceRange(m.start, m.end, ''));
    return m.group(1)!.trim();
  }

  /// `<p>…</p>` 벗기기, 남은 HTML 은 마크다운 렌더러가 인라인 문법으로 처리
  static String _bodyToMarkdown(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<p\s*>'), '');
    s = s.replaceAll(RegExp(r'</p\s*>'), '\n');
    // `<br>` 뒤의 줄바꿈은 그대로 두고, 줄 끝의 <br> 은 hard break 로
    s = s.replaceAll(RegExp(r'<br\s*/?>\s*\n', caseSensitive: false), '  \n');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '  \n');
    // 앞뒤 공백 정리
    return s.split('\n').map((l) => l.trimRight()).join('\n').trim();
  }

  Widget _buildCallout(BlogBlockStyle style, String raw) {
    final inner = _inner(raw);
    String body = '';
    final header = _takeHeader(inner, (rest) => body = rest);
    final bodyMarkdown = _bodyToMarkdown(body);

    final headerText = [
      if (header != null && header.isNotEmpty) header,
      if (style.autoHeaderText != null) style.autoHeaderText!,
    ].join(' ');

    final radius = BorderRadius.circular(style.isReference ? 6 : 4);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: radius,
        border: Border.all(color: style.borderColor, width: 1.2),
        boxShadow: style.isReference
            ? const [BoxShadow(color: Color(0x38000000), blurRadius: 8, offset: Offset(0, 2))]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (style.hasHeader)
            Container(
              color: style.headerBackground ?? style.borderColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    style.isReference
                        ? Icons.menu_book_outlined
                        : style.className.contains('warning')
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline,
                    size: 16,
                    color: style.headerTextColor ?? Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      headerText.isEmpty ? ' ' : headerText,
                      style: TextStyle(
                        color: style.headerTextColor ?? Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: fontSize * 0.85,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: bodyMarkdown.isEmpty
                ? Text(' ', style: TextStyle(fontSize: fontSize * 0.85))
                : BlogMarkdownBody(markdown: bodyMarkdown, theme: theme, fontSize: fontSize * 0.88),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCompare(String className, String raw) {
    final inner = _inner(raw);
    final label = inner.split('\n').map((l) => l.trim()).firstWhere(
          (l) => l.isNotEmpty && !l.startsWith('<'),
          orElse: () => className == 'code-block1' ? '입력' : '출력',
        );
    final code = RegExp(r'<code>([\s\S]*?)</code>').firstMatch(inner)?.group(1) ?? '';
    final lang = RegExp(r'language-([\w+#-]+)').firstMatch(inner)?.group(1);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(className == 'code-block1' ? Icons.input : Icons.output, size: 16, color: theme.skin.mutedText),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: theme.skin.text, fontSize: fontSize * 0.9)),
              if (lang != null) ...[
                const SizedBox(width: 8),
                Text(lang, style: TextStyle(color: theme.skin.mutedText, fontSize: 11)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF263238),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              code.trim().isEmpty ? ' ' : code.trim(),
              style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['Courier New', 'monospace'], color: const Color(0xFFECEFF1), fontSize: fontSize - 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericDiv(String className, String raw) {
    final bodyMarkdown = _bodyToMarkdown(_inner(raw).replaceAll(RegExp(r'</?div[^>]*>'), ''));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.skin.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('.$className', style: TextStyle(fontSize: 11, color: theme.skin.mutedText)),
          if (bodyMarkdown.isNotEmpty) BlogMarkdownBody(markdown: bodyMarkdown, theme: theme, fontSize: fontSize * 0.9),
        ],
      ),
    );
  }
}
