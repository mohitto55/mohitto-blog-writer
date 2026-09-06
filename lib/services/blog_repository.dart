import 'dart:typed_data';

import '../models/jekyll_post.dart';

/// `_posts` 목록에 보여줄 포스트 요약 정보
class PostInfo {
  final String name;
  final String title;
  final String category;
  final List<String> tags;
  final DateTime? date;
  final DateTime modified;

  const PostInfo({
    required this.name,
    required this.title,
    required this.category,
    required this.tags,
    required this.date,
    required this.modified,
  });

  bool get isPublished => JekyllPost.isPublishedFileName(name);
  bool get isDraft => JekyllPost.isDraftFileName(name);
  bool get isTemplate => JekyllPost.isTemplateFileName(name);

  String get dateLabel {
    final d = date;
    if (d != null) return _fmt(d);
    return '수정 ${_fmt(modified)}';
  }

  static String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 파일 내용(앞부분이라도)에서 요약 정보를 만든다
  factory PostInfo.fromContent(String name, String content, {DateTime? modified}) {
    final post = JekyllPost.parse(content);
    final date = JekyllPost.dateFromFileName(name);
    return PostInfo(
      name: name,
      title: post.fullTitle,
      category: post.category,
      tags: post.tags,
      date: date,
      modified: modified ?? date ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 블로그 저장소 추상화.
///
/// - [LocalBlogRepository] : 로컬 Jekyll 폴더 (데스크톱). git push 는 별도.
/// - [GitHubBlogRepository] : GitHub REST API 로 직접 읽고 커밋 (모바일/웹).
abstract class BlogRepository {
  /// 화면에 보여줄 이름 (예: `로컬 폴더`, `GitHub`)
  String get label;

  /// 위치 설명 (경로 또는 owner/repo@branch)
  String get location;

  /// 로컬 파일 시스템 기반인지 (Jekyll 서버, git 명령, 탐색기 열기 등이 가능한지)
  bool get isLocal;

  /// 미리보기에서 `/assets/…` 같은 사이트 상대 경로를 그릴 때 쓸 기준 URL. 로컬이면 null.
  String? get assetBaseUrl;

  Future<List<PostInfo>> listPosts();

  Future<String> readPost(String name);

  Future<bool> postExists(String name);

  /// 저장. [previousName] 이 있고 이름이 다르면 이름 변경(옛 파일 삭제)으로 처리한다.
  Future<void> writePost(String name, String content, {String? previousName});

  Future<void> deletePost(String name);

  /// 이미지를 `assets/images/` 에 넣고 마크다운에 쓸 사이트 상대 경로를 돌려준다.
  Future<String> uploadImage(String fileName, Uint8List bytes);

  /// 저장소 루트 기준 상대 경로의 텍스트 파일. 없으면 null.
  Future<String?> readTextFile(String path);

  /// [dirPath] 아래 파일 경로 목록 (저장소 루트 기준 상대 경로, `/` 구분자)
  Future<List<String>> listFiles(String dirPath, {bool recursive = false, String? extension});

  /// 목록/캐시를 새로 읽게 한다
  Future<void> refresh();
}

/// 사용자에게 보여줄 수 있는 저장소 오류
class BlogRepositoryException implements Exception {
  final String message;
  BlogRepositoryException(this.message);

  @override
  String toString() => message;
}
