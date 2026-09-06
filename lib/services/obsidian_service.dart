import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/blog_post.dart';
import '../core/constants/app_constants.dart';

/// Service for reading files from Obsidian vault
class ObsidianService {
  final String vaultPath;

  ObsidianService({required this.vaultPath});

  /// Lists all markdown files in the vault
  Future<List<File>> listMarkdownFiles({String? subfolder}) async {
    final targetPath = subfolder != null
        ? path.join(vaultPath, subfolder)
        : vaultPath;

    final directory = Directory(targetPath);

    if (!await directory.exists()) {
      throw Exception('Directory does not exist: $targetPath');
    }

    final files = <File>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith(AppConstants.markdownExtension)) {
        files.add(entity);
      }
    }

    return files;
  }

  /// Reads a markdown file and returns its content
  Future<String> readMarkdownFile(File file) async {
    if (!await file.exists()) {
      throw Exception(AppConstants.errorFileNotFound);
    }

    return await file.readAsString();
  }

  /// Gets file metadata (creation and modification times)
  Future<FileMetadata> getFileMetadata(File file) async {
    final stat = await file.stat();
    return FileMetadata(
      path: file.path,
      createdAt: stat.changed,
      modifiedAt: stat.modified,
      size: stat.size,
    );
  }

  /// Reads a markdown file and converts it to BlogPost
  Future<BlogPost> readBlogPost(File file) async {
    final content = await readMarkdownFile(file);
    final metadata = await getFileMetadata(file);

    // Extract images from content
    final imageAttachments = _extractImagePaths(content, file.parent.path);

    return BlogPost.fromMarkdown(
      content,
      filePath: file.path,
    ).copyWith(
      createdAt: metadata.createdAt,
      modifiedAt: metadata.modifiedAt,
      imageAttachments: imageAttachments,
    );
  }

  /// Extracts image file paths from Obsidian embed syntax
  List<String> _extractImagePaths(String content, String basePath) {
    final imagePattern = RegExp(r'!\[\[([^\]]+?)\]\]');
    final matches = imagePattern.allMatches(content);
    final imagePaths = <String>[];

    for (final match in matches) {
      final imageName = match.group(1)!;
      final imagePath = path.join(basePath, imageName);

      // Check if file exists
      if (File(imagePath).existsSync()) {
        imagePaths.add(imagePath);
      } else {
        // Try looking in attachments folder
        final attachmentPath = path.join(vaultPath, 'attachments', imageName);
        if (File(attachmentPath).existsSync()) {
          imagePaths.add(attachmentPath);
        }
      }
    }

    return imagePaths;
  }

  /// Searches for files modified after a certain date
  Future<List<File>> findRecentlyModified(DateTime since) async {
    final allFiles = await listMarkdownFiles();
    final recentFiles = <File>[];

    for (final file in allFiles) {
      final metadata = await getFileMetadata(file);
      if (metadata.modifiedAt.isAfter(since)) {
        recentFiles.add(file);
      }
    }

    return recentFiles;
  }

  /// Reads image file as bytes
  Future<List<int>> readImageBytes(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('Image not found: $imagePath');
    }

    return await file.readAsBytes();
  }
}

/// Metadata for a file
class FileMetadata {
  final String path;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int size;

  FileMetadata({
    required this.path,
    required this.createdAt,
    required this.modifiedAt,
    required this.size,
  });
}
