import 'package:flutter/material.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'pretext_text_block.dart';
import '../widgets/markdown_theme.dart';

class MarkdownCodeSyntaxHighlighter {
  const MarkdownCodeSyntaxHighlighter();

  static final Highlight _highlight = Highlight()
    ..registerLanguages(builtinAllLanguages);

  TextSpan buildTextSpan({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    if (source.isEmpty) {
      return TextSpan(style: baseStyle, text: '');
    }

    String? targetLanguage = language?.trim().toLowerCase();
    if (targetLanguage != null && targetLanguage.isEmpty) {
      targetLanguage = null;
    }

    HighlightResult result;
    try {
      if (targetLanguage != null &&
          _highlight.getLanguage(targetLanguage) != null) {
        result = _highlight.highlight(code: source, language: targetLanguage);
      } else {
        if (source.length <= 4000) {
          result = _highlight.highlightAuto(source);
        } else {
          result = _highlight.justTextHighlightResult(source);
        }
      }
    } catch (_) {
      result = _highlight.justTextHighlightResult(source);
    }

    final renderer = _MarkdownHighlightRenderer(
        baseStyle: baseStyle, theme: theme, highlighter: this);
    result.render(renderer);
    return renderer.span ?? TextSpan(style: baseStyle, text: source);
  }

  List<MarkdownPretextInlineRun> buildPretextRuns({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    final span = buildTextSpan(
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      language: language,
    );
    final runs = <MarkdownPretextInlineRun>[];
    _collectPretextRuns(
      span,
      inheritedStyle: baseStyle,
      runs: runs,
    );
    return runs.isEmpty
        ? <MarkdownPretextInlineRun>[
            MarkdownPretextInlineRun(text: source, style: baseStyle),
          ]
        : runs;
  }

  void _collectPretextRuns(
    InlineSpan span, {
    required TextStyle inheritedStyle,
    required List<MarkdownPretextInlineRun> runs,
  }) {
    if (span is! TextSpan) {
      return;
    }

    final effectiveStyle = inheritedStyle.merge(span.style);
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      if (runs.isNotEmpty &&
          runs.last.renderSpan == null &&
          runs.last.decoration == null &&
          runs.last.mouseCursor == null &&
          runs.last.recognizer == null &&
          runs.last.style == effectiveStyle) {
        final last = runs.removeLast();
        runs.add(last.copyWithText(last.text + text));
      } else {
        runs.add(MarkdownPretextInlineRun(text: text, style: effectiveStyle));
      }
    }

    final children = span.children;
    if (children == null) {
      return;
    }
    for (final child in children) {
      _collectPretextRuns(
        child,
        inheritedStyle: effectiveStyle,
        runs: runs,
      );
    }
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
      foreground.withValues(alpha: 0.55),
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
        return TextStyle(color: foreground.withValues(alpha: 0.78));
      default:
        return const TextStyle();
    }
  }
}

class _RendererNode {
  final String? scope;
  final TextStyle style;
  final List<InlineSpan> children = [];

  _RendererNode({this.scope, required this.style});
}

class _MarkdownHighlightRenderer implements HighlightRenderer {
  final TextStyle baseStyle;
  final MarkdownThemeData theme;
  final MarkdownCodeSyntaxHighlighter highlighter;

  final List<_RendererNode> _stack = [];
  final List<InlineSpan> _results = [];

  _MarkdownHighlightRenderer({
    required this.baseStyle,
    required this.theme,
    required this.highlighter,
  });

  @override
  void addText(String text) {
    if (_stack.isEmpty) {
      _results.add(TextSpan(text: text, style: baseStyle));
    } else {
      final top = _stack.last;
      top.children.add(TextSpan(text: text, style: top.style));
    }
  }

  @override
  void openNode(DataNode node) {
    final parentStyle = _stack.isEmpty ? baseStyle : _stack.last.style;
    final style =
        highlighter._styleFor(node.scope, baseStyle: parentStyle, theme: theme);
    _stack.add(_RendererNode(scope: node.scope, style: style));
  }

  @override
  void closeNode(DataNode node) {
    final top = _stack.removeLast();
    final span = TextSpan(
        style: top.style, children: top.children.isEmpty ? null : top.children);
    if (_stack.isEmpty) {
      _results.add(span);
    } else {
      _stack.last.children.add(span);
    }
  }

  TextSpan? get span {
    if (_results.isEmpty) return null;
    return TextSpan(style: baseStyle, children: _results);
  }
}
