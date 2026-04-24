import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'pretext_text_block.dart';
import '../widgets/markdown_theme.dart';

class MarkdownCodeSyntaxHighlighter {
  const MarkdownCodeSyntaxHighlighter();

  static const int _autoDetectMaxChars = 4000;
  static const int _backgroundIsolateMinLines = 80;
  static const int _backgroundIsolateMinChars = 6000;

  static final Highlight _highlight = Highlight()
    ..registerLanguages(builtinAllLanguages);

  MarkdownCodeHighlightPresentation buildPlainTextPresentation({
    required String source,
    required TextStyle baseStyle,
  }) {
    final span = TextSpan(style: baseStyle, text: source);
    return MarkdownCodeHighlightPresentation(
      span: span,
      runs: <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(text: source, style: baseStyle),
      ],
      isHighlighted: false,
    );
  }

  bool shouldDegradeHighlight({
    required String source,
    required MarkdownThemeData theme,
  }) {
    final maxLines = theme.codeHighlightMaxLines;
    if (maxLines == null || maxLines <= 0) {
      return false;
    }
    return lineCountOf(source) > maxLines;
  }

  Future<MarkdownCodeHighlightPresentation> buildPresentationAsync({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) async {
    if (source.isEmpty ||
        shouldDegradeHighlight(source: source, theme: theme)) {
      return buildPlainTextPresentation(source: source, baseStyle: baseStyle);
    }

    final normalizedLanguage = _normalizeLanguage(language);
    final segments = await _highlightSegmentsAsync(
      source: source,
      language: normalizedLanguage,
    );
    return _presentationFromSegments(
      segments,
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      isHighlighted: segments.isNotEmpty,
    );
  }

  TextSpan buildTextSpan({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    return buildPresentation(
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      language: language,
    ).span;
  }

  MarkdownCodeHighlightPresentation buildPresentation({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    if (source.isEmpty ||
        shouldDegradeHighlight(source: source, theme: theme)) {
      return buildPlainTextPresentation(source: source, baseStyle: baseStyle);
    }
    final segments = _highlightSegmentsSync(
      source: source,
      language: _normalizeLanguage(language),
    );
    return _presentationFromSegments(
      segments,
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      isHighlighted: segments.isNotEmpty,
    );
  }

  List<MarkdownPretextInlineRun> buildPretextRuns({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    return buildPresentation(
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      language: language,
    ).runs;
  }

  int lineCountOf(String source) {
    if (source.isEmpty) {
      return 0;
    }
    return '\n'.allMatches(source).length + 1;
  }

  Future<List<_MarkdownHighlightSegment>> _highlightSegmentsAsync({
    required String source,
    required String? language,
  }) async {
    if (_shouldUseBackgroundIsolate(source: source, language: language)) {
      final response =
          await compute<Map<String, Object?>, List<Map<String, Object?>>>(
        _highlightSegmentsInBackground,
        <String, Object?>{
          'source': source,
          'language': language,
        },
      );
      return response
          .map(_MarkdownHighlightSegment.fromMessage)
          .toList(growable: false);
    }
    return Future<List<_MarkdownHighlightSegment>>.value(
      _highlightSegmentsSync(source: source, language: language),
    );
  }

  bool _shouldUseBackgroundIsolate({
    required String source,
    required String? language,
  }) {
    if (kIsWeb) {
      return false;
    }
    if (source.length < _backgroundIsolateMinChars &&
        lineCountOf(source) < _backgroundIsolateMinLines) {
      return false;
    }
    return language != null || source.length <= _autoDetectMaxChars;
  }

  List<_MarkdownHighlightSegment> _highlightSegmentsSync({
    required String source,
    required String? language,
  }) {
    if (source.isEmpty) {
      return const <_MarkdownHighlightSegment>[];
    }
    final result = _runHighlight(
      _highlight,
      source: source,
      language: language,
    );
    final renderer = _MarkdownHighlightSegmentRenderer();
    result.render(renderer);
    return renderer.segments;
  }

  String? _normalizeLanguage(String? language) {
    final normalized = language?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  HighlightResult _runHighlight(
    Highlight highlighter, {
    required String source,
    required String? language,
  }) {
    try {
      if (language != null && highlighter.getLanguage(language) != null) {
        return highlighter.highlight(code: source, language: language);
      }
      if (source.length <= _autoDetectMaxChars) {
        return highlighter.highlightAuto(source);
      }
    } catch (_) {
      return highlighter.justTextHighlightResult(source);
    }
    return highlighter.justTextHighlightResult(source);
  }

  MarkdownCodeHighlightPresentation _presentationFromSegments(
    List<_MarkdownHighlightSegment> segments, {
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    required bool isHighlighted,
  }) {
    if (segments.isEmpty) {
      return buildPlainTextPresentation(source: source, baseStyle: baseStyle);
    }

    final runs = <MarkdownPretextInlineRun>[];
    final children = <InlineSpan>[];

    for (final segment in segments) {
      if (segment.text.isEmpty) {
        continue;
      }
      var effectiveStyle = baseStyle;
      for (final scope in segment.scopes) {
        effectiveStyle = effectiveStyle
            .merge(_styleFor(scope, baseStyle: effectiveStyle, theme: theme));
      }
      if (runs.isNotEmpty && runs.last.style == effectiveStyle) {
        final last = runs.removeLast();
        runs.add(last.copyWithText(last.text + segment.text));
      } else {
        runs.add(MarkdownPretextInlineRun(
            text: segment.text, style: effectiveStyle));
      }

      if (children.isNotEmpty) {
        final last = children.last;
        if (last is TextSpan &&
            last.style == effectiveStyle &&
            last.children == null) {
          children[children.length - 1] = TextSpan(
            text: (last.text ?? '') + segment.text,
            style: effectiveStyle,
          );
          continue;
        }
      }
      children.add(TextSpan(text: segment.text, style: effectiveStyle));
    }

    if (runs.isEmpty || children.isEmpty) {
      return buildPlainTextPresentation(source: source, baseStyle: baseStyle);
    }

    return MarkdownCodeHighlightPresentation(
      span: TextSpan(style: baseStyle, children: children),
      runs: runs,
      isHighlighted: isHighlighted,
    );
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

class MarkdownCodeHighlightPresentation {
  const MarkdownCodeHighlightPresentation({
    required this.span,
    required this.runs,
    required this.isHighlighted,
  });

  final TextSpan span;
  final List<MarkdownPretextInlineRun> runs;
  final bool isHighlighted;
}

class MarkdownCodeHighlightCache extends ChangeNotifier {
  MarkdownCodeHighlightCache({
    required MarkdownCodeSyntaxHighlighter highlighter,
  }) : _highlighter = highlighter;

  final MarkdownCodeSyntaxHighlighter _highlighter;
  final Map<String, _MarkdownCodeHighlightCacheEntry> _entries =
      <String, _MarkdownCodeHighlightCacheEntry>{};
  int _nextRequestId = 0;
  bool _isDisposed = false;

  MarkdownCodeHighlightPresentation resolve({
    required String blockId,
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    final contentSignature = Object.hash(source, language);
    final presentationSignature =
        Object.hash(contentSignature, baseStyle, theme);
    final existing = _entries[blockId];
    if (existing != null &&
        existing.presentationSignature == presentationSignature) {
      return existing.presentation;
    }

    final plainPresentation = _highlighter.buildPlainTextPresentation(
      source: source,
      baseStyle: baseStyle,
    );
    if (_isDisposed) {
      return plainPresentation;
    }

    final requestId = ++_nextRequestId;
    if (_highlighter.shouldDegradeHighlight(source: source, theme: theme)) {
      _entries[blockId] = _MarkdownCodeHighlightCacheEntry(
        contentSignature: contentSignature,
        presentationSignature: presentationSignature,
        requestId: requestId,
        presentation: plainPresentation,
        isPending: false,
      );
      return plainPresentation;
    }

    final placeholderPresentation = existing != null &&
            existing.contentSignature == contentSignature &&
            existing.presentation.isHighlighted
        ? existing.presentation
        : plainPresentation;
    _entries[blockId] = _MarkdownCodeHighlightCacheEntry(
      contentSignature: contentSignature,
      presentationSignature: presentationSignature,
      requestId: requestId,
      presentation: placeholderPresentation,
      isPending: true,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) {
        return;
      }
      unawaited(
        _startHighlight(
          blockId: blockId,
          requestId: requestId,
          contentSignature: contentSignature,
          presentationSignature: presentationSignature,
          source: source,
          baseStyle: baseStyle,
          theme: theme,
          language: language,
        ),
      );
    });
    return placeholderPresentation;
  }

  String cacheSignatureFor(String blockId) {
    final entry = _entries[blockId];
    if (entry == null) {
      return 'highlight:unresolved';
    }
    final state = entry.presentation.isHighlighted ? 'ready' : 'plain';
    final pending = entry.isPending ? 'pending' : 'stable';
    return 'highlight:$state:$pending:${entry.presentationSignature}';
  }

  Future<void> _startHighlight({
    required String blockId,
    required int requestId,
    required int contentSignature,
    required int presentationSignature,
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    required String? language,
  }) async {
    if (_isDisposed) {
      return;
    }
    final current = _entries[blockId];
    if (current == null ||
        current.requestId != requestId ||
        current.presentationSignature != presentationSignature ||
        !current.isPending) {
      return;
    }

    final presentation = await _highlighter.buildPresentationAsync(
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      language: language,
    );
    if (_isDisposed) {
      return;
    }
    final latest = _entries[blockId];
    if (latest == null ||
        latest.requestId != requestId ||
        latest.presentationSignature != presentationSignature) {
      return;
    }

    _entries[blockId] = _MarkdownCodeHighlightCacheEntry(
      contentSignature: contentSignature,
      presentationSignature: presentationSignature,
      requestId: requestId,
      presentation: presentation,
      isPending: false,
    );
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void clear() {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
  }

  void cleanup(Set<String> validIds) {
    _entries.removeWhere((key, _) => !validIds.contains(key));
  }

  @override
  void dispose() {
    _isDisposed = true;
    _entries.clear();
    super.dispose();
  }
}

class _MarkdownCodeHighlightCacheEntry {
  const _MarkdownCodeHighlightCacheEntry({
    required this.contentSignature,
    required this.presentationSignature,
    required this.requestId,
    required this.presentation,
    required this.isPending,
  });

  final int contentSignature;
  final int presentationSignature;
  final int requestId;
  final MarkdownCodeHighlightPresentation presentation;
  final bool isPending;
}

@immutable
class _MarkdownHighlightSegment {
  const _MarkdownHighlightSegment({
    required this.text,
    required this.scopes,
  });

  factory _MarkdownHighlightSegment.fromMessage(Map<String, Object?> message) {
    final scopes = (message['scopes'] as List<Object?>)
        .map((scope) => scope! as String)
        .toList(growable: false);
    return _MarkdownHighlightSegment(
      text: message['text']! as String,
      scopes: scopes,
    );
  }

  final String text;
  final List<String> scopes;

  Map<String, Object?> toMessage() => <String, Object?>{
        'text': text,
        'scopes': scopes,
      };
}

class _MarkdownHighlightSegmentRenderer implements HighlightRenderer {
  final List<String> _scopeStack = <String>[];
  final List<_MarkdownHighlightSegment> _segments =
      <_MarkdownHighlightSegment>[];

  List<_MarkdownHighlightSegment> get segments =>
      List<_MarkdownHighlightSegment>.unmodifiable(_segments);

  @override
  void addText(String text) {
    if (text.isEmpty) {
      return;
    }
    if (_segments.isNotEmpty &&
        listEquals(_segments.last.scopes, _scopeStack)) {
      final previous = _segments.removeLast();
      _segments.add(
        _MarkdownHighlightSegment(
          text: previous.text + text,
          scopes: previous.scopes,
        ),
      );
      return;
    }
    _segments.add(
      _MarkdownHighlightSegment(
        text: text,
        scopes: List<String>.unmodifiable(_scopeStack),
      ),
    );
  }

  @override
  void openNode(DataNode node) {
    final scope = node.scope;
    if (scope != null && scope.isNotEmpty) {
      _scopeStack.add(scope);
    }
  }

  @override
  void closeNode(DataNode node) {
    final scope = node.scope;
    if (scope != null && scope.isNotEmpty && _scopeStack.isNotEmpty) {
      _scopeStack.removeLast();
    }
  }
}

List<Map<String, Object?>> _highlightSegmentsInBackground(
  Map<String, Object?> request,
) {
  final highlighter = Highlight()..registerLanguages(builtinAllLanguages);
  final source = request['source']! as String;
  final language = request['language'] as String?;
  final result = _runHighlightInBackground(
    highlighter,
    source: source,
    language: language,
  );
  final renderer = _MarkdownHighlightSegmentRenderer();
  result.render(renderer);
  return renderer.segments
      .map((segment) => segment.toMessage())
      .toList(growable: false);
}

HighlightResult _runHighlightInBackground(
  Highlight highlighter, {
  required String source,
  required String? language,
}) {
  try {
    if (language != null && highlighter.getLanguage(language) != null) {
      return highlighter.highlight(code: source, language: language);
    }
    if (source.length <= MarkdownCodeSyntaxHighlighter._autoDetectMaxChars) {
      return highlighter.highlightAuto(source);
    }
  } catch (_) {
    return highlighter.justTextHighlightResult(source);
  }
  return highlighter.justTextHighlightResult(source);
}
