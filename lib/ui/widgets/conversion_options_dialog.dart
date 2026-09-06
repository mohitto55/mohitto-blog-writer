import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;
import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';

class ConversionOptions {
  final DateTime date;
  final String subject;
  final String title;
  final String? category;
  final List<String>? tags;
  final String? referenceUrl;

  ConversionOptions({
    required this.date,
    required this.subject,
    required this.title,
    this.category,
    this.tags,
    this.referenceUrl,
  });

  String get fullTitle => '[$subject] $title';

  String get fileName {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$dateStr-$fullTitle.md';
  }
}

class ConversionOptionsDialog extends ConsumerStatefulWidget {
  final String? defaultTitle;
  final String? defaultCategory;
  final List<String>? defaultTags;
  final String? sourceFileName;

  const ConversionOptionsDialog({
    super.key,
    this.defaultTitle,
    this.defaultCategory,
    this.defaultTags,
    this.sourceFileName,
  });

  @override
  ConsumerState<ConversionOptionsDialog> createState() => _ConversionOptionsDialogState();
}

class _ConversionOptionsDialogState extends ConsumerState<ConversionOptionsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _titleController = TextEditingController();
  final _tagsController = TextEditingController();
  final _referenceUrlController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  List<String> _availableCategories = [];
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.defaultTitle ?? '';
    _selectedCategory = widget.defaultCategory;
    if (widget.defaultTags != null && widget.defaultTags!.isNotEmpty) {
      _tagsController.text = widget.defaultTags!.join(', ');
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final settings = ref.read(settingsProvider);
      final jekyllPath = settings[AppConstants.settingsJekyllBlogPath];

      print('DEBUG: Jekyll path: $jekyllPath');

      if (jekyllPath == null || jekyllPath.isEmpty) {
        print('DEBUG: Jekyll path is null or empty');
        return;
      }

      final categoriesDir = Directory(path.join(jekyllPath, '_pages', 'categories'));
      print('DEBUG: Categories directory: ${categoriesDir.path}');

      if (!await categoriesDir.exists()) {
        print('DEBUG: Categories directory does not exist');
        return;
      }

      final categories = <String>[];
      var fileCount = 0;
      await for (final entity in categoriesDir.list()) {
        print('DEBUG: Found entity: ${entity.path}');
        if (entity is File && entity.path.endsWith('.md')) {
          fileCount++;
          try {
            final content = await entity.readAsString();
            print('DEBUG: Read file content (${content.length} chars)');
            final permalink = _extractPermalink(content);
            print('DEBUG: Extracted permalink: $permalink');
            if (permalink != null) {
              categories.add(permalink);
            }
          } catch (e) {
            print('DEBUG: Error reading file: $e');
          }
        }
      }

      print('DEBUG: Total files found: $fileCount');
      print('DEBUG: Total categories extracted: ${categories.length}');
      print('DEBUG: Categories: $categories');

      if (mounted) {
        setState(() {
          _availableCategories = categories..sort();
        });
      }
    } catch (e) {
      print('DEBUG: Error in _loadCategories: $e');
    }
  }

  String? _extractPermalink(String content) {
    // Windows 줄바꿈 처리 (\r\n)
    final lines = content.split(RegExp(r'\r?\n'));

    // Check if content starts with frontmatter (---)
    if (lines.isEmpty || lines[0].trim() != '---') {
      return null;
    }

    // 두 번째 --- 찾기 (trim 사용)
    int endIndex = -1;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        endIndex = i;
        break;
      }
    }

    if (endIndex <= 0) {
      return null;
    }

    final frontmatterText = lines.sublist(1, endIndex).join('\n');

    try {
      final parsed = loadYaml(frontmatterText);
      if (parsed is Map && parsed.containsKey('permalink')) {
        String permalink = parsed['permalink'].toString();
        // Remove leading slash if present
        if (permalink.startsWith('/')) {
          permalink = permalink.substring(1);
        }
        return permalink;
      }
    } catch (e) {
      // Failed to parse YAML
    }

    return null;
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _titleController.dispose();
    _tagsController.dispose();
    _referenceUrlController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Widget _buildCategoryField() {
    if (_availableCategories.isEmpty) {
      return TextFormField(
        enabled: false,
        decoration: const InputDecoration(
          labelText: '카테고리 (선택)',
          hintText: '카테고리 파일이 없습니다',
          border: OutlineInputBorder(),
        ),
      );
    }

    // 카테고리가 10개 미만이면 기존 드롭다운 사용 (높이만 증가)
    if (_availableCategories.length < 10) {
      return DropdownButtonFormField<String>(
        value: _selectedCategory,
        decoration: const InputDecoration(
          labelText: '카테고리 (선택)',
          hintText: '카테고리 선택',
          border: OutlineInputBorder(),
        ),
        menuMaxHeight: 500, // 300 → 500으로 증가
        items: _availableCategories.map((category) {
          return DropdownMenuItem<String>(
            value: category,
            child: Text(category),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedCategory = value;
          });
        },
      );
    }

    // 카테고리가 10개 이상이면 검색 가능한 Autocomplete 사용
    return Autocomplete<String>(
      initialValue: _selectedCategory != null
          ? TextEditingValue(text: _selectedCategory!)
          : TextEditingValue.empty,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _availableCategories;
        }
        return _availableCategories.where((String option) {
          return option.toLowerCase().contains(
            textEditingValue.text.toLowerCase(),
          );
        });
      },
      onSelected: (String selection) {
        setState(() {
          _selectedCategory = selection;
        });
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController textEditingController,
        FocusNode focusNode,
        VoidCallback onFieldSubmitted,
      ) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: '카테고리 (선택)',
            hintText: '카테고리 검색 또는 선택',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<String> onSelected,
        Iterable<String> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400, maxWidth: 300),
              child: ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return InkWell(
                    onTap: () {
                      onSelected(option);
                    },
                    child: ListTile(
                      title: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  List<String> _parseTags() {
    final tagsText = _tagsController.text.trim();
    if (tagsText.isEmpty) return [];

    return tagsText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // 헤더
              Row(
                children: [
                  const Icon(Icons.settings, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Jekyll 변환 옵션',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.sourceFileName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '파일: ${widget.sourceFileName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // 날짜 선택
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '발행 날짜',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('날짜 선택'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 주제 입력
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: '주제 *',
                  hintText: 'Math, Python, Flutter 등',
                  border: OutlineInputBorder(),
                  helperText: '파일명과 제목에 [주제] 형식으로 추가됩니다',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '주제를 입력해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 제목 입력
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '제목 *',
                  hintText: '세점을 지나는 원의 중심 구하기',
                  border: OutlineInputBorder(),
                  helperText: '파일명: YYYY-MM-DD-[주제] 제목.md',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '제목을 입력해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 미리보기
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '미리보기',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subjectController.text.isEmpty || _titleController.text.isEmpty
                          ? '주제와 제목을 입력하면 미리보기가 표시됩니다'
                          : '파일명: ${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}-[${_subjectController.text}] ${_titleController.text}.md',
                      style: TextStyle(
                        fontSize: 13,
                        color: _subjectController.text.isEmpty || _titleController.text.isEmpty
                            ? Colors.grey
                            : Colors.black87,
                        fontFamily: 'Courier New',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subjectController.text.isEmpty || _titleController.text.isEmpty
                          ? ''
                          : 'title: "[${_subjectController.text}] ${_titleController.text}"',
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'Courier New',
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const Divider(),
              const SizedBox(height: 16),

              // 카테고리 (선택)
              _buildCategoryField(),
              const SizedBox(height: 16),

              // 태그 (선택)
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: '태그 (선택)',
                  hintText: 'math, geometry, circumcenter (쉼표로 구분)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // 참고 URL (선택)
              TextFormField(
                controller: _referenceUrlController,
                decoration: const InputDecoration(
                  labelText: '참고 URL (선택)',
                  hintText: 'https://example.com/reference',
                  border: OutlineInputBorder(),
                  helperText: '입력하면 글 마지막에 Reference 섹션이 추가됩니다',
                ),
              ),
              const SizedBox(height: 24),

              // 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        final options = ConversionOptions(
                          date: _selectedDate,
                          subject: _subjectController.text.trim(),
                          title: _titleController.text.trim(),
                          category: _selectedCategory,
                          tags: _parseTags(),
                          referenceUrl: _referenceUrlController.text.trim().isEmpty
                              ? null
                              : _referenceUrlController.text.trim(),
                        );
                        Navigator.pop(context, options);
                      }
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('확인'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
