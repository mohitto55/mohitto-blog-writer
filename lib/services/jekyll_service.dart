import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;

/// Service for managing local Jekyll server and preview
class JekyllService {
  final String blogPath;
  Process? _serverProcess;
  bool _isRunning = false;

  JekyllService({required this.blogPath});

  /// Check if Jekyll server is currently running
  bool get isRunning => _isRunning;

  /// Start Jekyll server
  Future<bool> startServer() async {
    if (_isRunning) {
      print('Jekyll server is already running');
      return true;
    }

    try {
      print('Starting Jekyll server at: $blogPath');

      // Check if blog path exists
      final blogDir = Directory(blogPath);
      if (!await blogDir.exists()) {
        throw Exception('Blog directory not found: $blogPath');
      }

      // Start Jekyll server with bundle exec
      _serverProcess = await Process.start(
        'bundle',
        ['exec', 'jekyll', 'serve', '--livereload'],
        workingDirectory: blogPath,
        runInShell: true,
      );

      // Listen to server output
      _serverProcess!.stdout.listen((data) {
        print('Jekyll: ${String.fromCharCodes(data)}');
      });

      _serverProcess!.stderr.listen((data) {
        print('Jekyll Error: ${String.fromCharCodes(data)}');
      });

      // Wait a bit for server to start
      await Future.delayed(Duration(seconds: 3));

      // Check if server is actually running
      final isServerUp = await _checkServerHealth();

      if (isServerUp) {
        _isRunning = true;
        print('Jekyll server started successfully');
        return true;
      } else {
        print('Jekyll server failed to start');
        await stopServer();
        return false;
      }
    } catch (e) {
      print('Error starting Jekyll server: $e');
      _isRunning = false;
      return false;
    }
  }

  /// 서버가 응답하면 그대로 두고, 아니면 시작한다. (외부에서 띄운 서버도 인식)
  Future<bool> ensureRunning() async {
    if (await _checkServerHealth()) {
      _isRunning = true;
      return true;
    }
    _isRunning = false;
    final started = await startServer();
    if (started) return true;

    // 첫 빌드가 오래 걸리는 경우를 위해 조금 더 기다린다
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (await _checkServerHealth()) {
        _isRunning = true;
        return true;
      }
    }
    return false;
  }

  /// Stop Jekyll server
  Future<void> stopServer() async {
    if (_serverProcess != null) {
      print('Stopping Jekyll server...');

      _serverProcess!.kill(ProcessSignal.sigterm);
      await _serverProcess!.exitCode;

      _serverProcess = null;
      _isRunning = false;

      print('Jekyll server stopped');
    }
  }

  /// Check if Jekyll server is responding
  Future<bool> _checkServerHealth() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://localhost:4000'));
      final response = await request.close().timeout(Duration(seconds: 5));

      client.close();
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Copy a markdown file to Jekyll _posts folder
  Future<void> copyToPostsFolder(String sourceFilePath, String fileName) async {
    final postsDir = Directory(path.join(blogPath, '_posts'));

    // Create _posts directory if it doesn't exist
    if (!await postsDir.exists()) {
      await postsDir.create(recursive: true);
    }

    final sourceFile = File(sourceFilePath);
    final targetPath = path.join(postsDir.path, fileName);
    final targetFile = File(targetPath);

    // Copy file
    await sourceFile.copy(targetPath);

    print('Copied to Jekyll: $targetPath');
  }

  /// Copy markdown content (string) to Jekyll _posts folder
  Future<String> saveToPostsFolder(String content, String fileName) async {
    final postsDir = Directory(path.join(blogPath, '_posts'));

    // Create _posts directory if it doesn't exist
    if (!await postsDir.exists()) {
      await postsDir.create(recursive: true);
    }

    final targetPath = path.join(postsDir.path, fileName);
    final targetFile = File(targetPath);

    // Write content
    await targetFile.writeAsString(content);

    print('Saved to Jekyll: $targetPath');
    return targetPath;
  }

  /// Copy images to Jekyll assets folder
  Future<String> copyImageToAssets(String sourceImagePath) async {
    final imageName = path.basename(sourceImagePath);
    final assetsDir = Directory(path.join(blogPath, 'assets', 'images'));

    // Create assets/images directory if it doesn't exist
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }

    final sourceFile = File(sourceImagePath);
    final targetPath = path.join(assetsDir.path, imageName);

    // Copy image
    await sourceFile.copy(targetPath);

    print('Copied image to Jekyll: $targetPath');

    // Return relative path for Jekyll
    return '/assets/images/$imageName';
  }

  /// Remove a file from _posts folder
  Future<void> removeFromPostsFolder(String fileName) async {
    final targetPath = path.join(blogPath, '_posts', fileName);
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      await targetFile.delete();
      print('Removed from Jekyll: $targetPath');
    }
  }

  /// Get Jekyll server URL
  String get serverUrl => 'http://localhost:4000';

  /// Get URL for a specific post (requires post slug)
  String getPostUrl(String slug) {
    // Jekyll typically uses /year/month/day/slug format
    // For preview, we can use the base URL and let user navigate
    return serverUrl;
  }

  /// Clean up resources
  Future<void> dispose() async {
    await stopServer();
  }
}
