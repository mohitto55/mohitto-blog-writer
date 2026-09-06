import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../services/converter_service.dart';
import '../../services/obsidian_service.dart';
import '../widgets/conversion_options_dialog.dart';
import '../widgets/git_publish_flow.dart';
import '../widgets/markdown_preview_panel.dart';
import '../widgets/obsidian_file_browser.dart';
import 'settings_screen.dart';

/// Obsidian 노트를 골라 Jekyll 포스트로 변환하는 화면.
///
/// 변환이 끝나면 [onConverted]로 생성된 파일을 넘겨 에디터에서 바로 열 수 있게 한다.
class ObsidianImportScreen extends ConsumerStatefulWidget {
  final void Function(File converted)? onConverted;

  const ObsidianImportScreen({super.key, this.onConverted});

  @override
  ConsumerState<ObsidianImportScreen> createState() => _ObsidianImportScreenState();
}

class _ObsidianImportScreenState extends ConsumerState<ObsidianImportScreen> {
  List<File> selectedFiles = [];
  File? currentPreviewFile;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadSelectedFiles();
  }

  Future<void> _loadSelectedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPaths = prefs.getStringList(AppConstants.settingsSelectedFiles);

    if (savedPaths != null && savedPaths.isNotEmpty) {
      final files = savedPaths.map((p) => File(p)).where((file) => file.existsSync()).toList();
      if (files.isNotEmpty && mounted) {
        setState(() {
          selectedFiles = files;
          currentPreviewFile = files.first;
        });
      }
    }
  }

  Future<void> _saveSelectedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(AppConstants.settingsSelectedFiles, selectedFiles.map((f) => f.path).toList());
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final vaultPath = settings[AppConstants.settingsObsidianVaultPath] ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              const Icon(Icons.download_outlined, size: 22),
              const SizedBox(width: 8),
              const Text('Obsidian 가져오기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Text(
                vaultPath.isEmpty ? 'Vault 경로 미설정' : vaultPath,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _selectFromVault,
                icon: const Icon(Icons.book_outlined, size: 18),
                label: const Text('Vault에서 선택'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _selectFiles,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('파일 직접 선택'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: selectedFiles.isEmpty || isProcessing ? null : _convertToJekyll,
                icon: const Icon(Icons.transform, size: 18),
                label: const Text('Jekyll로 변환'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: isProcessing ? null : _publishToGitHub,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('GitHub 업로드'),
              ),
            ],
          ),
        ),
        if (isProcessing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: selectedFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_outlined, size: 64, color: scheme.outline),
                      const SizedBox(height: 16),
                      Text('가져올 Obsidian 노트를 선택하세요', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 340,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            color: scheme.surfaceContainerLow,
                            child: Row(
                              children: [
                                const Text('선택된 노트', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const Spacer(),
                                Text('${selectedFiles.length}개', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: selectedFiles.length,
                              itemBuilder: (context, index) {
                                final file = selectedFiles[index];
                                final isSelected = currentPreviewFile?.path == file.path;
                                return ListTile(
                                  dense: true,
                                  selected: isSelected,
                                  selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
                                  leading: Icon(Icons.description_outlined, size: 20, color: isSelected ? scheme.primary : null),
                                  title: Text(path.basename(file.path), style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                                  subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        if (currentPreviewFile?.path == file.path) currentPreviewFile = null;
                                        selectedFiles.removeAt(index);
                                      });
                                      _saveSelectedFiles();
                                    },
                                  ),
                                  onTap: () => setState(() => currentPreviewFile = file),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, color: scheme.outlineVariant),
                    Expanded(
                      child: MarkdownPreviewPanel(selectedFile: currentPreviewFile, vaultPath: vaultPath),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _selectFromVault() async {
    final settings = ref.read(settingsProvider);
    final vaultPath = settings[AppConstants.settingsObsidianVaultPath];

    if (vaultPath == null || vaultPath.isEmpty) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vault 경로 미설정'),
          content: const Text('Obsidian Vault 경로를 먼저 설정해주세요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('설정하기')),
          ],
        ),
      );
      if (result == true && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
      }
      return;
    }

    final result = await showDialog<List<File>>(
      context: context,
      builder: (context) => ObsidianFileBrowser(vaultPath: vaultPath),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        selectedFiles = result;
        currentPreviewFile = result.first;
      });
      _saveSelectedFiles();
    }
  }

  Future<void> _selectFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md'],
      allowMultiple: true,
    );
    if (result == null) return;

    final files = result.paths.whereType<String>().map((p) => File(p)).toList();
    setState(() {
      selectedFiles = files;
      if (files.isNotEmpty) currentPreviewFile = files.first;
    });
    _saveSelectedFiles();
  }

  Future<void> _convertToJekyll() async {
    final targetFile = currentPreviewFile ?? (selectedFiles.isNotEmpty ? selectedFiles.first : null);
    if (targetFile == null) {
      _snack('변환할 파일을 선택해주세요', color: Colors.orange);
      return;
    }

    final fileName = path.basename(targetFile.path);
    final options = await showDialog<ConversionOptions>(
      context: context,
      builder: (context) => ConversionOptionsDialog(sourceFileName: fileName),
    );
    if (options == null) return;

    setState(() => isProcessing = true);
    try {
      final settings = ref.read(settingsProvider);
      final vaultPath = settings[AppConstants.settingsObsidianVaultPath] ?? '';
      final jekyllPath = settings[AppConstants.settingsJekyllBlogPath];
      if (jekyllPath == null || jekyllPath.isEmpty) {
        throw Exception(AppConstants.errorNoBlogPath);
      }

      final obsidianService = ObsidianService(vaultPath: vaultPath);
      final converterService = ConverterService();
      final blogPost = await obsidianService.readBlogPost(targetFile);
      final convertedPost = converterService.convertPostWithTemplate(
        blogPost,
        customTitle: options.fullTitle,
        category: options.category,
        tags: options.tags,
        referenceUrl: options.referenceUrl,
        publishDate: options.date,
      );

      final postsDir = Directory(path.join(jekyllPath, AppConstants.defaultPostsFolder));
      if (!await postsDir.exists()) await postsDir.create(recursive: true);

      final outputFile = File(path.join(postsDir.path, options.fileName));
      await outputFile.writeAsString(convertedPost.toGitHubMarkdown());

      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('변환 완료'),
          content: Text('${options.fileName}\n\nJekyll _posts 폴더에 저장했습니다. 에디터에서 열까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('닫기')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('에디터에서 열기')),
          ],
        ),
      );
      if (open == true) widget.onConverted?.call(outputFile);
    } catch (e) {
      _snack('오류 발생: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _publishToGitHub() async {
    setState(() => isProcessing = true);
    try {
      await runGitPublishFlow(context, ref.read(jekyllBlogPathProvider));
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }
}
