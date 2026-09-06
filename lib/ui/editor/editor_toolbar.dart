import 'package:flutter/material.dart';

import '../../models/jekyll_theme.dart';
import 'editor_actions.dart';
import 'editor_snippets.dart';

/// 에디터 툴바. 버튼을 누르면 [onApply]로 편집 동작을 넘긴다.
class EditorToolbar extends StatelessWidget {
  final JekyllTheme theme;
  final void Function(SnippetApply apply) onApply;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertLink;
  final VoidCallback onInsertCodeBlock;
  final void Function(PostTemplate template) onInsertTemplate;

  const EditorToolbar({
    super.key,
    required this.theme,
    required this.onApply,
    required this.onInsertImage,
    required this.onInsertLink,
    required this.onInsertCodeBlock,
    required this.onInsertTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _group([
              _HeadingMenu(onApply: onApply),
              _btn(Icons.format_bold, '굵게 (Ctrl+B)', () => onApply(EditorSnippets.bold)),
              _btn(Icons.format_italic, '기울임 (Ctrl+I)', () => onApply(EditorSnippets.italic)),
              _btn(Icons.format_strikethrough, '취소선 (Ctrl+Shift+X)', () => onApply(EditorSnippets.strike)),
              _btn(Icons.format_underlined, '밑줄', () => onApply(EditorSnippets.underline)),
              _btn(Icons.code, '인라인 코드 (Ctrl+E)', () => onApply(EditorSnippets.inlineCode)),
            ]),
            _divider(),
            _group([
              _ColorMenu(
                icon: Icons.format_color_text,
                tooltip: '글자 색상',
                colors: EditorSnippets.textColors,
                onPick: (c) => onApply((v) => EditorSnippets.textColor(v, c)),
              ),
              _ColorMenu(
                icon: Icons.format_color_fill,
                tooltip: '배경 형광펜',
                colors: EditorSnippets.highlightColors,
                onPick: (c) => onApply((v) => EditorSnippets.highlight(v, c)),
                extra: [
                  PopupMenuItem<PaletteColor?>(
                    value: null,
                    child: Row(
                      children: [
                        Container(width: 18, height: 18, decoration: BoxDecoration(color: const Color(0xFFFFF59D), borderRadius: BorderRadius.circular(3))),
                        const SizedBox(width: 10),
                        const Text('<mark> 태그'),
                      ],
                    ),
                  ),
                ],
                onExtra: () => onApply(EditorSnippets.mark),
              ),
            ]),
            _divider(),
            _group([
              _btn(Icons.link, '링크 (Ctrl+K)', onInsertLink),
              _btn(Icons.image_outlined, '이미지 삽입', onInsertImage),
              _btn(Icons.data_object, '코드 블록 (Ctrl+Shift+K)', onInsertCodeBlock),
              _btn(Icons.format_quote, '인용', () => onApply(EditorActions.toggleQuote)),
              _btn(Icons.format_list_bulleted, '글머리 기호', () => onApply(EditorActions.toggleBulletList)),
              _btn(Icons.format_list_numbered, '번호 목록', () => onApply(EditorActions.toggleNumberedList)),
              _btn(Icons.checklist, '체크리스트', () => onApply(EditorActions.toggleTaskList)),
              _btn(Icons.table_chart_outlined, '표', () => onApply((v) => EditorSnippets.table(v))),
              _btn(Icons.horizontal_rule, '구분선', () => onApply(EditorSnippets.horizontalRule)),
              _btn(Icons.keyboard_return, '줄바꿈 <br>', () => onApply(EditorSnippets.lineBreak)),
            ]),
            _divider(),
            _group([
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 6),
                child: Text('블로그 블록', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
              for (final style in theme.blockStyles)
                _BlockChip(
                  style: style,
                  onTap: () => onApply((v) => EditorSnippets.calloutBlock(v, style)),
                ),
              if (theme.hasCodeCompareBlocks)
                _PlainChip(
                  icon: Icons.compare_arrows,
                  label: '입출력 비교',
                  color: scheme.primary,
                  tooltip: 'code-block1 / code-block2',
                  onTap: () => onApply((v) => EditorSnippets.codeCompareBlock(v)),
                ),
            ]),
            if (theme.templates.isNotEmpty) ...[
              _divider(),
              _TemplateMenu(templates: theme.templates, onPick: onInsertTemplate),
            ],
          ],
        ),
      ),
    );
  }

  Widget _group(List<Widget> children) => Row(mainAxisSize: MainAxisSize.min, children: children);

  Widget _divider() => Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 6), color: const Color(0xFFDDE2E1));

  Widget _btn(IconData icon, String tooltip, VoidCallback onPressed) {
    return _ToolButton(icon: icon, tooltip: tooltip, onPressed: onPressed);
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: const Color(0xFF3E4A48)),
        ),
      ),
    );
  }
}

class _HeadingMenu extends StatelessWidget {
  final void Function(SnippetApply apply) onApply;
  const _HeadingMenu({required this.onApply});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '제목 (Ctrl+1 ~ Ctrl+4)',
      position: PopupMenuPosition.under,
      onSelected: (level) => onApply((v) => EditorActions.toggleHeading(v, level)),
      itemBuilder: (context) => [
        for (var i = 1; i <= 4; i++)
          PopupMenuItem(
            value: i,
            child: Text('${'#' * i} 제목 $i', style: TextStyle(fontSize: 20 - i * 2.0, fontWeight: FontWeight.w700)),
          ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.title, size: 20, color: Color(0xFF3E4A48)),
            Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF3E4A48)),
          ],
        ),
      ),
    );
  }
}

class _ColorMenu extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final List<PaletteColor> colors;
  final void Function(Color color) onPick;
  final List<PopupMenuEntry<PaletteColor?>> extra;
  final VoidCallback? onExtra;

  const _ColorMenu({
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onPick,
    this.extra = const [],
    this.onExtra,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PaletteColor?>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      onSelected: (c) {
        if (c == null) {
          onExtra?.call();
        } else {
          onPick(c.color);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<PaletteColor?>(
          enabled: false,
          height: 0,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SizedBox(
            width: 230,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in colors)
                  Tooltip(
                    message: '${c.name} ${EditorSnippets.hex(c.color)}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        Navigator.of(context).pop();
                        onPick(c.color);
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c.color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        PopupMenuItem<PaletteColor?>(
          enabled: false,
          height: 0,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: _CustomHexField(onSubmit: (color) {
            Navigator.of(context).pop();
            onPick(color);
          }),
        ),
        if (extra.isNotEmpty) const PopupMenuDivider(),
        ...extra,
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF3E4A48)),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF3E4A48)),
          ],
        ),
      ),
    );
  }
}

class _CustomHexField extends StatefulWidget {
  final void Function(Color color) onSubmit;
  const _CustomHexField({required this.onSubmit});

  @override
  State<_CustomHexField> createState() => _CustomHexFieldState();
}

class _CustomHexFieldState extends State<_CustomHexField> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    var text = _controller.text.trim().replaceFirst('#', '');
    if (text.length == 3) text = text.split('').map((c) => '$c$c').join();
    final value = int.tryParse(text, radix: 16);
    if (text.length != 6 || value == null) {
      setState(() => _error = '예: #1E88E5');
      return;
    }
    widget.onSubmit(Color(0xFF000000 | value));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: TextField(
        controller: _controller,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          prefixText: '# ',
          hintText: '직접 입력 (hex)',
          errorText: _error,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          suffixIcon: IconButton(icon: const Icon(Icons.check, size: 18), onPressed: _submit),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  final BlogBlockStyle style;
  final VoidCallback onTap;
  const _BlockChip({required this.style, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = style.isReference
        ? Icons.menu_book_outlined
        : style.className.contains('warning')
            ? Icons.warning_amber_rounded
            : style.hasHeader
                ? Icons.info_outline
                : Icons.crop_square;
    return _PlainChip(
      icon: icon,
      label: style.label,
      color: style.headerBackground ?? style.borderColor,
      tooltip: '.${style.className}',
      onTap: onTap,
    );
  }
}

class _PlainChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _PlainChip({required this.icon, required this.label, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateMenu extends StatelessWidget {
  final List<PostTemplate> templates;
  final void Function(PostTemplate template) onPick;
  const _TemplateMenu({required this.templates, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PostTemplate>(
      tooltip: '_posts 폴더의 템플릿 삽입',
      position: PopupMenuPosition.under,
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final t in templates)
          PopupMenuItem(
            value: t,
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 16),
                const SizedBox(width: 8),
                Text(t.name),
              ],
            ),
          ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined, size: 20, color: Color(0xFF3E4A48)),
            SizedBox(width: 4),
            Text('템플릿', style: TextStyle(fontSize: 12, color: Color(0xFF3E4A48))),
            Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF3E4A48)),
          ],
        ),
      ),
    );
  }
}
