import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import 'blog_repository.dart';

/// 로컬 Jekyll 블로그 폴더를 직접 읽고 쓰는 저장소 (데스크톱 전용)
class LocalBlogRepository implements BlogRepository {
  final String blogPath;

  LocalBlogRepository({required this.blogPath});

  @override
  String get label => '로컬 폴더';

  @override
  String get location => blogPath;

  @override
  bool get isLocal => true;

  @override
  String? get assetBaseUrl => null;

  Directory get _postsDir => Directory(p.join(blogPath, AppConstants.defaultPostsFolder));

  File _postFile(String name) => File(p.join(_postsDir.path, name));

  @override
  Future<List<PostInfo>> listPosts() async {
    if (blogPath.isEmpty) throw BlogRepositoryException(AppConstants.errorNoBlogPath);
    if (!await _postsDir.exists()) {
      throw BlogRepositoryException('_posts 폴더가 없습니다: ${_postsDir.path}');
    }

    final result = <PostInfo>[];
    await for (final entity in _postsDir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) continue;
      final name = p.basename(entity.path);
      String head = '';
      try {
        // frontmatter 만 필요하므로 앞부분만 읽는다
        final raf = await entity.open();
        final bytes = await raf.read(4096);
        await raf.close();
        head = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
      result.add(PostInfo.fromContent(name, head, modified: entity.lastModifiedSync()));
    }
    result.sort((a, b) => b.modified.compareTo(a.modified));
    return result;
  }

  @override
  Future<String> readPost(String name) => _postFile(name).readAsString();

  @override
  Future<bool> postExists(String name) => _postFile(name).exists();

  @override
  Future<void> writePost(String name, String content, {String? previousName}) async {
    if (!await _postsDir.exists()) await _postsDir.create(recursive: true);
    await _postFile(name).writeAsString(content);
    if (previousName != null && previousName != name) {
      try {
        await _postFile(previousName).delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> deletePost(String name) => _postFile(name).delete();

  @override
  Future<String> uploadImage(String fileName, Uint8List bytes) async {
    final assetsDir = Directory(p.join(blogPath, 'assets', 'images'));
    if (!await assetsDir.exists()) await assetsDir.create(recursive: true);
    await File(p.join(assetsDir.path, fileName)).writeAsBytes(bytes);
    return '/assets/images/$fileName';
  }

  @override
  Future<String?> readTextFile(String path) async {
    final file = File(p.join(blogPath, path.replaceAll('/', p.separator)));
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> listFiles(String dirPath, {bool recursive = false, String? extension}) async {
    final dir = Directory(p.join(blogPath, dirPath.replaceAll('/', p.separator)));
    if (!await dir.exists()) return [];
    final result = <String>[];
    await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
      if (entity is! File) continue;
      if (extension != null && !entity.path.endsWith(extension)) continue;
      result.add(p.relative(entity.path, from: blogPath).replaceAll(p.separator, '/'));
    }
    result.sort();
    return result;
  }

  @override
  Future<void> refresh() async {}
}
