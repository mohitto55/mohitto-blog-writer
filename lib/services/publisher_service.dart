import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/blog_post.dart';
import 'obsidian_service.dart';
import 'converter_service.dart';
import 'github_service.dart';

/// Main service that orchestrates the publishing workflow
class PublisherService {
  final ObsidianService obsidianService;
  final ConverterService converterService;
  final GitHubService githubService;

  PublisherService({
    required this.obsidianService,
    required this.converterService,
    required this.githubService,
  });

  /// Publishes a single blog post from Obsidian to GitHub
  Future<PublishResult> publishPost(File file) async {
    try {
      // Step 1: Read the blog post from Obsidian
      final blogPost = await obsidianService.readBlogPost(file);

      // Step 2: Upload images first and get the URL mapping
      final imagePathMapping = await _uploadImages(blogPost.imageAttachments);

      // Step 3: Convert the post to GitHub format
      final convertedPost = converterService.convertPost(
        blogPost,
        imagePathMapping: imagePathMapping,
      );

      // Step 4: Generate filename for GitHub
      final filename = converterService.generateFilename(convertedPost);

      // Step 5: Publish to GitHub
      final content = convertedPost.toGitHubMarkdown();
      await githubService.publishPost(
        filename: filename,
        content: content,
      );

      return PublishResult(
        success: true,
        filename: filename,
        uploadedImages: imagePathMapping.length,
      );
    } catch (e) {
      return PublishResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Uploads images and returns path mapping
  Future<Map<String, String>> _uploadImages(List<String> imagePaths) async {
    if (imagePaths.isEmpty) {
      return {};
    }

    final imageBytes = <String, List<int>>{};

    // Read all image files
    for (final imagePath in imagePaths) {
      try {
        final bytes = await obsidianService.readImageBytes(imagePath);
        imageBytes[imagePath] = bytes;
      } catch (e) {
        print('Failed to read image $imagePath: $e');
      }
    }

    // Upload to GitHub
    return await githubService.uploadImages(images: imageBytes);
  }

  /// Publishes multiple posts
  Future<List<PublishResult>> publishMultiplePosts(List<File> files) async {
    final results = <PublishResult>[];

    for (final file in files) {
      final result = await publishPost(file);
      results.add(result);
    }

    return results;
  }

  /// Finds and publishes all posts modified since a certain date
  Future<List<PublishResult>> publishRecentPosts(DateTime since) async {
    final recentFiles = await obsidianService.findRecentlyModified(since);
    return await publishMultiplePosts(recentFiles);
  }

  /// Lists all markdown files available for publishing
  Future<List<File>> listAvailablePosts({String? subfolder}) async {
    return await obsidianService.listMarkdownFiles(subfolder: subfolder);
  }
}

/// Result of a publish operation
class PublishResult {
  final bool success;
  final String? filename;
  final int uploadedImages;
  final String? error;

  PublishResult({
    required this.success,
    this.filename,
    this.uploadedImages = 0,
    this.error,
  });

  @override
  String toString() {
    if (success) {
      return 'Published: $filename (with $uploadedImages images)';
    } else {
      return 'Failed: $error';
    }
  }
}
