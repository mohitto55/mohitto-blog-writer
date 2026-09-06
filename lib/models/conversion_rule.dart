/// Represents a conversion rule for transforming Obsidian syntax to GitHub blog syntax
class ConversionRule {
  final String name;
  final RegExp pattern;
  final String Function(Match match) replacement;
  final int priority;

  ConversionRule({
    required this.name,
    required this.pattern,
    required this.replacement,
    this.priority = 0,
  });

  /// Applies this conversion rule to the given text
  String apply(String text) {
    return text.replaceAllMapped(pattern, replacement);
  }
}

/// Predefined conversion rules for common Obsidian syntax
class DefaultConversionRules {
  /// Converts WikiLinks [[Page Name]] to markdown links [Page Name](page-name.md)
  static final ConversionRule wikiLink = ConversionRule(
    name: 'WikiLink',
    pattern: RegExp(r'\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]'),
    replacement: (match) {
      final target = match.group(1)!;
      final display = match.group(2) ?? target;
      final slug = target.toLowerCase().replaceAll(' ', '-');
      return '[$display]($slug.md)';
    },
    priority: 1,
  );

  /// Converts Obsidian image embeds ![[image.png]] to markdown images
  static final ConversionRule imageEmbed = ConversionRule(
    name: 'ImageEmbed',
    pattern: RegExp(r'!\[\[([^\]]+?)\]\]'),
    replacement: (match) {
      final imageName = match.group(1)!;
      // Image path will be replaced later with actual uploaded path
      return '![](/assets/images/$imageName)';
    },
    priority: 2,
  );

  /// Converts Obsidian callouts to HTML divs
  static final ConversionRule callout = ConversionRule(
    name: 'Callout',
    pattern: RegExp(r'>\s*\[!(\w+)\]\s*(.+?)(?=\n(?!>)|$)', dotAll: true),
    replacement: (match) {
      final type = match.group(1)!.toLowerCase();
      final content = match.group(2)!;
      return '<div class="callout callout-$type">\n$content\n</div>';
    },
    priority: 3,
  );

  /// Converts Obsidian highlights ==text== to HTML mark tags
  static final ConversionRule highlight = ConversionRule(
    name: 'Highlight',
    pattern: RegExp(r'==([^=]+)=='),
    replacement: (match) {
      final text = match.group(1)!;
      return '<mark>$text</mark>';
    },
    priority: 0,
  );

  /// Returns all default conversion rules
  static List<ConversionRule> all() {
    return [
      wikiLink,
      imageEmbed,
      callout,
      highlight,
    ]..sort((a, b) => b.priority.compareTo(a.priority));
  }
}
