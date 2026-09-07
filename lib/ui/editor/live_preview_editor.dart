import 'package:flutter/material.dart';

import '../../models/jekyll_theme.dart';
import 'blog_preview.dart';
import 'editor_snippets.dart';
import 'markdown_blocks.dart';
import 'markdown_editor.dart';

/// 블로그 스타일이 적용된 페이지 위에서 바로 편집하는 라이브 편집기.
///
/// 문서를 블록(문단, 제목, 코드, 콜아웃 …)으로 나누어 렌더링하고, 클릭한 블록 하나만
/// 원문 편집 필드로 바꾼다 (Obsidian 라이브 프리뷰 방식). 편집 내용은 즉시
/// [document] 컨트롤러(전체 본문)에 반영되므로 소스 모드/저장과 항상 같은 내용을 본다.
class LivePreviewEditor extends StatefulWidget {
  final TextEditingController document;
  final JekyllTheme theme;
  final Map<ShortcutActivator, EditorShortcutHandler> shortcuts;
  final VoidCallback? onSave;
  final Widget? header;
  final ScrollController? scrollController;
  final double fontSize;
  final double horizontalPadding;

  const LivePreviewEditor({
    super.key,
    required this.document,
    required this.theme,
    this.shortcuts = const {},
    this.onSave,
    this.header,
    this.scrollController,
    this.fontSize = 15,
    this.horizontalPadding = 32,
  });

  @override
  State<LivePreviewEditor> createState() => LivePreviewEditorState();
}

class LivePreviewEditorState extends State<LivePreviewEditor> {
  List<MdBlock> _blocks = const [];
  int _active = -1;
  final _blockController = TextEditingController();
  final _blockFocus = FocusNode();
  bool _syncing = false;
  String _lastDocText = '';
  int _hover = -1;

  /// 현재 편집 중인 블록의 컨트롤러 (없으면 null)
  TextEditingController? get activeController => _active >= 0 ? _blockController : null;

  MdBlock? get activeBlock => _active >= 0 && _active < _blocks.length ? _blocks[_active] : null;

  @override
  void initState() {
    super.initState();
    _lastDocText = widget.document.text;
    _blocks = MarkdownBlocks.split(_lastDocText);
    widget.document.addListener(_onDocumentChanged);
    _blockController.addListener(_onBlockChanged);
  }

  @override
  void didUpdateWidget(covariant LivePreviewEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
      _lastDocText = widget.document.text;
      _blocks = MarkdownBlocks.split(_lastDocText);
      _active = -1;
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChanged);
    _blockController.removeListener(_onBlockChanged);
    _blockController.dispose();
    _blockFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sync: block field ↔ whole document
  // ---------------------------------------------------------------------------

  void _onBlockChanged() {
    if (_syncing || _active < 0 || _active >= _blocks.length) return;
    final block = _blocks[_active];
    final newText = _blockController.text;
    if (newText == block.text) return;

    final doc = widget.document.text.replaceRange(block.start, block.end, newText);
    final local = _blockController.selection.isValid ? _blockController.selection.extentOffset : newText.length;
    final cursor = (block.start + local).clamp(0, doc.length);

    _setDocument(doc, cursor);
    _resplit(cursor);
  }

  void _setDocument(String text, int cursor) {
    _syncing = true;
    try {
      widget.document.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
      );
      _lastDocText = text;
    } finally {
      _syncing = false;
    }
  }

  /// 문서를 다시 블록으로 나누고 [cursor] 가 들어 있는 블록을 활성화한다.
  void _resplit(int cursor, {bool keepActive = true}) {
    var blocks = MarkdownBlocks.split(widget.document.text);
    var idx = -1;
    if (keepActive) {
      idx = MarkdownBlocks.indexAt(blocks, cursor);
      if (idx < 0) {
        final (withVirtual, vIdx) = MarkdownBlocks.withVirtualAt(blocks, cursor);
        blocks = withVirtual;
        idx = vIdx;
      }
    }

    setState(() {
      _blocks = blocks;
      _active = idx;
    });

    if (idx >= 0) {
      final block = blocks[idx];
      final local = (cursor - block.start).clamp(0, block.text.length);
      if (_blockController.text != block.text || _blockController.selection.extentOffset != local) {
        _syncing = true;
        try {
          _blockController.value = TextEditingValue(
            text: block.text,
            selection: TextSelection.collapsed(offset: local),
          );
        } finally {
          _syncing = false;
        }
      }
    }
  }

  void _onDocumentChanged() {
    if (_syncing) return;
    final text = widget.document.text;
    if (text == _lastDocText) return; // 선택만 바뀐 경우
    _lastDocText = text;

    final sel = widget.document.selection;
    final cursor = sel.isValid ? sel.extentOffset : -1;
    if (_active >= 0 && cursor >= 0) {
      _resplit(cursor);
    } else {
      setState(() {
        _blocks = MarkdownBlocks.split(text);
        _active = -1;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Public API (toolbar 등)
  // ---------------------------------------------------------------------------

  /// 활성 블록에 편집 동작을 적용한다. 활성 블록이 없으면 문서 끝에 새 블록을 연다.
  void applyToActive(SnippetApply apply) {
    if (_active < 0) activateAtEnd();
    _blockController.value = apply(_blockController.value);
    _blockFocus.requestFocus();
  }

  /// 문서 끝에 빈 블록을 열어 편집을 시작한다.
  void activateAtEnd() {
    var doc = widget.document.text;
    if (doc.isNotEmpty && !doc.endsWith('\n\n')) {
      doc = doc.endsWith('\n') ? '$doc\n' : '$doc\n\n';
      _setDocument(doc, doc.length);
    }
    _resplit(doc.length);
    _blockFocus.requestFocus();
  }

  /// 블록 [idx] 를 편집 상태로 만든다.
  void _activate(int idx, {bool atEnd = true}) {
    if (idx < 0 || idx >= _blocks.length) return;
    final block = _blocks[idx];
    final cursor = atEnd ? block.end : block.start;
    _resplit(cursor);
    _blockFocus.requestFocus();
  }

  void _deactivate() {
    if (_active < 0) return;
    setState(() {
      _blocks = MarkdownBlocks.split(widget.document.text);
      _active = -1;
    });
    _blockFocus.unfocus();
  }

  void _navigatePrev() {
    if (_active <= 0) return;
    _activate(_active - 1, atEnd: true);
  }

  void _navigateNext() {
    if (_active < 0 || _active >= _blocks.length - 1) return;
    _activate(_active + 1, atEnd: false);
  }

  /// 블록 맨 앞에서 Backspace: 이전 블록과의 빈 줄을 지워 합친다.
  void _mergeWithPrevious() {
    if (_active <= 0) return;
    final prev = _blocks[_active - 1];
    final cur = _blocks[_active];
    if (cur.start <= prev.end) return;
    final doc = widget.document.text.replaceRange(prev.end, cur.start, '\n');
    // 줄바꿈 하나만 남기면 같은 문단으로 이어진다. 제목/코드 등은 다시 분리된다.
    _setDocument(doc, prev.end);
    _resplit(prev.end);
    _blockFocus.requestFocus();
  }

  /// 블록 맨 뒤에서 Delete: 다음 블록과 합친다.
  void _mergeWithNext() {
    if (_active < 0 || _active >= _blocks.length - 1) return;
    final cur = _blocks[_active];
    final next = _blocks[_active + 1];
    if (next.start <= cur.end) return;
    final doc = widget.document.text.replaceRange(cur.end, next.start, '\n');
    _setDocument(doc, cur.end);
    _resplit(cur.end);
    _blockFocus.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final skin = widget.theme.skin;
    final children = <Widget>[];

    if (widget.header != null) children.add(widget.header!);

    if (_blocks.isEmpty) {
      children.add(_EmptyHint(color: skin.mutedText, onTap: activateAtEnd));
    } else {
      for (var i = 0; i < _blocks.length; i++) {
        children.add(i == _active ? _buildActiveBlock(_blocks[i]) : _buildRenderedBlock(i, _blocks[i]));
      }
    }

    return Container(
      color: skin.background,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _deactivate,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...children,
                  // 문서 끝: 클릭하면 새 블록
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: activateAtEnd,
                    child: SizedBox(
                      height: 160,
                      child: _blocks.isEmpty
                          ? null
                          : Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  '+ 여기를 클릭해 이어서 쓰기',
                                  style: TextStyle(color: skin.mutedText.withValues(alpha: 0.6), fontSize: 12),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRenderedBlock(int index, MdBlock block) {
    final skin = widget.theme.skin;
    final hovered = _hover == index;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = index),
      onExit: (_) => setState(() => _hover = -1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _activate(index, atEnd: true),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: hovered ? skin.primary.withValues(alpha: 0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: hovered ? skin.primary.withValues(alpha: 0.5) : Colors.transparent, width: 2)),
          ),
          child: block.type == MdBlockType.br
              ? const SizedBox(height: 14)
              : BlogMarkdownBody(markdown: block.text, theme: widget.theme, fontSize: widget.fontSize),
        ),
      ),
    );
  }

  Widget _buildActiveBlock(MdBlock block) {
    final skin = widget.theme.skin;
    final fs = widget.fontSize;

    TextStyle style;
    BoxDecoration decoration;
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    Widget? label;

    switch (block.type) {
      case MdBlockType.heading:
        final level = block.headingLevel;
        final size = switch (level) { 1 => fs * 1.9, 2 => fs * 1.55, 3 => fs * 1.3, 4 => fs * 1.12, _ => fs };
        style = TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: skin.text, height: 1.3);
        decoration = _outline(skin);
      case MdBlockType.code:
        style = TextStyle(
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['Courier New', 'monospace'],
          fontSize: fs - 1.5,
          color: const Color(0xFFECEFF1),
          height: 1.5,
        );
        decoration = BoxDecoration(
          color: const Color(0xFF263238),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: skin.primary, width: 1.5),
        );
        padding = const EdgeInsets.all(14);
      case MdBlockType.html:
        final cls = block.htmlClassName;
        final bs = cls == null ? null : widget.theme.styleFor(cls);
        final accent = bs?.headerBackground ?? bs?.borderColor ?? skin.primary;
        style = TextStyle(
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['Malgun Gothic', 'Courier New', 'monospace'],
          fontSize: fs - 1,
          color: skin.text,
          height: 1.6,
        );
        decoration = BoxDecoration(
          color: bs?.backgroundColor ?? Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent, width: 1.5),
        );
        padding = const EdgeInsets.fromLTRB(12, 8, 12, 10);
        label = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: accent,
          child: Row(
            children: [
              Icon(Icons.code, size: 13, color: bs?.headerTextColor ?? Colors.white),
              const SizedBox(width: 6),
              Text(
                cls ?? 'HTML',
                style: TextStyle(fontSize: 11, color: bs?.headerTextColor ?? Colors.white, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text('Esc 로 렌더링 보기', style: TextStyle(fontSize: 10, color: (bs?.headerTextColor ?? Colors.white).withValues(alpha: 0.8))),
            ],
          ),
        );
      case MdBlockType.paragraph:
      case MdBlockType.hr:
      case MdBlockType.br:
        style = TextStyle(fontSize: fs, color: skin.text, height: 1.75);
        decoration = _outline(skin);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) label,
          MarkdownEditor(
            controller: _blockController,
            focusNode: _blockFocus,
            shortcuts: widget.shortcuts,
            onSave: widget.onSave,
            expands: false,
            autofocus: true,
            style: style,
            contentPadding: padding,
            hintText: block.virtual ? '내용을 입력하세요' : '',
            paragraphEnter: block.type != MdBlockType.code && block.type != MdBlockType.html,
            onNavigatePrev: _navigatePrev,
            onNavigateNext: _navigateNext,
            onBackspaceAtStart: _mergeWithPrevious,
            onDeleteAtEnd: _mergeWithNext,
            onEscape: _deactivate,
          ),
        ],
      ),
    );
  }

  BoxDecoration _outline(BlogSkin skin) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: skin.primary.withValues(alpha: 0.7), width: 1.5),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _EmptyHint({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '여기를 클릭해 글을 쓰기 시작하세요. 마크다운과 블로그 태그를 그대로 쓸 수 있습니다.',
          style: TextStyle(color: color, fontSize: 15),
        ),
      ),
    );
  }
}
