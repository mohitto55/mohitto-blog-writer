import 'dart:convert';
import 'package:dio/dio.dart';
import '../core/constants/app_constants.dart';

/// Service for interacting with GitHub API
class GitHubService {
  final String owner;
  final String repo;
  final String token;
  late final Dio _dio;

  GitHubService({
    required this.owner,
    required this.repo,
    required this.token,
  }) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.githubApiBaseUrl,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': AppConstants.githubApiVersion,
      },
    ));
  }

  /// Gets the content of a file in the repository
  Future<GitHubFile?> getFile(String path) async {
    try {
      final response = await _dio.get('/repos/$owner/$repo/contents/$path');

      if (response.statusCode == 200) {
        return GitHubFile.fromJson(response.data);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null; // File does not exist
      }
      rethrow;
    }

    return null;
  }

  /// Creates or updates a file in the repository
  Future<void> createOrUpdateFile({
    required String path,
    required String content,
    required String message,
    String? sha,
  }) async {
    final body = {
      'message': message,
      'content': base64Encode(utf8.encode(content)),
      if (sha != null) 'sha': sha,
    };

    final response = await _dio.put(
      '/repos/$owner/$repo/contents/$path',
      data: body,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create/update file: ${response.statusMessage}');
    }
  }

  /// Uploads an image file to the repository
  Future<String> uploadImage({
    required String imagePath,
    required List<int> imageBytes,
    required String commitMessage,
  }) async {
    // Check if file already exists
    final existingFile = await getFile(imagePath);

    await createOrUpdateFile(
      path: imagePath,
      content: base64Encode(imageBytes),
      message: commitMessage,
      sha: existingFile?.sha,
    );

    // Return the public URL of the uploaded image
    return 'https://raw.githubusercontent.com/$owner/$repo/main/$imagePath';
  }

  /// Deletes a file from the repository
  Future<void> deleteFile({
    required String path,
    required String message,
  }) async {
    final file = await getFile(path);

    if (file == null) {
      throw Exception('File not found: $path');
    }

    final response = await _dio.delete(
      '/repos/$owner/$repo/contents/$path',
      data: {
        'message': message,
        'sha': file.sha,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete file: ${response.statusMessage}');
    }
  }

  /// Lists all files in a directory
  Future<List<GitHubFile>> listDirectory(String path) async {
    try {
      final response = await _dio.get('/repos/$owner/$repo/contents/$path');

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => GitHubFile.fromJson(item))
            .toList();
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return []; // Directory does not exist
      }
      rethrow;
    }

    return [];
  }

  /// Publishes a blog post to GitHub
  Future<void> publishPost({
    required String filename,
    required String content,
    String folder = '_posts',
  }) async {
    final path = '$folder/$filename';
    final existingFile = await getFile(path);

    await createOrUpdateFile(
      path: path,
      content: content,
      message: existingFile != null
          ? 'Update post: $filename'
          : 'Publish new post: $filename',
      sha: existingFile?.sha,
    );
  }

  /// Batch uploads multiple images
  Future<Map<String, String>> uploadImages({
    required Map<String, List<int>> images,
    String folder = 'assets/images',
  }) async {
    final pathMapping = <String, String>{};

    for (final entry in images.entries) {
      final imageName = entry.key.split('/').last;
      final imagePath = '$folder/$imageName';

      try {
        final url = await uploadImage(
          imagePath: imagePath,
          imageBytes: entry.value,
          commitMessage: 'Upload image: $imageName',
        );

        pathMapping[entry.key] = url;
      } catch (e) {
        print('Failed to upload image $imageName: $e');
        rethrow;
      }
    }

    return pathMapping;
  }
}

/// Represents a file in GitHub repository
class GitHubFile {
  final String name;
  final String path;
  final String sha;
  final int size;
  final String type; // "file" or "dir"
  final String? downloadUrl;
  final String? content;

  GitHubFile({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    required this.type,
    this.downloadUrl,
    this.content,
  });

  factory GitHubFile.fromJson(Map<String, dynamic> json) {
    return GitHubFile(
      name: json['name'] as String,
      path: json['path'] as String,
      sha: json['sha'] as String,
      size: json['size'] as int,
      type: json['type'] as String,
      downloadUrl: json['download_url'] as String?,
      content: json['content'] as String?,
    );
  }

  /// Decodes base64 content
  String? get decodedContent {
    if (content == null) return null;
    try {
      return utf8.decode(base64Decode(content!.replaceAll('\n', '')));
    } catch (e) {
      return null;
    }
  }
}
