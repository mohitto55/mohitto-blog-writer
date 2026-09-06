import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../models/blog_post.dart';
import 'obsidian_service.dart';
import 'converter_service.dart';
import 'jekyll_service.dart';

/// Service for local preview workflow
class LocalPreviewService {
  final ObsidianService obsidianService;
  final ConverterService converterService;
  final JekyllService jekyllService;

  LocalPreviewService({
    required this.obsidianService,
    required this.converterService,
    required this.jekyllService,
  });

  /// Preview a single post locally
  Future<PreviewResult> previewPost(File file) async {
    try {
      // Step 1: Read the blog post from Obsidian
      final blogPost = await obsidianService.readBlogPost(file);

      // Step 2: Copy images to Jekyll assets
      final imagePathMapping = <String, String>{};

      for (final imagePath in blogPost.imageAttachments) {
        try {
          final jekyllImagePath = await jekyllService.copyImageToAssets(imagePath);
          imagePathMapping[imagePath] = jekyllImagePath;
        } catch (e) {
          print('Failed to copy image $imagePath: $e');
        }
      }

      // Step 3: Convert the post to GitHub format (which works for Jekyll too)
      final convertedPost = converterService.convertPost(
        blogPost,
        imagePathMapping: imagePathMapping,
      );

      // Step 4: Generate filename
      final filename = converterService.generateFilename(convertedPost);

      // Step 5: Save to Jekyll _posts folder
      final content = convertedPost.toGitHubMarkdown();
      await jekyllService.saveToPostsFolder(content, filename);

      // Step 6: Ensure Jekyll server is running
      if (!jekyllService.isRunning) {
        final started = await jekyllService.startServer();
        if (!started) {
          return PreviewResult(
            success: false,
            error: 'Failed to start Jekyll server',
          );
        }
      }

      // Step 7: Open browser to Jekyll server
      await _openBrowser(jekyllService.serverUrl);

      return PreviewResult(
        success: true,
        filename: filename,
        url: jekyllService.serverUrl,
        message: 'Preview opened in browser. Jekyll will auto-reload when files change.',
      );
    } catch (e) {
      return PreviewResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Preview multiple posts
  Future<List<PreviewResult>> previewMultiplePosts(List<File> files) async {
    final results = <PreviewResult>[];

    // Copy all posts first
    for (final file in files) {
      final result = await previewPost(file);
      results.add(result);

      // Only open browser once
      if (results.length == 1 && result.success) {
        // Browser already opened in first preview
      }
    }

    return results;
  }

  /// Start Jekyll server without previewing a specific post
  Future<bool> startJekyllServer() async {
    return await jekyllService.startServer();
  }

  /// Stop Jekyll server
  Future<void> stopJekyllServer() async {
    await jekyllService.stopServer();
  }

  /// Open browser to Jekyll server
  Future<void> openJekyllSite() async {
    if (!jekyllService.isRunning) {
      throw Exception('Jekyll server is not running');
    }

    await _openBrowser(jekyllService.serverUrl);
  }

  /// Open browser to a specific URL
  Future<void> _openBrowser(String url) async {
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } else {
      throw Exception('Could not launch $url');
    }
  }

  /// Check if Jekyll server is running
  bool get isServerRunning => jekyllService.isRunning;

  /// Get Jekyll server URL
  String get serverUrl => jekyllService.serverUrl;

  /// Clean up resources
  Future<void> dispose() async {
    await jekyllService.dispose();
  }
}

/// Result of a preview operation
class PreviewResult {
  final bool success;
  final String? filename;
  final String? url;
  final String? message;
  final String? error;

  PreviewResult({
    required this.success,
    this.filename,
    this.url,
    this.message,
    this.error,
  });

  @override
  String toString() {
    if (success) {
      return 'Preview successful: $filename at $url\n$message';
    } else {
      return 'Preview failed: $error';
    }
  }
}
