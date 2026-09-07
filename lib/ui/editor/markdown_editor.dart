import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_actions.dart';

/// 단축키 하나에 대응하는 편집 동작
typedef EditorShortcutHandler = TextEditingValue Function(TextEditingValue value);

/// 일반 텍스트 편집기처럼 동작하는 마크다운 입력 위젯.
///
/// - Tab / Shift+Tab 들여쓰기, Enter 시 목록 마커 이어가기
/// - Alt+↑/↓ 줄 이동, Ctrl+Shift+D 줄 복제
/// - 외부에서 넘긴 [shortcuts] (Ctrl+B 등) 처리
/// - Ctrl+Z / Ctrl+Y 되돌리기는 TextField 기본 동작 사용
///
/// 라이브 편집 모드에서는 블록 하나를 담는 작은 필드로도 쓰인다. 이때
/// [onNavigatePrev]/[onNavigateNext]/[onBackspaceAtStart]/[onDeleteAtEnd]/[onEscape] 로
/// 블록 사이 이동을 바깥에 알린다.
class MarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final UndoHistoryController? undoController;
  final Map<ShortcutActivator, EditorShortcutHandler> shortcuts;
  final VoidCallback? onSave;
  final double fontSize;
  final bool monospace;
  final ScrollController? scrollController;

  /// true 면 부모를 가득 채우는 전체 문서 편집기, false 면 내용 높이만큼 자라는 블록 필드
  final bool expands;
  final TextStyle? style;
  final EdgeInsets? contentPadding;
  final String? hintText;
  final bool autofocus;

  /// 커서가 첫 줄에 있을 때 ↑ (또는 마지막 줄에서 ↓)
  final VoidCallback? onNavigatePrev;
  final VoidCallback? onNavigateNext;

  /// 커서가 맨 앞일 때 Backspace / 맨 뒤일 때 Delete
  final VoidCallback? onBackspaceAtStart;
  final VoidCallback? onDeleteAtEnd;
  final VoidCallback? onEscape;

  /// true 면 Enter 가 새 문단(빈 줄)을 만들고 Shift+Enter 가 `<br>` 줄바꿈을 넣는다 (라이브 편집의 문단 블록)
  final bool paragraphEnter;

  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.undoController,
    this.shortcuts = const {},
    this.onSave,
    this.fontSize = 15,
    this.monospace = true,
    this.scrollController,
    this.expands = true,
    this.style,
    this.contentPadding,
    this.hintText,
    this.autofocus = false,
    this.onNavigatePrev,
    this.onNavigateNext,
    this.onBackspaceAtStart,
    this.onDeleteAtEnd,
    this.onEscape,
    this.paragraphEnter = false,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    var value = widget.controller.value;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final shift = keyboard.isShiftPressed;
    final alt = keyboard.isAltPressed;
    final key = event.logicalKey;
    final plain = !ctrl && !shift && !alt;
    final isEnter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

    // 한글 등 IME 조합 중에는 개입하지 않는다 (조합이 깨지지 않도록).
    // 단, Enter 는 조합을 확정한 뒤 바로 줄바꿈까지 처리해 "Enter 두 번" 을 없앤다.
    if (value.composing.isValid && !value.composing.isCollapsed) {
      if (!isEnter || ctrl || alt) return KeyEventResult.ignored;
      value = TextEditingValue(text: value.text, selection: value.selection);
      widget.controller.value = value;
    }

    // 저장
    if (ctrl && !shift && !alt && key == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return KeyEventResult.handled;
    }

    // 외부 단축키 (Ctrl+B 등)
    for (final entry in widget.shortcuts.entries) {
      if (entry.key.accepts(event, keyboard)) {
        _apply(entry.value(value));
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.escape && widget.onEscape != null) {
      widget.onEscape!();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.tab && !ctrl && !alt) {
      _apply(shift ? EditorActions.outdent(value) : EditorActions.indent(value));
      return KeyEventResult.handled;
    }

    if (isEnter && plain) {
      _apply(EditorActions.handleEnter(value, paragraphBreak: widget.paragraphEnter));
      return KeyEventResult.handled;
    }
    if (isEnter && shift && !ctrl && !alt && widget.paragraphEnter) {
      _apply(EditorActions.hardBreak(value));
      return KeyEventResult.handled;
    }

    if (alt && !ctrl && !shift && key == LogicalKeyboardKey.arrowUp) {
      _apply(EditorActions.moveLines(value, up: true));
      return KeyEventResult.handled;
    }
    if (alt && !ctrl && !shift && key == LogicalKeyboardKey.arrowDown) {
      _apply(EditorActions.moveLines(value, up: false));
      return KeyEventResult.handled;
    }
    if (ctrl && shift && !alt && key == LogicalKeyboardKey.keyD) {
      _apply(EditorActions.duplicateLines(value));
      return KeyEventResult.handled;
    }

    // 블록 사이 이동 (라이브 편집)
    final sel = value.selection;
    if (sel.isValid && sel.isCollapsed) {
      final offset = sel.extentOffset;
      final text = value.text;
      if (plain && key == LogicalKeyboardKey.arrowUp && widget.onNavigatePrev != null && !text.substring(0, offset).contains('\n')) {
        widget.onNavigatePrev!();
        return KeyEventResult.handled;
      }
      if (plain && key == LogicalKeyboardKey.arrowDown && widget.onNavigateNext != null && !text.substring(offset).contains('\n')) {
        widget.onNavigateNext!();
        return KeyEventResult.handled;
      }
      if (plain && key == LogicalKeyboardKey.backspace && widget.onBackspaceAtStart != null && offset == 0) {
        widget.onBackspaceAtStart!();
        return KeyEventResult.handled;
      }
      if (plain && key == LogicalKeyboardKey.delete && widget.onDeleteAtEnd != null && offset == text.length) {
        widget.onDeleteAtEnd!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _apply(TextEditingValue next) {
    if (next == widget.controller.value) return;
    widget.controller.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ??
        TextStyle(
          fontSize: widget.fontSize,
          height: 1.6,
          color: const Color(0xFF2B3634),
          fontFamily: widget.monospace ? 'Consolas' : null,
          fontFamilyFallback: widget.monospace ? const ['Malgun Gothic', 'Courier New', 'monospace'] : null,
        );

    return Focus(
      onKeyEvent: _onKeyEvent,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        undoController: widget.undoController,
        scrollController: widget.scrollController,
        autofocus: widget.autofocus,
        maxLines: null,
        expands: widget.expands,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: style,
        cursorColor: const Color(0xFF11999E),
        cursorWidth: 2,
        scrollPadding: const EdgeInsets.all(48),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: widget.contentPadding ?? const EdgeInsets.fromLTRB(24, 20, 24, 120),
          hintText: widget.hintText ?? '여기에 글을 쓰세요. 마크다운과 블로그 커스텀 태그를 그대로 사용할 수 있습니다.',
          hintStyle: const TextStyle(color: Color(0xFFA0AAA8)),
          isCollapsed: true,
        ),
      ),
    );
  }
}
