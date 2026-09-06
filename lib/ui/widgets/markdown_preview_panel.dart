import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/blog_post.dart';
import '../../services/obsidian_service.dart';
import '../../services/converter_service.dart';

class MarkdownPreviewPanel extends StatefulWidget {
  final File? selectedFile;
  final String vaultPath;

  const MarkdownPreviewPanel({
    super.key,
    required this.selectedFile,
    required this.vaultPath,
  });

  @override
  State<MarkdownPreviewPanel> createState() => _MarkdownPreviewPanelState();
}

class _MarkdownPreviewPanelState extends State<MarkdownPreviewPanel> {
  String? originalContent;
  String? convertedContent;
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAndConvert();
  }

  @override
  void didUpdateWidget(MarkdownPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFile?.path != widget.selectedFile?.path) {
      _loadAndConvert();
    }
  }

  Future<void> _loadAndConvert() async {
    if (widget.selectedFile == null) {
      setState(() {
        originalContent = null;
        convertedContent = null;
        errorMessage = null;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Read original content
      final obsidianService = ObsidianService(vaultPath: widget.vaultPath);
      final blogPost = await obsidianService.readBlogPost(widget.selectedFile!);

      // Convert to Jekyll format
      final converterService = ConverterService();
      final convertedPost = converterService.convertPost(blogPost);

      setState(() {
        originalContent = blogPost.content;
        convertedContent = convertedPost.toGitHubMarkdown();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedFile == null) {
      return _buildEmptyState();
    }

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return _buildErrorState();
    }

    return _buildComparisonView();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '파일을 선택하면\n변환 미리보기를 볼 수 있습니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          const Text(
            '오류 발생',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadAndConvert,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonView() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.compare_arrows, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '변환 미리보기',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.selectedFile!.path.split('\\').last,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAndConvert,
                tooltip: '새로고침',
              ),
            ],
          ),
        ),

        // Split view
        Expanded(
          child: Row(
            children: [
              // Original content
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.blue[50],
                      child: const Row(
                        children: [
                          Icon(Icons.article, size: 20, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            'Obsidian 원본',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            originalContent ?? '',
                            style: const TextStyle(
                              fontFamily: 'Courier New',
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                width: 1,
                color: Colors.grey[300],
              ),

              // Converted content
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.green[50],
                      child: const Row(
                        children: [
                          Icon(Icons.auto_fix_high, size: 20, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'Jekyll 변환 결과',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            convertedContent ?? '',
                            style: const TextStyle(
                              fontFamily: 'Courier New',
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Footer with stats
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(
              top: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('원본', originalContent?.length ?? 0),
              _buildStat('변환', convertedContent?.length ?? 0),
              _buildStat(
                '차이',
                (convertedContent?.length ?? 0) - (originalContent?.length ?? 0),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, int value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$value자',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
