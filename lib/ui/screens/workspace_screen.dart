import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/jekyll_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/blog_repository.dart';
import '../../services/update_service.dart';
import 'obsidian_import_screen.dart';
import 'post_editor_screen.dart';
import 'settings_screen.dart';

enum _Section { posts, import, settings }

enum _PostFilter { all, published, draft, template }

/// 앱의 메인 셸.
///
/// - 넓은 화면(데스크톱): 왼쪽 네비게이션 + 포스트 목록 + 에디터
/// - 좁은 화면(모바일): 하단 탭 + 목록, 글을 누르면 전체 화면 에디터
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  static const double _compactBreakpoint = 820;

  _Section _section = _Section.posts;
  GlobalKey<PostEditorState> _editorKey = GlobalKey<PostEditorState>();

  List<PostInfo> _posts = [];
  bool _loadingPosts = false;
  String? _postsError;
  _PostFilter _filter = _PostFilter.all;
  final _searchController = TextEditingController();

  PostInfo? _openPost;
  bool _creatingNew = false;
  PostTemplate? _newTemplate;
  bool _editorDirty = false;

  AppRelease? _availableUpdate;
  bool _updateDismissed = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPosts();
      _checkForUpdate();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Posts list
  // ---------------------------------------------------------------------------

  Future<void> _loadPosts({bool refresh = false}) async {
    final repo = ref.read(blogRepositoryProvider);
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });

    try {
      if (repo == null) throw BlogRepositoryException('저장소가 설정되지 않았습니다. 설정에서 로컬 폴더 또는 GitHub 정보를 입력하세요.');
      if (refresh) await repo.refresh();
      final entries = await repo.listPosts();
      if (mounted) {
        setState(() {
          _posts = entries;
          _loadingPosts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _posts = [];
          _loadingPosts = false;
          _postsError = e.toString();
        });
      }
    }
  }

  List<PostInfo> get _visiblePosts {
    final q = _searchController.text.trim().toLowerCase();
    return _posts.where((e) {
      switch (_filter) {
        case _PostFilter.all:
          break;
        case _PostFilter.published:
          if (!e.isPublished) return false;
        case _PostFilter.draft:
          if (!e.isDraft) return false;
        case _PostFilter.template:
          if (!e.isTemplate) return false;
      }
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.name.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          e.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Update check
  // ---------------------------------------------------------------------------

  Future<void> _checkForUpdate() async {
    if (kIsWeb) return; // 웹(PWA)은 새로고침으로 항상 최신
    try {
      final release = await ref.read(updateServiceProvider).checkForUpdate();
      if (release != null && mounted) setState(() => _availableUpdate = release);
    } catch (_) {}
  }

  Future<void> _applyUpdate() async {
    final release = _availableUpdate;
    if (release == null) return;
    final asset = release.assetForThisPlatform;
    if (asset == null) {
      await launchUrl(Uri.parse(release.htmlUrl), mode: LaunchMode.externalApplication);
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      final progress = ValueNotifier<double>(0);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('${release.tagName} 내려받는 중'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v > 0 ? v : null),
                const SizedBox(height: 8),
                const Text('내려받기가 끝나면 앱이 종료되고 새 버전으로 다시 실행됩니다.'),
              ],
            ),
          ),
        ),
      );
      try {
        await ref.read(updateServiceProvider).installWindows(asset, onProgress: (v) => progress.value = v);
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('업데이트 실패: $e'), backgroundColor: Colors.red));
        }
      }
      return;
    }

    // Android: APK 를 브라우저로 내려받아 설치
    await launchUrl(Uri.parse(asset.downloadUrl), mode: LaunchMode.externalApplication);
  }

  // ---------------------------------------------------------------------------
  // Editor navigation
  // ---------------------------------------------------------------------------

  Future<bool> _leaveCurrentEditor() async {
    final state = _editorKey.currentState;
    if (state == null) return true;
    return state.confirmLeave();
  }

  Future<void> _openPostInline(PostInfo post) async {
    if (_openPost?.name == post.name && !_creatingNew) return;
    if (!await _leaveCurrentEditor()) return;
    setState(() {
      _section = _Section.posts;
      _openPost = post;
      _creatingNew = false;
      _newTemplate = null;
      _editorDirty = false;
      _editorKey = GlobalKey<PostEditorState>();
    });
  }

  Future<void> _newPostInline({PostTemplate? template}) async {
    if (!await _leaveCurrentEditor()) return;
    setState(() {
      _section = _Section.posts;
      _openPost = null;
      _creatingNew = true;
      _newTemplate = template;
      _editorDirty = false;
      _editorKey = GlobalKey<PostEditorState>();
    });
  }

  /// 템플릿 선택. 취소하면 null 이 아니라 [_Cancelled] 를 던진다.
  Future<PostTemplate?> _pickTemplate(JekyllTheme theme) async {
    if (theme.templates.isEmpty) return null;
    final choice = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('새 글'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'blank'),
            child: const ListTile(leading: Icon(Icons.note_add_outlined), title: Text('빈 글'), dense: true),
          ),
          const Divider(),
          for (final t in theme.templates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: Text(t.name),
                subtitle: const Text('템플릿에서 시작', style: TextStyle(fontSize: 11)),
                dense: true,
              ),
            ),
        ],
      ),
    );
    if (choice == null) throw _Cancelled();
    return choice is PostTemplate ? choice : null;
  }

  Future<void> _startNewPost(JekyllTheme theme, {required bool compact}) async {
    PostTemplate? template;
    try {
      template = await _pickTemplate(theme);
    } on _Cancelled {
      return;
    }
    if (compact) {
      await _pushMobileEditor(null, template: template);
    } else {
      await _newPostInline(template: template);
    }
  }

  Future<void> _pushMobileEditor(PostInfo? post, {PostTemplate? template}) async {
    final repo = ref.read(blogRepositoryProvider);
    if (repo == null) return;
    final theme = ref.read(jekyllThemeProvider).value ?? JekyllTheme.fallback('');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _MobileEditorPage(post: post, repository: repo, theme: theme, template: template),
      ),
    );
    _loadPosts();
  }

  void _onSaved(String name) {
    setState(() {
      _openPost = PostInfo(name: name, title: '', category: '', tags: const [], date: null, modified: DateTime.now());
      _creatingNew = false;
    });
    _loadPosts();
  }

  void _onDeleted(String name) {
    setState(() {
      _openPost = null;
      _creatingNew = false;
      _editorKey = GlobalKey<PostEditorState>();
    });
    _loadPosts();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(blogRepositoryProvider, (prev, next) {
      if (prev?.location != next?.location || prev?.label != next?.label) {
        setState(() {
          _openPost = null;
          _creatingNew = false;
        });
        _loadPosts();
      }
    });

    final themeAsync = ref.watch(jekyllThemeProvider);
    final isDesktop = ref.watch(isDesktopProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;
        return compact ? _buildCompact(themeAsync) : _buildWide(themeAsync, isDesktop);
      },
    );
  }

  // ----- wide (desktop) ------------------------------------------------------

  Widget _buildWide(AsyncValue<JekyllTheme> themeAsync, bool isDesktop) {
    final scheme = Theme.of(context).colorScheme;
    final destinations = [
      const NavigationRailDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: Text('포스트')),
      if (isDesktop)
        const NavigationRailDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: Text('Obsidian')),
      const NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('설정')),
    ];
    final sections = [_Section.posts, if (isDesktop) _Section.import, _Section.settings];
    final selectedIndex = sections.indexOf(_section).clamp(0, sections.length - 1);

    return Scaffold(
      body: Column(
        children: [
          if (_availableUpdate != null && !_updateDismissed) _buildUpdateBanner(),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (i) => setState(() => _section = sections[i]),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: scheme.surfaceContainerLow,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.auto_stories, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton.small(
                          heroTag: 'new-post',
                          tooltip: '새 글',
                          onPressed: () => _startNewPost(themeAsync.value ?? JekyllTheme.fallback(''), compact: false),
                          child: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  destinations: destinations,
                ),
                VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
                Expanded(child: _buildWideSection(themeAsync)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideSection(AsyncValue<JekyllTheme> themeAsync) {
    switch (_section) {
      case _Section.posts:
        return Row(
          children: [
            SizedBox(width: 320, child: _buildPostList(themeAsync, compact: false)),
            VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
            Expanded(child: _buildEditorArea(themeAsync)),
          ],
        );
      case _Section.import:
        return ObsidianImportScreen(
          onConverted: (file) {
            final name = file.path.split(RegExp(r'[\\/]')).last;
            _openPostInline(PostInfo(name: name, title: '', category: '', tags: const [], date: null, modified: DateTime.now()));
          },
        );
      case _Section.settings:
        return const SettingsScreen();
    }
  }

  Widget _buildEditorArea(AsyncValue<JekyllTheme> themeAsync) {
    final scheme = Theme.of(context).colorScheme;
    final repo = ref.watch(blogRepositoryProvider);

    if (repo == null) return _buildNotConfigured();

    if (_openPost == null && !_creatingNew) {
      return Container(
        color: scheme.surfaceContainerLowest,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_note, size: 72, color: scheme.outline),
              const SizedBox(height: 12),
              Text('왼쪽에서 글을 고르거나 새 글을 시작하세요', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _startNewPost(themeAsync.value ?? JekyllTheme.fallback(''), compact: false),
                icon: const Icon(Icons.add),
                label: const Text('새 글 쓰기'),
              ),
            ],
          ),
        ),
      );
    }

    return themeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildEditor(repo, JekyllTheme.fallback(repo.isLocal ? repo.location : '')),
      data: (theme) => _buildEditor(repo, theme),
    );
  }

  Widget _buildEditor(BlogRepository repo, JekyllTheme theme) {
    return PostEditor(
      key: _editorKey,
      post: _openPost,
      repository: repo,
      theme: theme,
      initialTemplate: _newTemplate,
      onSaved: _onSaved,
      onDeleted: _onDeleted,
      onDirtyChanged: (dirty) {
        if (_editorDirty != dirty && mounted) setState(() => _editorDirty = dirty);
      },
    );
  }

  // ----- compact (mobile) ----------------------------------------------------

  Widget _buildCompact(AsyncValue<JekyllTheme> themeAsync) {
    final sections = [_Section.posts, _Section.settings];
    final index = _section == _Section.settings ? 1 : 0;
    final configured = ref.watch(blogRepositoryProvider) != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_availableUpdate != null && !_updateDismissed) _buildUpdateBanner(),
            Expanded(
              child: index == 0
                  ? (configured ? _buildPostList(themeAsync, compact: true) : _buildNotConfigured())
                  : const SettingsScreen(),
            ),
          ],
        ),
      ),
      floatingActionButton: index == 0 && configured
          ? FloatingActionButton.extended(
              heroTag: 'new-post-mobile',
              onPressed: () => _startNewPost(themeAsync.value ?? JekyllTheme.fallback(''), compact: true),
              icon: const Icon(Icons.add),
              label: const Text('새 글'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _section = sections[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: '포스트'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }

  // ----- shared pieces -------------------------------------------------------

  Widget _buildUpdateBanner() {
    final release = _availableUpdate!;
    return MaterialBanner(
      leading: const Icon(Icons.system_update_alt),
      content: Text('새 버전 ${release.tagName} 이 있습니다.'),
      actions: [
        TextButton(onPressed: () => setState(() => _updateDismissed = true), child: const Text('나중에')),
        FilledButton(onPressed: _applyUpdate, child: Text(!kIsWeb && Platform.isWindows ? '업데이트' : '다운로드')),
      ],
    );
  }

  Widget _buildNotConfigured() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              '블로그 저장소가 연결되지 않았습니다.\n설정에서 로컬 Jekyll 폴더(데스크톱) 또는 GitHub 저장소 정보를 입력하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => setState(() => _section = _Section.settings),
              icon: const Icon(Icons.settings),
              label: const Text('설정 열기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostList(AsyncValue<JekyllTheme> themeAsync, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visiblePosts;
    final repo = ref.watch(blogRepositoryProvider);

    return Container(
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                const Expanded(child: Text('포스트', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                  tooltip: '목록 새로고침 + 블로그 다시 스캔',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () async {
                    await _loadPosts(refresh: true);
                    ref.invalidate(jekyllThemeProvider);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '제목, 파일명, 카테고리, 태그 검색',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: _searchController.clear)
                    : null,
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _PostFilter.values) ...[
                    ChoiceChip(
                      label: Text(_filterLabel(f), style: const TextStyle(fontSize: 12)),
                      selected: _filter == f,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Row(
              children: [
                Icon(repo?.isLocal == true ? Icons.folder_outlined : Icons.cloud_outlined, size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    repo == null ? '미연결' : '${repo.label} · ${repo.location}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${visible.length}개', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: themeAsync.when(
                data: (t) => Text('${t.skin.name} 스킨 · 블록 ${t.blockStyles.length}개', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                loading: () => Text('블로그 스캔 중…', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                error: (e, _) => Text('스캔 실패', style: TextStyle(fontSize: 11, color: scheme.error)),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingPosts
                ? const Center(child: CircularProgressIndicator())
                : _postsError != null
                    ? _buildListMessage(
                        Icons.error_outline,
                        _postsError!,
                        action: TextButton(onPressed: () => setState(() => _section = _Section.settings), child: const Text('설정 열기')),
                      )
                    : visible.isEmpty
                        ? _buildListMessage(Icons.inbox_outlined, _posts.isEmpty ? '_posts 폴더에 글이 없습니다' : '검색 결과가 없습니다')
                        : RefreshIndicator(
                            onRefresh: () => _loadPosts(refresh: true),
                            child: ListView.builder(
                              padding: compact ? const EdgeInsets.only(bottom: 88) : EdgeInsets.zero,
                              itemCount: visible.length,
                              itemBuilder: (context, index) => _buildPostTile(visible[index], compact: compact),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(_PostFilter f) {
    switch (f) {
      case _PostFilter.all:
        return '전체';
      case _PostFilter.published:
        return '게시됨';
      case _PostFilter.draft:
        return '초안';
      case _PostFilter.template:
        return '템플릿';
    }
  }

  Widget _buildListMessage(IconData icon, String message, {Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: scheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      ),
    );
  }

  Widget _buildPostTile(PostInfo entry, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final isOpen = !compact && !_creatingNew && _openPost?.name == entry.name;

    Widget badge;
    if (entry.isTemplate) {
      badge = _Badge(text: '템플릿', color: scheme.tertiary);
    } else if (entry.isDraft) {
      badge = _Badge(text: '초안', color: Colors.orange[800]!);
    } else if (entry.isPublished) {
      badge = _Badge(text: '게시', color: scheme.primary);
    } else {
      badge = _Badge(text: '날짜 없음', color: scheme.outline);
    }

    return InkWell(
      onTap: () => compact ? _pushMobileEditor(entry) : _openPostInline(entry),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: isOpen ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
          border: Border(
            left: BorderSide(color: isOpen ? scheme.primary : Colors.transparent, width: 3),
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title.isEmpty ? entry.name : entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: isOpen ? FontWeight.w700 : FontWeight.w600, height: 1.3),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                badge,
                const SizedBox(width: 6),
                if (entry.category.isNotEmpty) ...[
                  Icon(Icons.folder_outlined, size: 12, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(entry.category, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(entry.dateLabel, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                ),
                if (isOpen && _editorDirty) Icon(Icons.circle, size: 8, color: Colors.orange[800]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cancelled implements Exception {}

/// 모바일: 전체 화면 에디터 페이지
class _MobileEditorPage extends StatefulWidget {
  final PostInfo? post;
  final BlogRepository repository;
  final JekyllTheme theme;
  final PostTemplate? template;

  const _MobileEditorPage({required this.post, required this.repository, required this.theme, this.template});

  @override
  State<_MobileEditorPage> createState() => _MobileEditorPageState();
}

class _MobileEditorPageState extends State<_MobileEditorPage> {
  final _key = GlobalKey<PostEditorState>();
  bool _dirty = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _key.currentState?.confirmLeave() ?? true;
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.post == null ? '새 글' : '글 편집'),
          titleSpacing: 0,
        ),
        body: SafeArea(
          child: PostEditor(
            key: _key,
            post: widget.post,
            repository: widget.repository,
            theme: widget.theme,
            initialTemplate: widget.template,
            onSaved: (_) {},
            onDeleted: (_) => Navigator.of(context).pop(),
            onDirtyChanged: (d) {
              if (mounted && _dirty != d) setState(() => _dirty = d);
            },
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
