import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../models/jekyll_post.dart';
import '../../models/jekyll_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/blog_repository.dart';
import '../editor/blog_preview.dart';
import '../editor/editor_actions.dart';
import '../editor/editor_snippets.dart';
import '../editor/editor_toolbar.dart';
import '../editor/live_preview_editor.dart';
import '../editor/markdown_editor.dart';
import '../widgets/git_publish_flow.dart';

enum EditorViewMode { live, edit, split, preview }

/// 지킬 포스트 한 편을 편집하는 화면.
///
/// [post]가 null 이면 새 글. 저장 시 파일명은 `YYYY-MM-DD-[주제] 제목.md` 규칙으로 만든다.
/// 저장소가 로컬이면 파일에 쓰고, GitHub 이면 커밋한다.
class PostEditor extends ConsumerStatefulWidget {
  final PostInfo? post;
  final BlogRepository repository;
  final JekyllTheme theme;
  final PostTemplate? initialTemplate;
  final void Function(String name) onSaved;
  final void Function(String name) onDeleted;
  final void Function(bool dirty)? onDirtyChanged;

  const PostEditor({
    super.key,
    required this.post,
    required this.repository,
    required this.theme,
    this.initialTemplate,
    required this.onSaved,
    required this.onDeleted,
    this.onDirtyChanged,
  });

  @override
  ConsumerState<PostEditor> createState() => PostEditorState();
}

class PostEditorState extends ConsumerState<PostEditor> {
  late JekyllPost _post;
  String? _name;
  bool _isDraft = false;
  DateTime _date = DateTime.now();

  final _subjectController = TextEditingController();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _tagInputController = TextEditingController();
  final _bodyController = TextEditingController();
  final _bodyFocus = FocusNode();
  final _categoryFocus = FocusNode();
  final _tagFocus = FocusNode();
  final _undoController = UndoHistoryController();
  final _editorScroll = ScrollController();
  final _previewScroll = ScrollController();

  EditorViewMode _viewMode = EditorViewMode.live;
  final _liveKey = GlobalKey<LivePreviewEditorState>();
  double _fontSize = 15;
  bool _monospace = true;
  bool _dirty = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String _previewMarkdown = '';
  Timer? _previewDebounce;
  (int, int) _cursor = (1, 1);

  bool get isDirty => _dirty;
  String? get name => _name;
  BlogRepository get _repo => widget.repository;

  late final Map<ShortcutActivator, EditorShortcutHandler> _shortcuts = {
    const SingleActivator(LogicalKeyboardKey.keyB, control: true): EditorSnippets.bold,
    const SingleActivator(LogicalKeyboardKey.keyI, control: true): EditorSnippets.italic,
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): EditorSnippets.inlineCode,
    const SingleActivator(LogicalKeyboardKey.keyX, control: true, shift: true): EditorSnippets.strike,
    const SingleActivator(LogicalKeyboardKey.digit1, control: true): (v) => EditorActions.toggleHeading(v, 1),
    const SingleActivator(LogicalKeyboardKey.digit2, control: true): (v) => EditorActions.toggleHeading(v, 2),
    const SingleActivator(LogicalKeyboardKey.digit3, control: true): (v) => EditorActions.toggleHeading(v, 3),
    const SingleActivator(LogicalKeyboardKey.digit4, control: true): (v) => EditorActions.toggleHeading(v, 4),
    const SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true): EditorActions.toggleBulletList,
    const SingleActivator(LogicalKeyboardKey.keyQ, control: true, shift: true): EditorActions.toggleQuote,
  };

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(_onBodyChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant PostEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post?.name != widget.post?.name) {
      _load();
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _bodyController.removeListener(_onBodyChanged);
    _subjectController.dispose();
    _titleController.dispose();
    _categoryController.dispose();
    _tagInputController.dispose();
    _bodyController.dispose();
    _bodyFocus.dispose();
    _categoryFocus.dispose();
    _tagFocus.dispose();
    _undoController.dispose();
    _editorScroll.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading / dirty tracking
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    _name = widget.post?.name;
    try {
      if (_name == null) {
        _post = JekyllPost(body: widget.initialTemplate?.body ?? '');
        _isDraft = false;
        _date = DateTime.now();
      } else {
        final raw = await _repo.readPost(_name!);
        _post = JekyllPost.parse(raw);
        _isDraft = JekyllPost.isDraftFileName(_name!);
        _date = JekyllPost.dateFromFileName(_name!) ?? DateTime.now();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
      return;
    }
    if (!mounted) return;

    _subjectController.text = _post.subject;
    _titleController.text = _post.title;
    _categoryController.text = _post.category;
    _bodyController.value = TextEditingValue(
      text: _post.body,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _previewMarkdown = _post.body;
    _setDirty(false);

    setState(() => _loading = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _viewMode == EditorViewMode.edit) _bodyFocus.requestFocus();
    });
  }

  void _onBodyChanged() {
    final cursor = EditorActions.cursorPosition(_bodyController.value);
    if (cursor != _cursor) {
      setState(() => _cursor = cursor);
    }
    if (_bodyController.text != _post.body) {
      _post.body = _bodyController.text;
      _setDirty(true);
      _previewDebounce?.cancel();
      _previewDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() => _previewMarkdown = _bodyController.text);
      });
    }
  }

  void _setDirty(bool value) {
    if (_dirty == value) return;
    _dirty = value;
    widget.onDirtyChanged?.call(value);
    if (mounted) setState(() {});
  }

  void _syncMetaFromFields() {
    _post.subject = _subjectController.text.trim();
    _post.title = _titleController.text.trim();
    _post.category = _categoryController.text.trim();
  }

  // ---------------------------------------------------------------------------
  // Editing helpers
  // ---------------------------------------------------------------------------

  bool get _isLive => _viewMode == EditorViewMode.live;

  /// 툴바/단축키가 바라보는 현재 편집 값 (라이브 모드면 활성 블록)
  TextEditingValue get _currentValue {
    if (_isLive) {
      final active = _liveKey.currentState?.activeController;
      if (active != null) return active.value;
    }
    return _bodyController.value;
  }

  void _apply(SnippetApply apply) {
    if (_isLive && _liveKey.currentState != null) {
      _liveKey.currentState!.applyToActive(apply);
      return;
    }
    final next = apply(_bodyController.value);
    _bodyController.value = next;
    _bodyFocus.requestFocus();
  }

  Future<void> _insertLink() async {
    final value = _currentValue;
    final selected = value.selection.isValid ? value.text.substring(value.selection.start, value.selection.end) : '';
    if (RegExp(r'^https?://\S+$').hasMatch(selected.trim())) {
      _apply(EditorSnippets.link);
      return;
    }

    final urlController = TextEditingController();
    final textController = TextEditingController(text: selected);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('링크 삽입'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'URL', hintText: 'https://', border: OutlineInputBorder()),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                decoration: const InputDecoration(labelText: '표시할 텍스트 (비우면 URL)', border: OutlineInputBorder()),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삽입')),
        ],
      ),
    );

    if (result == true) {
      final url = urlController.text.trim();
      final text = textController.text.trim().isEmpty ? url : textController.text.trim();
      _apply((v) => EditorActions.insert(v, '[$text]($url)'));
    }
    urlController.dispose();
    textController.dispose();
  }

  Future<void> _insertCodeBlock() async {
    const languages = ['cpp', 'csharp', 'python', 'javascript', 'typescript', 'bash', 'yaml', 'json', 'html', 'css', 'text'];
    final language = await showDialog<String>(
      context: context,
      builder: (context) {
        final custom = TextEditingController();
        return AlertDialog(
          title: const Text('코드 블록 언어'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final l in languages) ActionChip(label: Text(l), onPressed: () => Navigator.pop(context, l)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: custom,
                  decoration: const InputDecoration(labelText: '직접 입력', border: OutlineInputBorder(), isDense: true),
                  onSubmitted: (v) => Navigator.pop(context, v.trim()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, custom.text.trim()), child: const Text('삽입')),
          ],
        );
      },
    );
    if (language == null) return;
    _apply((v) => EditorActions.codeFence(v, language: language));
  }

  Future<void> _insertImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final buffer = StringBuffer();
    for (final file in result.files) {
      try {
        var bytes = file.bytes;
        if (bytes == null && !kIsWeb && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }
        if (bytes == null) continue;
        final safeName = file.name.replaceAll(RegExp(r'[^\w.\-가-힣]+'), '_');
        _snack('이미지 업로드 중: $safeName');
        final rel = await _repo.uploadImage(safeName, bytes);
        final alt = safeName.replaceFirst(RegExp(r'\.[^.]+$'), '');
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write('![$alt]($rel)');
      } catch (e) {
        _snack('이미지 업로드 실패: $e', error: true);
      }
    }
    if (buffer.isNotEmpty) {
      _apply((v) => EditorActions.insertBlock(v, buffer.toString()));
    }
  }

  void _insertTemplate(PostTemplate template) {
    _apply((v) => EditorActions.insertBlock(v, template.body.trim()));
  }

  void _addTag(String raw) {
    final parts = raw.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    var changed = false;
    for (final t in parts) {
      if (!_post.tags.contains(t)) {
        _post.tags.add(t);
        changed = true;
      }
    }
    _tagInputController.clear();
    if (changed) {
      _setDirty(true);
      setState(() {});
    }
  }

  void _removeTag(String tag) {
    _post.tags.remove(tag);
    _setDirty(true);
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Save / delete / preview
  // ---------------------------------------------------------------------------

  String get _targetFileName {
    _syncMetaFromFields();
    if (_name != null) {
      if (JekyllPost.isTemplateFileName(_name!)) return _name!;
      return JekyllPost.toggleDraftFileName(_name!, draft: _isDraft);
    }
    return JekyllPost.buildFileName(date: _date, fullTitle: _post.fullTitle, draft: _isDraft);
  }

  Future<bool> save() async {
    if (_saving) return false;
    _syncMetaFromFields();

    if (_post.fullTitle.isEmpty) {
      _snack('제목을 입력해주세요.', error: true);
      return false;
    }

    setState(() => _saving = true);
    try {
      final targetName = _targetFileName;
      final isRename = _name != null && _name != targetName;
      if ((_name == null || isRename) && await _repo.postExists(targetName)) {
        _snack('같은 이름의 파일이 이미 있습니다: $targetName', error: true);
        return false;
      }

      // 새 글은 최근 포스트처럼 date / published 를 채운다
      if (_name == null || !_post.hasFrontmatterKey('date')) {
        _post.ensurePublishFields(_date);
      }

      await _repo.writePost(targetName, _post.serialize(), previousName: isRename ? _name : null);

      _name = targetName;
      _setDirty(false);
      widget.onSaved(targetName);
      _snack(_repo.isLocal ? '저장했습니다 · $targetName' : 'GitHub에 커밋했습니다 · $targetName');
      return true;
    } catch (e) {
      _snack('저장 실패: $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 다른 글로 이동하기 전에 호출. 저장하지 않은 변경이 있으면 물어본다.
  Future<bool> confirmLeave() async {
    if (!_dirty) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장하지 않은 변경이 있습니다'),
        content: Text('"${_titleController.text.isEmpty ? '제목 없음' : _titleController.text}" 의 변경 사항을 저장할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('버리기')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('저장')),
        ],
      ),
    );
    if (result == 'save') return await save();
    return result == 'discard';
  }

  Future<void> _delete() async {
    if (_name == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('포스트 삭제'),
        content: Text('$_name\n\n이 글을 삭제할까요? ${_repo.isLocal ? '되돌릴 수 없습니다.' : 'GitHub에 삭제 커밋이 만들어집니다.'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final name = _name!;
      await _repo.deletePost(name);
      _setDirty(false);
      widget.onDeleted(name);
    } catch (e) {
      _snack('삭제 실패: $e', error: true);
    }
  }

  Future<void> _openInBrowser() async {
    if (_dirty || _name == null) {
      final saved = await save();
      if (!saved) return;
    }
    final name = _name!;

    String path = '/';
    var published = JekyllPost.isPublishedFileName(name);
    if (published) {
      path = JekyllPost.localUrlPath(
        fileName: name,
        category: _post.category,
        permalinkPattern: widget.theme.permalinkPattern,
      );
    } else {
      _snack('초안(m 접두어) 파일은 사이트에 표시되지 않습니다. 블로그 홈을 엽니다.');
    }

    if (_repo.isLocal) {
      final jekyll = ref.read(jekyllServiceProvider);
      _snack('Jekyll 서버 확인 중...');
      final running = await jekyll.ensureRunning();
      if (!running) {
        _snack(AppConstants.errorJekyllServerFailed, error: true);
        return;
      }
      await launchUrl(Uri.parse('${AppConstants.jekyllServerUrl}$path'), mode: LaunchMode.externalApplication);
      return;
    }

    final site = widget.theme.siteUrl;
    if (site.isEmpty) {
      _snack('_config.yml 에 url 이 없어 사이트 주소를 알 수 없습니다.', error: true);
      return;
    }
    _snack('게시된 사이트를 엽니다. 방금 커밋한 내용은 GitHub Pages 빌드 후(1~2분) 반영됩니다.');
    await launchUrl(Uri.parse('$site$path'), mode: LaunchMode.externalApplication);
  }

  Future<void> _publish() async {
    if (_dirty) {
      final saved = await save();
      if (!saved) return;
    }
    if (!mounted) return;
    await runGitPublishFlow(context, ref.read(jekyllBlogPathProvider));
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red[700] : null,
        duration: Duration(seconds: error ? 4 : 2),
      ));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('글을 열 수 없습니다\n$_loadError', textAlign: TextAlign.center),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact && _viewMode == EditorViewMode.split) {
          _viewMode = EditorViewMode.live;
        }
        return Column(
          children: [
            compact ? _buildCompactMetaBar(context) : _buildMetaBar(context),
            EditorToolbar(
              theme: widget.theme,
              onApply: _apply,
              onInsertImage: _insertImage,
              onInsertLink: _insertLink,
              onInsertCodeBlock: _insertCodeBlock,
              onInsertTemplate: _insertTemplate,
            ),
            Expanded(child: _buildBody(compact)),
            _buildStatusBar(context, compact),
          ],
        );
      },
    );
  }

  Widget _buildMetaBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fileName = _name ?? _targetFileName;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 150, child: _subjectField()),
              const SizedBox(width: 10),
              Expanded(child: _titleField(fontSize: 22)),
              const SizedBox(width: 12),
              _buildStatusChip(scheme),
              const SizedBox(width: 12),
              _buildViewModeToggle(compact: false),
              const SizedBox(width: 8),
              Tooltip(
                message: _repo.isLocal ? '브라우저에서 보기 (Jekyll 서버 자동 시작)' : '게시된 사이트에서 보기',
                child: IconButton.outlined(onPressed: _openInBrowser, icon: const Icon(Icons.open_in_browser)),
              ),
              const SizedBox(width: 6),
              _saveButton(),
              const SizedBox(width: 6),
              _moreMenu(),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(width: 210, child: _buildCategoryField()),
              const SizedBox(width: 10),
              Expanded(child: _buildTagsField()),
              const SizedBox(width: 10),
              if (_name == null) _dateButton(),
              const SizedBox(width: 10),
              _draftSwitch(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(_repo.isLocal ? Icons.insert_drive_file_outlined : Icons.cloud_outlined, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _repo.isLocal ? fileName : '${_repo.location} · $fileName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 좁은 화면(모바일)용 메타 바
  Widget _buildCompactMetaBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildStatusChip(scheme),
              const Spacer(),
              _buildViewModeToggle(compact: true),
              const SizedBox(width: 4),
              IconButton(onPressed: _openInBrowser, icon: const Icon(Icons.open_in_browser), tooltip: '사이트에서 보기'),
              _saveButton(),
              _moreMenu(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(width: 110, child: _subjectField()),
              const SizedBox(width: 8),
              Expanded(child: _titleField(fontSize: 18)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildCategoryField()),
              const SizedBox(width: 8),
              if (_name == null) _dateButton(),
              _draftSwitch(),
            ],
          ),
          const SizedBox(height: 8),
          _buildTagsField(),
        ],
      ),
    );
  }

  Widget _subjectField() {
    return TextField(
      controller: _subjectController,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: const InputDecoration(
        prefixText: '[ ',
        suffixText: ' ]',
        hintText: '주제',
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: (_) => _setDirty(true),
    );
  }

  Widget _titleField({required double fontSize}) {
    return TextField(
      controller: _titleController,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
      decoration: const InputDecoration(
        hintText: '제목을 입력하세요',
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 6),
      ),
      onChanged: (_) => _setDirty(true),
      onSubmitted: (_) => _bodyFocus.requestFocus(),
    );
  }

  Widget _saveButton() {
    return FilledButton.icon(
      onPressed: _saving ? null : save,
      icon: _saving
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.save_outlined, size: 18),
      label: Text(_repo.isLocal ? '저장' : '커밋'),
    );
  }

  Widget _moreMenu() {
    return PopupMenuButton<String>(
      tooltip: '더 보기',
      onSelected: (v) {
        switch (v) {
          case 'publish':
            _publish();
          case 'delete':
            _delete();
          case 'reveal':
            if (_name != null && _repo.isLocal) {
              Process.run('explorer', ['/select,', '${_repo.location}\\${AppConstants.defaultPostsFolder}\\$_name']);
            }
        }
      },
      itemBuilder: (context) => [
        if (_repo.isLocal)
          const PopupMenuItem(value: 'publish', child: ListTile(leading: Icon(Icons.cloud_upload_outlined), title: Text('GitHub에 업로드 (commit & push)'), dense: true)),
        if (_name != null && _repo.isLocal && !kIsWeb && Platform.isWindows)
          const PopupMenuItem(value: 'reveal', child: ListTile(leading: Icon(Icons.folder_open_outlined), title: Text('탐색기에서 보기'), dense: true)),
        if (_name != null) const PopupMenuDivider(),
        if (_name != null)
          const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('삭제', style: TextStyle(color: Colors.red)), dense: true)),
      ],
    );
  }

  Widget _dateButton() {
    return Tooltip(
      message: '게시 날짜 (파일명에 사용)',
      child: OutlinedButton.icon(
        onPressed: () async {
          final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (picked != null) setState(() => _date = picked);
        },
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
      ),
    );
  }

  Widget _draftSwitch() {
    return Tooltip(
      message: '초안으로 표시하면 파일명 앞에 m 을 붙여 Jekyll 이 게시하지 않게 합니다',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: _isDraft,
            onChanged: (v) {
              setState(() => _isDraft = v);
              _setDirty(true);
            },
          ),
          const Text('초안', style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusChip(ColorScheme scheme) {
    final label = _dirty ? '수정됨' : (_repo.isLocal ? '저장됨' : '커밋됨');
    final color = _dirty ? Colors.orange[800]! : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_dirty ? Icons.edit_outlined : Icons.check, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle({required bool compact}) {
    return SegmentedButton<EditorViewMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        const ButtonSegment(value: EditorViewMode.live, icon: Icon(Icons.auto_fix_high, size: 18), tooltip: '라이브 편집 (블로그 화면에서 바로 수정)'),
        const ButtonSegment(value: EditorViewMode.edit, icon: Icon(Icons.code, size: 18), tooltip: '소스 편집'),
        if (!compact) const ButtonSegment(value: EditorViewMode.split, icon: Icon(Icons.vertical_split, size: 18), tooltip: '소스 + 미리보기'),
        const ButtonSegment(value: EditorViewMode.preview, icon: Icon(Icons.visibility_outlined, size: 18), tooltip: '미리보기만'),
      ],
      selected: {_viewMode},
      onSelectionChanged: (s) => setState(() => _viewMode = s.first),
    );
  }

  Widget _buildCategoryField() {
    final categories = widget.theme.categories;
    return RawAutocomplete<BlogCategory>(
      textEditingController: _categoryController,
      focusNode: _categoryFocus,
      displayStringForOption: (c) => c.slug,
      optionsBuilder: (value) {
        final q = value.text.toLowerCase();
        if (q.isEmpty) return categories;
        return categories.where((c) => c.slug.toLowerCase().contains(q) || c.title.toLowerCase().contains(q));
      },
      onSelected: (c) {
        _categoryController.text = c.slug;
        _setDirty(true);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.folder_outlined, size: 18),
            hintText: '카테고리',
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          onChanged: (_) => _setDirty(true),
          onSubmitted: (_) => onSubmit(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 260),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final c in options)
                    ListTile(
                      dense: true,
                      title: Text(c.slug),
                      subtitle: c.title != c.slug ? Text(c.title, style: const TextStyle(fontSize: 11)) : null,
                      onTap: () => onSelected(c),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagsField() {
    final suggestions = widget.theme.tags;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.sell_outlined, size: 16, color: Color(0xFF6B7A77)),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in _post.tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InputChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => _removeTag(t),
                      ),
                    ),
                  SizedBox(
                    width: 200,
                    child: RawAutocomplete<String>(
                      textEditingController: _tagInputController,
                      focusNode: _tagFocus,
                      optionsBuilder: (value) {
                        final q = value.text.trim().toLowerCase();
                        if (q.isEmpty) return const Iterable<String>.empty();
                        return suggestions.where((t) => t.toLowerCase().contains(q) && !_post.tags.contains(t)).take(8);
                      },
                      onSelected: _addTag,
                      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: '태그 입력 후 Enter (쉼표로 여러 개)',
                            hintStyle: TextStyle(fontSize: 12),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (v) {
                            if (v.endsWith(',')) _addTag(v);
                          },
                          onSubmitted: (v) {
                            _addTag(v);
                            focusNode.requestFocus();
                          },
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(6),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 240),
                              child: ListView(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                children: [
                                  for (final t in options) ListTile(dense: true, title: Text(t), onTap: () => onSelected(t)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<ShortcutActivator, EditorShortcutHandler> get _allShortcuts => {
        ..._shortcuts,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): (v) {
          // 다이얼로그는 비동기이므로 값은 그대로 두고 호출만 한다
          WidgetsBinding.instance.addPostFrameCallback((_) => _insertLink());
          return v;
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true): (v) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _insertCodeBlock());
          return v;
        },
      };

  Widget _buildBody(bool compact) {
    if (_viewMode == EditorViewMode.live) {
      return LivePreviewEditor(
        key: _liveKey,
        document: _bodyController,
        theme: widget.theme,
        shortcuts: _allShortcuts,
        onSave: save,
        fontSize: _fontSize,
        scrollController: _previewScroll,
        horizontalPadding: compact ? 12 : 32,
        header: _fullTitlePreview.isEmpty
            ? null
            : BlogPostHeader(
                theme: widget.theme,
                title: _fullTitlePreview,
                category: _categoryController.text.trim(),
                tags: _post.tags,
                date: _date,
              ),
      );
    }

    final editor = MarkdownEditor(
      controller: _bodyController,
      focusNode: _bodyFocus,
      undoController: _undoController,
      shortcuts: _allShortcuts,
      onSave: save,
      fontSize: _fontSize,
      monospace: _monospace,
      scrollController: _editorScroll,
      contentPadding: compact ? const EdgeInsets.fromLTRB(12, 12, 12, 120) : null,
    );

    final preview = BlogPreview(
      markdown: _previewMarkdown,
      theme: widget.theme,
      title: _fullTitlePreview,
      category: _categoryController.text.trim(),
      tags: _post.tags,
      date: _date,
      scrollController: _previewScroll,
    );

    switch (_viewMode) {
      case EditorViewMode.live:
        throw StateError('unreachable');
      case EditorViewMode.edit:
        return Container(color: Colors.white, child: editor);
      case EditorViewMode.preview:
        return preview;
      case EditorViewMode.split:
        return Row(
          children: [
            Expanded(child: Container(color: Colors.white, child: editor)),
            Container(width: 1, color: const Color(0xFFDDE2E1)),
            Expanded(child: preview),
          ],
        );
    }
  }

  String get _fullTitlePreview {
    final s = _subjectController.text.trim();
    final t = _titleController.text.trim();
    if (s.isEmpty) return t;
    return '[$s] $t';
  }

  Widget _buildStatusBar(BuildContext context, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final text = _bodyController.text;
    final chars = text.length;
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final style = TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Text('줄 ${_cursor.$1}, 열 ${_cursor.$2}', style: style),
          const SizedBox(width: 16),
          Text('$chars자 · $words단어', style: style),
          const Spacer(),
          if (!compact) ...[
            Text('Ctrl+S 저장 · Ctrl+B 굵게 · Ctrl+K 링크 · Tab 들여쓰기 · Alt+↑↓ 줄 이동', style: style),
            const SizedBox(width: 16),
          ],
          Tooltip(
            message: _monospace ? '고정폭 글꼴' : '가변폭 글꼴',
            child: InkWell(
              onTap: () => setState(() => _monospace = !_monospace),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(_monospace ? Icons.code : Icons.text_fields, size: 15, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: '글자 작게',
            onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(11, 24)),
            icon: const Icon(Icons.remove),
          ),
          Text('${_fontSize.round()}', style: style),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: '글자 크게',
            onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(11, 24)),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
