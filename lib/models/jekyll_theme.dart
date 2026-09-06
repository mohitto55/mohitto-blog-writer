import 'dart:ui';

/// 지킬 블로그의 SCSS에서 발견한 커스텀 블록(콜아웃) 클래스 스타일.
///
/// 예: `.callout-info-expanded`, `.callout-red`, `.Reference`
class BlogBlockStyle {
  final String className;
  final String label;
  final Color borderColor;
  final Color backgroundColor;
  final Color? headerBackground;
  final Color? headerTextColor;

  /// `callout-header` 영역을 가지는 확장형 블록인지 여부
  final bool hasHeader;

  /// `.callout-header::after { content: "..." }` 로 자동 삽입되는 헤더 텍스트
  final String? autoHeaderText;

  const BlogBlockStyle({
    required this.className,
    required this.label,
    required this.borderColor,
    required this.backgroundColor,
    this.headerBackground,
    this.headerTextColor,
    required this.hasHeader,
    this.autoHeaderText,
  });

  bool get isReference => className == 'Reference';

  @override
  String toString() => 'BlogBlockStyle($className, header=$hasHeader)';
}

/// 블로그 스킨(minimal-mistakes skin) 색상.
class BlogSkin {
  final String name;
  final Color background;
  final Color text;
  final Color mutedText;
  final Color primary;
  final Color link;
  final Color border;
  final Color accent;

  const BlogSkin({
    required this.name,
    required this.background,
    required this.text,
    required this.mutedText,
    required this.primary,
    required this.link,
    required this.border,
    required this.accent,
  });

  /// mint 스킨 기본값 (스캔 실패 시 사용)
  static const BlogSkin mint = BlogSkin(
    name: 'mint',
    background: Color(0xFFF3F6F6),
    text: Color(0xFF40514E),
    mutedText: Color(0xFF6B7A77),
    primary: Color(0xFF11999E),
    link: Color(0xFF11999E),
    border: Color(0xFFCFD4D3),
    accent: Color(0xFF34AD7D),
  );

  BlogSkin copyWith({
    String? name,
    Color? background,
    Color? text,
    Color? mutedText,
    Color? primary,
    Color? link,
    Color? border,
    Color? accent,
  }) {
    return BlogSkin(
      name: name ?? this.name,
      background: background ?? this.background,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      primary: primary ?? this.primary,
      link: link ?? this.link,
      border: border ?? this.border,
      accent: accent ?? this.accent,
    );
  }
}

/// `_pages/categories/*.md` 에서 읽은 카테고리
class BlogCategory {
  final String slug;
  final String title;

  const BlogCategory({required this.slug, required this.title});

  @override
  String toString() => slug;
}

/// `_posts` 폴더의 템플릿 파일 (파일명에 '템플릿'/'template' 포함)
class PostTemplate {
  final String name;
  final String path;
  final String body;

  const PostTemplate({required this.name, required this.path, required this.body});
}

/// 연결된 지킬 블로그 폴더를 스캔한 결과.
class JekyllTheme {
  final String blogPath;
  final BlogSkin skin;
  final List<BlogBlockStyle> blockStyles;
  final List<BlogCategory> categories;
  final List<String> tags;
  final List<PostTemplate> templates;
  final bool hasCodeCompareBlocks;
  final String permalinkPattern;

  /// 게시된 사이트 URL (`_config.yml` 의 `url` + `baseurl`)
  final String siteUrl;

  /// 로컬이 아닐 때 `/assets/…` 를 읽을 기준 URL (raw.githubusercontent.com …)
  final String? assetBaseUrl;

  const JekyllTheme({
    required this.blogPath,
    required this.skin,
    required this.blockStyles,
    required this.categories,
    required this.tags,
    required this.templates,
    required this.hasCodeCompareBlocks,
    required this.permalinkPattern,
    this.siteUrl = '',
    this.assetBaseUrl,
  });

  BlogBlockStyle? styleFor(String className) {
    for (final s in blockStyles) {
      if (s.className == className) return s;
    }
    return null;
  }

  /// 블로그 경로가 없을 때 사용하는 기본 테마
  static JekyllTheme fallback(String blogPath) {
    return JekyllTheme(
      blogPath: blogPath,
      skin: BlogSkin.mint,
      blockStyles: const [
        BlogBlockStyle(
          className: 'callout-info-expanded',
          label: 'Info',
          borderColor: Color(0xFF48B3E4),
          backgroundColor: Color(0xFFFCFCFC),
          headerBackground: Color(0xFF48B3E4),
          headerTextColor: Color(0xFFF3F3F3),
          hasHeader: true,
        ),
        BlogBlockStyle(
          className: 'callout-warning-expanded',
          label: 'Warning',
          borderColor: Color(0xFFEE6565),
          backgroundColor: Color(0xFFFFF5F5),
          headerBackground: Color(0xFFEE6565),
          headerTextColor: Color(0xFFF7F7F7),
          hasHeader: true,
        ),
        BlogBlockStyle(
          className: 'Reference',
          label: 'Reference',
          borderColor: Color(0xFF5E6969),
          backgroundColor: Color(0xFFF8F8F8),
          headerBackground: Color(0xFF5E6969),
          headerTextColor: Color(0xFFEEEEEE),
          hasHeader: true,
          autoHeaderText: 'Reference',
        ),
      ],
      categories: const [],
      tags: const [],
      templates: const [],
      hasCodeCompareBlocks: true,
      permalinkPattern: '/:categories/:title/',
      siteUrl: '',
      assetBaseUrl: null,
    );
  }
}
