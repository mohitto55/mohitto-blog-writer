import 'package:yaml/yaml.dart';
import '../models/blog_post.dart';
import '../models/conversion_rule.dart';
import '../core/constants/app_constants.dart';

/// Service for converting Obsidian markdown to GitHub blog markdown
class ConverterService {
  final List<ConversionRule> conversionRules;

  ConverterService({List<ConversionRule>? customRules})
      : conversionRules = customRules ?? DefaultConversionRules.all();

  /// Converts a BlogPost from Obsidian format to GitHub blog format
  BlogPost convertPost(BlogPost post, {Map<String, String>? imagePathMapping}) {
    // Parse frontmatter from content
    final parsedContent = _parseFrontmatter(post.content);
    final frontmatter = parsedContent['frontmatter'] as Map<String, dynamic>;
    var content = parsedContent['content'] as String;

    // Remove any remaining frontmatter blocks in content
    content = _removeAllFrontmatterBlocks(content);

    // Convert frontmatter keys
    final convertedFrontmatter = _convertFrontmatter(frontmatter);

    // Auto-generate title if missing
    if (!convertedFrontmatter.containsKey('title') ||
        convertedFrontmatter['title']?.toString().trim().isEmpty == true) {
      final generatedTitle = _generateTitleFromFile(post);
      convertedFrontmatter['title'] = generatedTitle;
      print('Auto-generated title: $generatedTitle');
    }

    // Apply conversion rules to content
    var convertedContent = content;
    for (final rule in conversionRules) {
      convertedContent = rule.apply(convertedContent);
    }

    // Replace image paths if mapping is provided
    if (imagePathMapping != null) {
      convertedContent = _replaceImagePaths(convertedContent, imagePathMapping);
    }

    // Always add Reference template if not present
    if (!convertedContent.contains('<div class="Reference">')) {
      convertedContent = _addEmptyReferenceTemplate(convertedContent);
      print('Added empty Reference template to preview');
    }

    return post.copyWith(
      frontmatter: convertedFrontmatter,
      content: convertedContent,
    );
  }

  /// Removes all frontmatter blocks (---...---) from content
  String _removeAllFrontmatterBlocks(String content) {
    print('\n=== _removeAllFrontmatterBlocks DEBUG ===');

    // Remove all YAML frontmatter blocks from content
    final pattern = RegExp(
      r'^---\s*\n.*?\n---\s*$',
      multiLine: true,
      dotAll: true,
    );

    final matches = pattern.allMatches(content);
    print('Found ${matches.length} frontmatter blocks in content');

    if (matches.isNotEmpty) {
      var cleanedContent = content;
      for (final match in matches) {
        final block = match.group(0)!;
        print('Removing frontmatter block (${block.length} chars)');
        cleanedContent = cleanedContent.replaceFirst(block, '');
      }

      print('Cleaned content length: ${cleanedContent.length} (was ${content.length})');
      print('=== END _removeAllFrontmatterBlocks DEBUG ===\n');

      return cleanedContent.trim();
    }

    print('No frontmatter blocks found in content');
    print('=== END _removeAllFrontmatterBlocks DEBUG ===\n');

    return content;
  }

  /// Generates title from filename in format: [Subject] Title
  /// Date is handled separately in frontmatter
  String _generateTitleFromFile(BlogPost post) {
    // Extract filename from path
    String fileName = 'Untitled';
    if (post.filePath != null) {
      final pathParts = post.filePath!.split(RegExp(r'[/\\]'));
      fileName = pathParts.last.replaceAll('.md', '');
    }

    // Check if filename already has [Subject] format
    final subjectPattern = RegExp(r'\[([^\]]+)\](.*)');
    final match = subjectPattern.firstMatch(fileName);

    if (match != null) {
      // Filename has [Subject] format: "[Math] 세점을 지나는 원의 중심"
      final subject = match.group(1)!.trim();
      final title = match.group(2)!.trim();
      return '[$subject] $title';
    } else {
      // No subject in filename, use default
      return '[Untitled] $fileName';
    }
  }

  /// Converts a BlogPost with Jekyll template applied (title, categories, tags, reference)
  BlogPost convertPostWithTemplate(
    BlogPost post, {
    Map<String, String>? imagePathMapping,
    String? customTitle,
    String? category,
    List<String>? tags,
    String? referenceUrl,
    DateTime? publishDate,
  }) {
    print('\n=== convertPostWithTemplate DEBUG ===');
    print('customTitle: $customTitle');
    print('category: $category');
    print('tags: $tags');
    print('referenceUrl: $referenceUrl');
    print('publishDate: $publishDate');

    // First, apply standard conversion
    var converted = convertPost(post, imagePathMapping: imagePathMapping);

    print('After convertPost - frontmatter keys: ${converted.frontmatter.keys}');

    // Enhance frontmatter with template fields
    final enhancedFrontmatter = Map<String, dynamic>.from(converted.frontmatter);

    // Override title if custom title is provided
    if (customTitle != null && customTitle.isNotEmpty) {
      print('Setting title to: $customTitle');
      enhancedFrontmatter['title'] = customTitle;
    }

    // Add/override publish date
    if (publishDate != null) {
      final dateStr = '${publishDate.year}-${publishDate.month.toString().padLeft(2, '0')}-${publishDate.day.toString().padLeft(2, '0')}';
      print('Setting date to: $dateStr');
      enhancedFrontmatter['date'] = dateStr;
    }

    // Add category if provided
    if (category != null && category.isNotEmpty) {
      print('Setting categories to: $category');
      enhancedFrontmatter['categories'] = category;
    }

    // Add tags if provided
    if (tags != null && tags.isNotEmpty) {
      print('Setting tags to: $tags');
      enhancedFrontmatter['tags'] = tags;
    }

    print('Final frontmatter: $enhancedFrontmatter');

    // Add Reference section at the end if URL is provided
    var enhancedContent = converted.content;
    if (referenceUrl != null && referenceUrl.isNotEmpty) {
      print('Adding reference URL: $referenceUrl');
      enhancedContent = _addReferenceSection(enhancedContent, referenceUrl);
    }

    print('=== END DEBUG ===\n');

    return converted.copyWith(
      frontmatter: enhancedFrontmatter,
      content: enhancedContent,
    );
  }

  /// Adds empty Reference template at the end of content
  String _addEmptyReferenceTemplate(String content) {
    final referenceTemplate = '''

<br>
---
<br>

<div class="Reference">
<div class="callout-header"> </div>
<p>
<a href=""></a>
</p>
</div>''';

    return content + referenceTemplate;
  }

  /// Adds Reference section at the end of content
  String _addReferenceSection(String content, String referenceUrl) {
    print('\n=== _addReferenceSection DEBUG ===');
    print('referenceUrl: $referenceUrl');
    print('content length: ${content.length}');
    print('Contains existing Reference: ${content.contains('<div class="Reference">')}');

    // Check if Reference section already exists
    if (content.contains('<div class="Reference">')) {
      print('Found existing Reference section, trying to add URL to it');

      // Find the closing </p> tag inside Reference section and add new URL before it
      final referencePattern = RegExp(
        r'(<div class="Reference">.*?<p>)(.*?)(</p>.*?</div>)',
        dotAll: true,
      );

      final match = referencePattern.firstMatch(content);
      if (match != null) {
        print('Regex matched! Adding URL to existing Reference');
        final beforeUrls = match.group(1)!;
        final existingUrls = match.group(2)!;
        final afterUrls = match.group(3)!;

        // Add new URL with proper line break
        final newUrl = '<br>\n<a href="$referenceUrl">$referenceUrl</a>';
        final updatedContent = content.replaceFirst(
          referencePattern,
          '$beforeUrls$existingUrls$newUrl$afterUrls',
        );

        print('Successfully added URL to existing Reference');
        print('=== END _addReferenceSection DEBUG ===\n');
        return updatedContent;
      }

      // If pattern doesn't match, return content as is
      print('WARNING: Regex did not match existing Reference section!');
      print('=== END _addReferenceSection DEBUG ===\n');
      return content;
    }

    // No existing Reference section, create new one
    print('No existing Reference section, creating new one');
    final referenceSection = '''

<br>
---
<br>

<div class="Reference">
<div class="callout-header"> </div>
<p>
<a href="$referenceUrl">$referenceUrl</a>
</p>
</div>''';

    print('Successfully created new Reference section');
    print('=== END _addReferenceSection DEBUG ===\n');
    return content + referenceSection;
  }

  /// Parses YAML frontmatter from markdown content
  Map<String, dynamic> _parseFrontmatter(String markdown) {
    // Handle both Windows (\r\n) and Unix (\n) line endings
    final lines = markdown.split(RegExp(r'\r?\n'));
    final frontmatter = <String, dynamic>{};
    var content = markdown;

    print('\n=== _parseFrontmatter DEBUG ===');
    print('Total lines: ${lines.length}');
    print('First line: "${lines.isNotEmpty ? lines[0] : ''}"');

    // Check if content starts with frontmatter (---)
    if (lines.isNotEmpty && lines[0].trim() == '---') {
      print('Found first --- delimiter');

      // Find the second --- delimiter (end of frontmatter)
      int endIndex = -1;
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].trim() == '---') {
          endIndex = i;
          print('Found second --- delimiter at line $i');
          break;
        }
      }

      if (endIndex > 0) {
        print('Extracting frontmatter from lines 1 to $endIndex');

        // Extract frontmatter text (between two --- delimiters)
        final frontmatterLines = lines.sublist(1, endIndex);
        print('Frontmatter lines: ${frontmatterLines.length}');

        // Extract content (after second --- delimiter)
        content = lines.sublist(endIndex + 1).join('\n').trim();
        print('Content length after removing frontmatter: ${content.length}');

        // Try to parse frontmatter with YAML
        final frontmatterText = frontmatterLines.join('\n');
        try {
          final parsed = loadYaml(frontmatterText);
          if (parsed is Map) {
            frontmatter.addAll(Map<String, dynamic>.from(parsed));
            print('Successfully parsed frontmatter: ${frontmatter.keys}');
          }
        } catch (e) {
          print('Error parsing frontmatter with YAML: $e');
          print('Frontmatter will be empty, content will be used as-is');
        }
      } else {
        print('WARNING: Second --- delimiter not found!');
      }
    } else {
      print('No frontmatter found (first line is not ---)');
    }

    print('=== END _parseFrontmatter DEBUG ===\n');

    return {
      'frontmatter': frontmatter,
      'content': content,
    };
  }

  /// Converts frontmatter keys from Obsidian format to GitHub blog format
  /// Only keeps Jekyll-required fields and removes Obsidian-specific fields
  Map<String, dynamic> _convertFrontmatter(Map<String, dynamic> frontmatter) {
    final converted = <String, dynamic>{};

    // Only extract Jekyll-required fields from original frontmatter
    // 1. Title (if exists)
    if (frontmatter.containsKey('title') && frontmatter['title'] != null) {
      converted['title'] = frontmatter['title'];
    }

    // 2. Date (from created or use current date)
    if (frontmatter.containsKey('created')) {
      final createdValue = frontmatter['created'].toString();
      // Try to extract YYYY-MM-DD format
      final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(createdValue);
      if (dateMatch != null) {
        converted['date'] = dateMatch.group(1);
      } else {
        converted['date'] = DateTime.now().toIso8601String().split('T')[0];
      }
    } else if (frontmatter.containsKey('date')) {
      converted['date'] = frontmatter['date'];
    } else {
      converted['date'] = DateTime.now().toIso8601String().split('T')[0];
    }

    // 3. Categories (if exists)
    if (frontmatter.containsKey('categories')) {
      converted['categories'] = frontmatter['categories'];
    } else if (frontmatter.containsKey('category')) {
      converted['categories'] = frontmatter['category'];
    }

    // 4. Tags (if exists and is not Obsidian-specific)
    if (frontmatter.containsKey('tags')) {
      final tags = frontmatter['tags'];
      // Filter out Obsidian-specific tags like "Clips"
      if (tags is List) {
        final filteredTags = tags
            .where((tag) => !tag.toString().toLowerCase().contains('clips'))
            .toList();
        if (filteredTags.isNotEmpty) {
          converted['tags'] = filteredTags;
        }
      }
    }

    // 5. Always add published flag
    converted['published'] = true;

    print('Converted frontmatter from ${frontmatter.keys} to ${converted.keys}');

    return converted;
  }

  /// Replaces image paths in content using the provided mapping
  String _replaceImagePaths(String content, Map<String, String> pathMapping) {
    var result = content;

    pathMapping.forEach((originalPath, newPath) {
      // Replace various image reference formats
      final imageName = originalPath.split('/').last;

      // Replace markdown image syntax
      result = result.replaceAll(
        '![](/assets/images/$imageName)',
        '![]($newPath)',
      );

      // Replace HTML img tags if any
      result = result.replaceAll(
        'src="/assets/images/$imageName"',
        'src="$newPath"',
      );
    });

    return result;
  }

  /// Generates a slug from title (for filename)
  String generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
  }

  /// Generates filename for GitHub blog post
  String generateFilename(BlogPost post, {String? customFileName}) {
    // If custom filename is provided, use it
    if (customFileName != null && customFileName.isNotEmpty) {
      return customFileName.endsWith(AppConstants.markdownExtension)
          ? customFileName
          : '$customFileName${AppConstants.markdownExtension}';
    }

    final date = post.createdAt ?? DateTime.now();
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final title = post.frontmatter['title']?.toString() ?? post.title;
    final slug = generateSlug(title);

    return '$dateStr-$slug${AppConstants.markdownExtension}';
  }

  /// Extracts all image references from content
  List<String> extractImageReferences(String content) {
    final imagePattern = RegExp(r'!\[.*?\]\(([^)]+)\)');
    final matches = imagePattern.allMatches(content);

    return matches.map((m) => m.group(1)!).toList();
  }
}
