/// Represents a blog post with its metadata and content
class BlogPost {
  final String title;
  final String content;
  final Map<String, dynamic> frontmatter;
  final String? filePath;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final List<String> tags;
  final List<String> imageAttachments;

  BlogPost({
    required this.title,
    required this.content,
    required this.frontmatter,
    this.filePath,
    this.createdAt,
    this.modifiedAt,
    this.tags = const [],
    this.imageAttachments = const [],
  });

  /// Creates a BlogPost from a markdown file content
  factory BlogPost.fromMarkdown(String markdown, {String? filePath}) {
    final parsedData = _parseFrontmatter(markdown);
    final frontmatter = parsedData['frontmatter'] as Map<String, dynamic>;
    final content = parsedData['content'] as String;

    // Extract title from frontmatter
    final title = frontmatter['title']?.toString() ?? '';

    // Extract tags if present
    final tags = <String>[];
    if (frontmatter['tags'] != null) {
      if (frontmatter['tags'] is List) {
        tags.addAll((frontmatter['tags'] as List).map((e) => e.toString()));
      } else if (frontmatter['tags'] is String) {
        // Handle comma-separated tags string
        tags.addAll(
          frontmatter['tags']
              .toString()
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty),
        );
      }
    }

    return BlogPost(
      title: title,
      content: content,
      frontmatter: frontmatter,
      filePath: filePath,
      tags: tags,
    );
  }

  /// Parses YAML frontmatter from markdown content (static helper)
  static Map<String, dynamic> _parseFrontmatter(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    final frontmatter = <String, dynamic>{};
    var content = markdown;

    // Check if content starts with frontmatter (---)
    if (lines.isNotEmpty && lines[0].trim() == '---') {
      int endIndex = -1;
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].trim() == '---') {
          endIndex = i;
          break;
        }
      }

      if (endIndex > 0) {
        final frontmatterText = lines.sublist(1, endIndex).join('\n');
        content = lines.sublist(endIndex + 1).join('\n').trim();

        try {
          // Use simple key-value parsing instead of YAML library
          for (var line in frontmatterText.split('\n')) {
            if (line.trim().isEmpty || !line.contains(':')) continue;

            final colonIndex = line.indexOf(':');
            if (colonIndex > 0) {
              final key = line.substring(0, colonIndex).trim();
              var value = line.substring(colonIndex + 1).trim();

              // Remove quotes if present
              if (value.startsWith('"') && value.endsWith('"')) {
                value = value.substring(1, value.length - 1);
              }

              // Parse array format: [item1, item2, item3]
              if (value.startsWith('[') && value.endsWith(']')) {
                final items = value.substring(1, value.length - 1)
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                frontmatter[key] = items;
              } else {
                frontmatter[key] = value;
              }
            }
          }
        } catch (e) {
          print('Error parsing frontmatter: $e');
        }
      }
    }

    return {
      'frontmatter': frontmatter,
      'content': content,
    };
  }

  /// Converts the blog post to GitHub-compatible markdown format
  String toGitHubMarkdown() {
    print('\n=== toGitHubMarkdown DEBUG ===');
    print('Frontmatter: $frontmatter');

    final buffer = StringBuffer();

    // Write frontmatter
    if (frontmatter.isNotEmpty) {
      buffer.writeln('---');
      frontmatter.forEach((key, value) {
        print('Processing key: $key, value: $value (type: ${value.runtimeType})');

        if (value is List) {
          // tags는 인라인 리스트 형태로 출력: tags: [tag1, tag2, tag3]
          if (key == 'tags') {
            final line = '$key: [${value.join(', ')}]';
            print('  Writing tags line: $line');
            buffer.writeln(line);
          } else {
            // 다른 리스트는 기존 방식 유지
            buffer.writeln('$key:');
            for (var item in value) {
              buffer.writeln('  - $item');
            }
          }
        } else {
          // title은 항상 큰따옴표로 감싸기
          if (key == 'title') {
            final line = '$key: "$value"';
            print('  Writing title line: $line');
            buffer.writeln(line);
          } else {
            final line = '$key: $value';
            print('  Writing line: $line');
            buffer.writeln(line);
          }
        }
      });
      buffer.writeln('---');
      buffer.writeln();
    }

    // Write content
    buffer.write(content);

    print('=== END toGitHubMarkdown DEBUG ===\n');

    return buffer.toString();
  }

  BlogPost copyWith({
    String? title,
    String? content,
    Map<String, dynamic>? frontmatter,
    String? filePath,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<String>? tags,
    List<String>? imageAttachments,
  }) {
    return BlogPost(
      title: title ?? this.title,
      content: content ?? this.content,
      frontmatter: frontmatter ?? this.frontmatter,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      tags: tags ?? this.tags,
      imageAttachments: imageAttachments ?? this.imageAttachments,
    );
  }
}
