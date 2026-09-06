import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../services/github_blog_repository.dart';
import '../../services/update_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _githubTokenController = TextEditingController();
  final _githubOwnerController = TextEditingController();
  final _githubRepoController = TextEditingController();
  final _githubBranchController = TextEditingController();
  final _obsidianPathController = TextEditingController();
  final _jekyllPathController = TextEditingController();
  String _storageMode = 'auto';
  bool _showToken = false;
  bool _testing = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    ref.read(updateServiceProvider).currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _githubTokenController.dispose();
    _githubOwnerController.dispose();
    _githubRepoController.dispose();
    _githubBranchController.dispose();
    _obsidianPathController.dispose();
    _jekyllPathController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    final settings = ref.read(settingsProvider);
    _githubTokenController.text = settings[AppConstants.settingsGitHubToken] ?? '';
    _githubOwnerController.text = settings[AppConstants.settingsGitHubOwner] ?? '';
    _githubRepoController.text = settings[AppConstants.settingsGitHubRepo] ?? '';
    _githubBranchController.text = settings[AppConstants.settingsGitHubBranch] ?? '';
    _obsidianPathController.text = settings[AppConstants.settingsObsidianVaultPath] ?? '';
    _jekyllPathController.text = settings[AppConstants.settingsJekyllBlogPath] ?? '';
    _storageMode = settings[AppConstants.settingsStorageMode] ?? 'auto';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ref.watch(isDesktopProvider);
    final repo = ref.watch(blogRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          IconButton(icon: const Icon(Icons.save), tooltip: '저장', onPressed: _saveSettings),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 현재 연결 상태
          Card(
            color: scheme.surfaceContainerLow,
            child: ListTile(
              leading: Icon(repo == null ? Icons.link_off : (repo.isLocal ? Icons.folder : Icons.cloud), color: repo == null ? scheme.error : scheme.primary),
              title: Text(repo == null ? '저장소 미연결' : '${repo.label} 사용 중'),
              subtitle: Text(repo == null ? '아래에서 로컬 폴더 또는 GitHub 정보를 입력하세요' : repo.location),
            ),
          ),
          const SizedBox(height: 20),

          _sectionTitle('저장 방식'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'auto', label: Text('자동'), icon: Icon(Icons.auto_mode)),
              if (isDesktop) const ButtonSegment(value: 'local', label: Text('로컬 폴더'), icon: Icon(Icons.folder_outlined)),
              const ButtonSegment(value: 'github', label: Text('GitHub'), icon: Icon(Icons.cloud_outlined)),
            ],
            selected: {_storageMode == 'local' && !isDesktop ? 'auto' : _storageMode},
            onSelectionChanged: (s) => setState(() => _storageMode = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            isDesktop
                ? '자동: 로컬 Jekyll 폴더가 있으면 폴더에 저장하고 git 으로 올립니다. 없으면 GitHub API 로 바로 커밋합니다.'
                : '모바일/웹에서는 GitHub API 로 바로 커밋합니다. 저장 = 커밋 이므로 GitHub Pages 가 자동으로 다시 빌드합니다.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),

          const SizedBox(height: 28),
          _sectionTitle('GitHub'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _githubOwnerController,
                  decoration: const InputDecoration(labelText: '사용자명 (owner)', hintText: 'mohitto55', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _githubRepoController,
                  decoration: const InputDecoration(labelText: '저장소 (repo)', hintText: 'mohitto55.github.io', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _githubBranchController,
            decoration: const InputDecoration(labelText: '브랜치 (비우면 기본 브랜치)', hintText: 'main', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _githubTokenController,
            obscureText: !_showToken,
            decoration: InputDecoration(
              labelText: 'Personal Access Token',
              hintText: 'github_pat_… 또는 ghp_…',
              border: const OutlineInputBorder(),
              helperText: 'Fine-grained token: 해당 저장소에 Contents: Read and write 권한만 주면 됩니다.',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showToken = !_showToken),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _testGitHub,
                icon: _testing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('연결 테스트'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://github.com/settings/personal-access-tokens/new'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('토큰 만들기'),
              ),
            ],
          ),

          if (isDesktop) ...[
            const SizedBox(height: 28),
            _sectionTitle('로컬 (데스크톱)'),
            const SizedBox(height: 12),
            _pathField(
              controller: _jekyllPathController,
              label: 'Jekyll 블로그 폴더 (git clone 한 폴더)',
              hint: r'C:\Users\admin\git\blog',
              onPick: () => _pickDirectory(_jekyllPathController),
            ),
            const SizedBox(height: 12),
            _pathField(
              controller: _obsidianPathController,
              label: 'Obsidian Vault 폴더 (가져오기용, 선택)',
              hint: r'C:\Users\...\ObsidianVault',
              onPick: () => _pickDirectory(_obsidianPathController),
            ),
          ],

          const SizedBox(height: 28),
          _sectionTitle('앱'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text('${AppConstants.appName} ${_version ?? ''}'),
            subtitle: Text(kIsWeb ? '웹 버전은 새로고침하면 항상 최신입니다.' : '업데이트는 GitHub Releases(${AppConstants.appRepo})에서 확인합니다.'),
            trailing: kIsWeb
                ? null
                : OutlinedButton(onPressed: _checkUpdate, child: const Text('업데이트 확인')),
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('설정 저장'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700));

  Widget _pathField({required TextEditingController controller, required String label, required String hint, required VoidCallback onPick}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(icon: const Icon(Icons.folder_open), onPressed: onPick, tooltip: '폴더 선택'),
      ),
    );
  }

  Future<void> _pickDirectory(TextEditingController controller) async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir != null) setState(() => controller.text = dir);
  }

  Future<void> _testGitHub() async {
    setState(() => _testing = true);
    try {
      final repo = GitHubBlogRepository(
        owner: _githubOwnerController.text.trim(),
        repo: _githubRepoController.text.trim(),
        token: _githubTokenController.text.trim(),
        branchOverride: _githubBranchController.text.trim().isEmpty ? null : _githubBranchController.text.trim(),
      );
      final posts = await repo.listPosts();
      _snack('연결 성공: ${repo.location} · 포스트 ${posts.length}개');
    } catch (e) {
      _snack('연결 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _checkUpdate() async {
    final service = ref.read(updateServiceProvider);
    final latest = await service.fetchLatest();
    if (!mounted) return;
    if (latest == null) {
      _snack('릴리스 정보를 가져올 수 없습니다. (${AppConstants.appRepo})', error: true);
      return;
    }
    final current = await service.currentVersion();
    if (UpdateService.compareVersions(latest.version, current) > 0) {
      _snack('새 버전 ${latest.tagName} 이 있습니다. 앱을 다시 시작하면 상단에 업데이트 안내가 표시됩니다.');
      await launchUrl(Uri.parse(latest.htmlUrl), mode: LaunchMode.externalApplication);
    } else {
      _snack('최신 버전입니다 ($current)');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.updateMultipleSettings({
        AppConstants.settingsGitHubToken: _githubTokenController.text.trim(),
        AppConstants.settingsGitHubOwner: _githubOwnerController.text.trim(),
        AppConstants.settingsGitHubRepo: _githubRepoController.text.trim(),
        AppConstants.settingsGitHubBranch: _githubBranchController.text.trim(),
        AppConstants.settingsStorageMode: _storageMode,
        AppConstants.settingsObsidianVaultPath: _obsidianPathController.text.trim(),
        AppConstants.settingsJekyllBlogPath: _jekyllPathController.text.trim(),
      });
      _snack('설정을 저장했습니다');
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      _snack('설정 저장 실패: $e', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Colors.red[700] : null, duration: Duration(seconds: error ? 5 : 2)));
  }
}
