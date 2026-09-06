import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class ObsidianFileBrowser extends StatefulWidget {
  final String vaultPath;

  const ObsidianFileBrowser({
    super.key,
    required this.vaultPath,
  });

  @override
  State<ObsidianFileBrowser> createState() => _ObsidianFileBrowserState();
}

class _ObsidianFileBrowserState extends State<ObsidianFileBrowser> {
  List<File> allMarkdownFiles = [];
  Set<String> selectedFiles = {};
  bool isLoading = true;
  String? errorMessage;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMarkdownFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMarkdownFiles() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final directory = Directory(widget.vaultPath);

      if (!await directory.exists()) {
        throw Exception('Vault 경로를 찾을 수 없습니다: ${widget.vaultPath}');
      }

      final files = <File>[];
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          files.add(entity);
        }
      }

      // 파일명으로 정렬
      files.sort((a, b) => a.path.compareTo(b.path));

      setState(() {
        allMarkdownFiles = files;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  String _getRelativePath(String filePath) {
    return path.relative(filePath, from: widget.vaultPath);
  }

  List<File> _getFilteredFiles() {
    if (searchQuery.isEmpty) {
      return allMarkdownFiles;
    }

    final query = searchQuery.toLowerCase();
    return allMarkdownFiles.where((file) {
      final fileName = path.basename(file.path).toLowerCase();
      final relativePath = _getRelativePath(file.path).toLowerCase();
      return fileName.contains(query) || relativePath.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.folder_open, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Obsidian Vault 파일 선택',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.vaultPath,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),

            // 검색 입력
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: '검색',
                  hintText: '파일명 또는 경로로 검색...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 8),

            // 액션 버튼
            Row(
              children: [
                TextButton.icon(
                  onPressed: selectedFiles.isEmpty
                      ? null
                      : () {
                          setState(() {
                            selectedFiles.clear();
                          });
                        },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('전체 해제'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      final filteredFiles = _getFilteredFiles();
                      selectedFiles.addAll(filteredFiles.map((f) => f.path));
                    });
                  },
                  icon: const Icon(Icons.select_all),
                  label: Text(searchQuery.isEmpty ? '전체 선택' : '검색 결과 선택'),
                ),
                const Spacer(),
                Text(
                  '${selectedFiles.length}/${allMarkdownFiles.length}개 선택' +
                      (searchQuery.isNotEmpty
                          ? ' (${_getFilteredFiles().length}개 표시)'
                          : ''),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 파일 목록
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '오류 발생',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(errorMessage!),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadMarkdownFiles,
                                child: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        )
                      : allMarkdownFiles.isEmpty
                          ? const Center(
                              child: Text('마크다운 파일이 없습니다'),
                            )
                          : _buildFileList(),
            ),

            const Divider(),

            // 하단 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: selectedFiles.isEmpty
                      ? null
                      : () {
                          final selected = allMarkdownFiles
                              .where((f) => selectedFiles.contains(f.path))
                              .toList();
                          Navigator.pop(context, selected);
                        },
                  child: Text('선택 (${selectedFiles.length})'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    final filteredFiles = _getFilteredFiles();

    if (filteredFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              searchQuery.isEmpty
                  ? '마크다운 파일이 없습니다'
                  : '검색 결과가 없습니다',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredFiles.length,
      itemBuilder: (context, index) {
        final file = filteredFiles[index];
        final relativePath = _getRelativePath(file.path);
        final isSelected = selectedFiles.contains(file.path);

        return CheckboxListTile(
          value: isSelected,
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                selectedFiles.add(file.path);
              } else {
                selectedFiles.remove(file.path);
              }
            });
          },
          title: Text(path.basename(file.path)),
          subtitle: Text(
            relativePath,
            style: const TextStyle(fontSize: 12),
          ),
          secondary: const Icon(Icons.description),
        );
      },
    );
  }
}
