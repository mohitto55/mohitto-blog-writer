import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import 'blog_repository.dart';

/// GitHub REST API 로 블로그 저장소를 직접 읽고 커밋하는 저장소 (모바일/웹, 또는 데스크톱에서 선택)
///
/// - 트리 API 한 번으로 모든 파일 경로와 blob sha 를 받는다.
/// - 파일 내용은 sha 기준으로 캐시하므로 바뀐 파일만 다시 받는다.
/// - 저장은 Contents API 로 커밋 한 번씩 만든다.
class GitHubBlogRepository implements BlogRepository {
  final String owner;
  final String repo;
  final String token;
  final String? branchOverride;
  final SharedPreferences? prefs;

  late final Dio _dio;
  String? _branch;
  Map<String, _TreeEntry>? _tree;
  final Map<String, String> _memoryCache = {};

  GitHubBlogRepository({
    required this.owner,
    required this.repo,
    required this.token,
    this.branchOverride,
    this.prefs,
  }) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.githubApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        // 토큰이 없으면 공개 저장소 읽기만 가능 (쓰기는 401)
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': AppConstants.githubApiVersion,
      },
    ));
  }

  @override
  String get label => 'GitHub';

  @override
  String get location => '$owner/$repo${_branch != null ? '@$_branch' : ''}';

  @override
  bool get isLocal => false;

  @override
  String? get assetBaseUrl => 'https://raw.githubusercontent.com/$owner/$repo/${_branch ?? branchOverride ?? 'main'}';

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _encodePath(String path) => path.split('/').map(Uri.encodeComponent).join('/');

  String _cacheKey(String path) => 'ghc:$owner/$repo:$path';

  Never _fail(Object e, String what) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final msg = (e.response?.data is Map) ? (e.response?.data['message']?.toString() ?? '') : '';
      if (status == 401) throw BlogRepositoryException('GitHub 토큰이 유효하지 않습니다 (401). 설정에서 토큰을 확인하세요.');
      if (status == 403) throw BlogRepositoryException('GitHub 접근이 거부되었습니다 (403). 토큰 권한(Contents: Read and write) 또는 API 한도를 확인하세요. $msg');
      if (status == 404) throw BlogRepositoryException('$what: 찾을 수 없습니다 (404). owner/repo/branch 설정을 확인하세요.');
      if (status == 409) throw BlogRepositoryException('$what: 충돌이 발생했습니다 (409). 목록을 새로고침한 뒤 다시 시도하세요.');
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        throw BlogRepositoryException('GitHub에 연결할 수 없습니다. 네트워크를 확인하세요.');
      }
      throw BlogRepositoryException('$what 실패 (${status ?? e.type.name}) $msg');
    }
    throw BlogRepositoryException('$what 실패: $e');
  }

  Future<String> _resolveBranch() async {
    if (_branch != null) return _branch!;
    if (branchOverride != null && branchOverride!.trim().isNotEmpty) {
      _branch = branchOverride!.trim();
      return _branch!;
    }
    try {
      final res = await _dio.get('/repos/$owner/$repo');
      _branch = (res.data['default_branch'] as String?) ?? 'main';
    } catch (e) {
      _fail(e, '저장소 정보 읽기');
    }
    return _branch!;
  }

  Future<Map<String, _TreeEntry>> _loadTree({bool force = false}) async {
    if (_tree != null && !force) return _tree!;
    final branch = await _resolveBranch();
    try {
      final res = await _dio.get('/repos/$owner/$repo/git/trees/$branch', queryParameters: {'recursive': '1'});
      final entries = <String, _TreeEntry>{};
      for (final item in (res.data['tree'] as List)) {
        if (item['type'] != 'blob') continue;
        entries[item['path'] as String] = _TreeEntry(
          path: item['path'] as String,
          sha: item['sha'] as String,
          size: (item['size'] as num?)?.toInt() ?? 0,
        );
      }
      _tree = entries;
      return entries;
    } catch (e) {
      _fail(e, '파일 목록 읽기');
    }
  }

  /// sha 캐시를 거쳐 텍스트 파일을 읽는다
  Future<String?> _readCached(String path) async {
    final tree = await _loadTree();
    final entry = tree[path];
    if (entry == null) return null;

    final mem = _memoryCache[path];
    if (mem != null) return mem;

    final key = _cacheKey(path);
    final stored = prefs?.getString(key);
    if (stored != null) {
      try {
        final json = jsonDecode(stored) as Map<String, dynamic>;
        if (json['sha'] == entry.sha) {
          final text = json['text'] as String;
          _memoryCache[path] = text;
          return text;
        }
      } catch (_) {}
    }

    final text = await _fetchText(path);
    if (text == null) return null;
    _memoryCache[path] = text;
    if (entry.size <= 200 * 1024) {
      try {
        await prefs?.setString(key, jsonEncode({'sha': entry.sha, 'text': text}));
      } catch (_) {}
    }
    return text;
  }

  Future<String?> _fetchText(String path) async {
    final branch = await _resolveBranch();
    try {
      final res = await _dio.get(
        '/repos/$owner/$repo/contents/${_encodePath(path)}',
        queryParameters: {'ref': branch},
      );
      final data = res.data;
      if (data is! Map) return null;
      if (data['encoding'] == 'base64' && data['content'] != null) {
        return utf8.decode(base64Decode((data['content'] as String).replaceAll('\n', '')), allowMalformed: true);
      }
      // 1MB 이상은 content 가 비어 있으므로 download_url 로 받는다
      final url = data['download_url'] as String?;
      if (url != null) {
        final raw = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain, headers: {'Accept': '*/*'}));
        return raw.data;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      _fail(e, '파일 읽기 ($path)');
    }
  }

  Future<List<T>> _parallel<T>(List<Future<T> Function()> tasks, {int concurrency = 6}) async {
    final results = List<T?>.filled(tasks.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= tasks.length) return;
        results[i] = await tasks[i]();
      }
    }

    await Future.wait(List.generate(concurrency.clamp(1, tasks.length), (_) => worker()));
    return results.cast<T>();
  }

  // ---------------------------------------------------------------------------
  // BlogRepository
  // ---------------------------------------------------------------------------

  @override
  Future<List<PostInfo>> listPosts() async {
    final tree = await _loadTree();
    final paths = tree.keys
        .where((k) => k.startsWith('${AppConstants.defaultPostsFolder}/') && k.toLowerCase().endsWith('.md'))
        .where((k) => !k.substring(AppConstants.defaultPostsFolder.length + 1).contains('/'))
        .toList();

    final infos = await _parallel(paths.map((path) {
      return () async {
        final name = path.substring(AppConstants.defaultPostsFolder.length + 1);
        final text = await _readCached(path) ?? '';
        return PostInfo.fromContent(name, text);
      };
    }).toList());

    infos.sort((a, b) => b.modified.compareTo(a.modified));
    return infos;
  }

  @override
  Future<String> readPost(String name) async {
    final text = await _readCached('${AppConstants.defaultPostsFolder}/$name');
    if (text == null) throw BlogRepositoryException('포스트를 찾을 수 없습니다: $name');
    return text;
  }

  @override
  Future<bool> postExists(String name) async {
    final tree = await _loadTree();
    return tree.containsKey('${AppConstants.defaultPostsFolder}/$name');
  }

  @override
  Future<void> writePost(String name, String content, {String? previousName}) async {
    final path = '${AppConstants.defaultPostsFolder}/$name';
    await _putFile(path, utf8.encode(content), message: previousName == null || previousName == name ? '${await postExists(name) ? 'Update' : 'Add'} post: $name' : 'Rename post: $previousName → $name');
    _memoryCache[path] = content;
    if (previousName != null && previousName != name) {
      await deletePost(previousName);
    }
  }

  @override
  Future<void> deletePost(String name) async {
    final path = '${AppConstants.defaultPostsFolder}/$name';
    final tree = await _loadTree();
    final entry = tree[path];
    if (entry == null) return;
    final branch = await _resolveBranch();
    try {
      await _dio.delete(
        '/repos/$owner/$repo/contents/${_encodePath(path)}',
        data: {'message': 'Delete post: $name', 'sha': entry.sha, 'branch': branch},
      );
      tree.remove(path);
      _memoryCache.remove(path);
      await prefs?.remove(_cacheKey(path));
    } catch (e) {
      _fail(e, '삭제');
    }
  }

  @override
  Future<String> uploadImage(String fileName, Uint8List bytes) async {
    final path = 'assets/images/$fileName';
    await _putFile(path, bytes, message: 'Upload image: $fileName');
    return '/$path';
  }

  Future<void> _putFile(String path, List<int> bytes, {required String message}) async {
    final tree = await _loadTree();
    final branch = await _resolveBranch();
    final existing = tree[path];
    try {
      final res = await _dio.put(
        '/repos/$owner/$repo/contents/${_encodePath(path)}',
        data: {
          'message': message,
          'content': base64Encode(bytes),
          'branch': branch,
          if (existing != null) 'sha': existing.sha,
        },
      );
      final newSha = res.data['content']?['sha'] as String?;
      tree[path] = _TreeEntry(path: path, sha: newSha ?? '', size: bytes.length);
      await prefs?.remove(_cacheKey(path));
    } catch (e) {
      _fail(e, '저장');
    }
  }

  @override
  Future<String?> readTextFile(String path) => _readCached(path);

  @override
  Future<List<String>> listFiles(String dirPath, {bool recursive = false, String? extension}) async {
    final tree = await _loadTree();
    final prefix = dirPath.endsWith('/') ? dirPath : '$dirPath/';
    return tree.keys.where((k) {
      if (!k.startsWith(prefix)) return false;
      if (!recursive && k.substring(prefix.length).contains('/')) return false;
      if (extension != null && !k.endsWith(extension)) return false;
      return true;
    }).toList()
      ..sort();
  }

  @override
  Future<void> refresh() async {
    _memoryCache.clear();
    await _loadTree(force: true);
  }
}

class _TreeEntry {
  final String path;
  final String sha;
  final int size;
  _TreeEntry({required this.path, required this.sha, required this.size});
}
