import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' as highlight;

import '../widgets/markdown_theme.dart';

class MarkdownCodeSyntaxHighlighter {
  const MarkdownCodeSyntaxHighlighter();

  static const Map<String, String> _languageAliases = <String, String>{
    'c++': 'cpp',
    'c#': 'cs',
    'js': 'javascript',
    'jsx': 'javascript',
    'kt': 'kotlin',
    'objc': 'objectivec',
    'py': 'python',
    'rb': 'ruby',
    'rs': 'rust',
    'sh': 'bash',
    'shell': 'bash',
    'ts': 'typescript',
    'tsx': 'typescript',
    'yml': 'yaml',
  };

  TextSpan buildTextSpan({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    if (source.isEmpty) {
      return TextSpan(style: baseStyle, text: '');
    }

    final result = _parse(source, language: language);
    final nodes = result?.nodes;
    if (nodes == null || nodes.isEmpty) {
      return TextSpan(style: baseStyle, text: source);
    }

    return TextSpan(
      style: baseStyle,
      children: <InlineSpan>[
        for (final node in nodes)
          ..._buildNodeSpans(
            node,
            baseStyle: baseStyle,
            theme: theme,
          ),
      ],
    );
  }

  highlight.Result? _parse(String source, {String? language}) {
    final normalizedLanguage = _normalizeLanguage(language);
    try {
      if (normalizedLanguage != null && normalizedLanguage.isNotEmpty) {
        return highlight.highlight.parse(
          source,
          language: normalizedLanguage,
        );
      }
      if (source.length <= 4000) {
        return highlight.highlight.parse(source, autoDetection: true);
      }
    } catch (_) {
      try {
        if (source.length <= 4000) {
          return highlight.highlight.parse(source, autoDetection: true);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String? _normalizeLanguage(String? language) {
    final trimmed = language?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return _languageAliases[trimmed] ?? trimmed;
  }

  List<InlineSpan> _buildNodeSpans(
    highlight.Node node, {
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
  }) {
    final style = _styleFor(node.className, baseStyle: baseStyle, theme: theme);
    if (node.value != null) {
      return <InlineSpan>[TextSpan(text: node.value, style: style)];
    }
    final children = node.children;
    if (children == null || children.isEmpty) {
      return const <InlineSpan>[];
    }
    return <InlineSpan>[
      for (final child in children)
        ..._buildNodeSpans(
          child,
          baseStyle: style,
          theme: theme,
        ),
    ];
  }

  TextStyle _styleFor(
    String? className, {
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
  }) {
    if (className == null || className.isEmpty) {
      return baseStyle;
    }
    final classes = className.split(RegExp(r'\s+'));
    var style = baseStyle;
    for (final token in classes) {
      style =
          style.merge(_tokenStyle(token, baseStyle: baseStyle, theme: theme));
    }
    return style;
  }

  TextStyle _tokenStyle(
    String token, {
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
  }) {
    final foreground = baseStyle.color ?? const Color(0xFF1D1D1F);
    final accent = theme.linkStyle.color ?? const Color(0xFF0F6CBD);
    final stringColor = Color.lerp(accent, const Color(0xFF1F7A52), 0.6)!;
    final numericColor = Color.lerp(accent, const Color(0xFFB2581C), 0.5)!;
    final metaColor = Color.lerp(accent, const Color(0xFF006B6B), 0.45)!;
    final titleColor = Color.lerp(accent, const Color(0xFF8B5A00), 0.3)!;
    final mutedColor = Color.alphaBlend(
      foreground.withOpacity(0.55),
      theme.codeBlockBackgroundColor,
    );

    switch (token) {
      case 'comment':
      case 'quote':
      case 'doctag':
        return TextStyle(color: mutedColor, fontStyle: FontStyle.italic);
      case 'keyword':
      case 'selector-tag':
      case 'literal':
      case 'operator':
        return TextStyle(color: accent, fontWeight: FontWeight.w700);
      case 'string':
      case 'regexp':
      case 'subst':
        return TextStyle(color: stringColor);
      case 'number':
      case 'symbol':
      case 'bullet':
        return TextStyle(color: numericColor);
      case 'type':
      case 'built_in':
      case 'built_in-name':
      case 'attr':
      case 'attribute':
      case 'variable':
      case 'template-variable':
        return TextStyle(color: metaColor);
      case 'title':
      case 'title.function_':
      case 'title.class_':
      case 'function':
      case 'section':
        return TextStyle(color: titleColor, fontWeight: FontWeight.w700);
      case 'meta':
      case 'meta-keyword':
        return TextStyle(color: metaColor, fontWeight: FontWeight.w600);
      case 'emphasis':
        return const TextStyle(fontStyle: FontStyle.italic);
      case 'strong':
        return const TextStyle(fontWeight: FontWeight.w700);
      case 'link':
        return theme.linkStyle;
      case 'punctuation':
        return TextStyle(color: foreground.withOpacity(0.78));
      default:
        return const TextStyle();
    }
  }
}
