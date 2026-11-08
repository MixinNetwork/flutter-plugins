import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../core/document.dart';
import '../widgets/markdown_theme.dart';
import 'pretext_text_block.dart';

class MarkdownCodeSyntaxHighlighter {
  const MarkdownCodeSyntaxHighlighter();

  static const int _autoDetectMaxChars = 4000;
  static const int _maxSegmentCacheEntries = 128;
  static final Map<_MarkdownHighlightRequestKey,
          List<_MarkdownHighlightSegment>> _segmentCache =
      <_MarkdownHighlightRequestKey, List<_MarkdownHighlightSegment>>{};
  static final Map<_MarkdownHighlightRequestKey,
          Future<List<_MarkdownHighlightSegment>>> _pendingSegmentRequests =
      <_MarkdownHighlightRequestKey, Future<List<_MarkdownHighlightSegment>>>{};

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

  /// The highlighted presentation of [source] when its segments are cached,
  /// or null when they still have to be found.
  ///
  /// A code block that mounts again, such as a post scrolled back into view
  /// or shown in another list, then shows highlighted in its first frame
  /// instead of rebuilding the whole document a frame later.
  MarkdownCodeHighlightPresentation? cachedPresentation({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    if (source.isEmpty ||
        shouldDegradeHighlight(source: source, theme: theme)) {
      return null;
    }
    final segments = _segmentCache[_MarkdownHighlightRequestKey(
      source: source,
      language: _normalizeLanguage(language),
    )];
    if (segments == null) {
      return null;
    }
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
    return buildPlainTextPresentation(source: source, baseStyle: baseStyle)
        .span;
  }

  MarkdownCodeHighlightPresentation buildPresentation({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    return buildPlainTextPresentation(source: source, baseStyle: baseStyle);
  }

  List<MarkdownPretextInlineRun> buildPretextRuns({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    return buildPlainTextPresentation(source: source, baseStyle: baseStyle)
        .runs;
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
    final cacheKey = _MarkdownHighlightRequestKey(
      source: source,
      language: language,
    );
    final cached = _segmentCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final pending = _pendingSegmentRequests[cacheKey];
    if (pending != null) {
      return pending;
    }

    final request = compute<Map<String, Object?>, List<Map<String, Object?>>>(
      _highlightSegmentsInBackground,
      <String, Object?>{
        'source': source,
        'language': language,
      },
    ).then((response) {
      final segments = response
          .map(_MarkdownHighlightSegment.fromMessage)
          .toList(growable: false);
      if (_segmentCache.length >= _maxSegmentCacheEntries) {
        _segmentCache.remove(_segmentCache.keys.first);
      }
      _segmentCache[cacheKey] = segments;
      return segments;
    }).whenComplete(() {
      _pendingSegmentRequests.remove(cacheKey);
    });
    _pendingSegmentRequests[cacheKey] = request;
    return request;
  }

  String? _normalizeLanguage(String? language) {
    final normalized = language?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
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
        return TextStyle(
          color: theme.linkStyle.color,
          decoration: theme.linkStyle.decoration,
          decorationColor: theme.linkStyle.decorationColor,
        );
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
  final Set<String> _highlightingBlockIds = <String>{};
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
    final request = _MarkdownCodeHighlightRequest(
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      language: language,
    );
    if (_highlighter.shouldDegradeHighlight(source: source, theme: theme)) {
      _entries[blockId] = _MarkdownCodeHighlightCacheEntry(
        request: request,
        contentSignature: contentSignature,
        presentationSignature: presentationSignature,
        requestId: requestId,
        presentation: plainPresentation,
        isPending: false,
      );
      return plainPresentation;
    }

    final cachedPresentation = _highlighter.cachedPresentation(
      source: source,
      baseStyle: baseStyle,
      theme: theme,
      language: language,
    );
    if (cachedPresentation != null) {
      _entries[blockId] = _MarkdownCodeHighlightCacheEntry(
        request: request,
        contentSignature: contentSignature,
        presentationSignature: presentationSignature,
        requestId: requestId,
        presentation: cachedPresentation,
        isPending: false,
        highlightedPrefix: cachedPresentation.isHighlighted
            ? _MarkdownHighlightedPrefix(
                source: source,
                styleSignature: request.styleSignature,
                presentation: cachedPresentation,
              )
            : null,
      );
      return cachedPresentation;
    }

    // While a streamed block grows, show its last highlight with the new tail
    // in plain text instead of flashing the whole block back to plain.
    final highlightedPrefix = existing?.highlightedPrefix;
    final placeholderPresentation = existing != null &&
            existing.contentSignature == contentSignature &&
            existing.presentation.isHighlighted
        ? existing.presentation
        : highlightedPrefix?.extendTo(
              source,
              styleSignature: request.styleSignature,
              baseStyle: baseStyle,
            ) ??
            plainPresentation;
    _entries[blockId] = _MarkdownCodeHighlightCacheEntry(
      request: request,
      contentSignature: contentSignature,
      presentationSignature: presentationSignature,
      requestId: requestId,
      presentation: placeholderPresentation,
      isPending: true,
      highlightedPrefix: highlightedPrefix,
    );
    // At most one highlight runs for a block; it picks up the latest source
    // when it finishes, so a streamed block does not start one per chunk.
    if (_highlightingBlockIds.add(blockId)) {
      unawaited(_runHighlights(blockId));
    }
    return placeholderPresentation;
  }

  String cacheSignatureFor(String blockId) {
    final entry = _entries[blockId];
    if (entry == null) {
      return 'highlight:unresolved';
    }
    final state = entry.presentation.isHighlighted ? 'ready' : 'plain';
    final pending = entry.isPending ? 'pending' : 'stable';
    return 'highlight:$state:$pending:${entry.presentationSignature}:'
        '${identityHashCode(entry.presentation)}';
  }

  Future<void> _runHighlights(String blockId) async {
    try {
      while (!_isDisposed) {
        final entry = _entries[blockId];
        if (entry == null || !entry.isPending) {
          return;
        }
        final request = entry.request;
        final presentation = await _highlighter.buildPresentationAsync(
          source: request.source,
          baseStyle: request.baseStyle,
          theme: request.theme,
          language: request.language,
        );
        if (_isDisposed) {
          return;
        }
        final latest = _entries[blockId];
        if (latest == null) {
          return;
        }
        final highlightedPrefix = presentation.isHighlighted
            ? _MarkdownHighlightedPrefix(
                source: request.source,
                styleSignature: request.styleSignature,
                presentation: presentation,
              )
            : latest.highlightedPrefix;
        if (latest.requestId == entry.requestId) {
          _entries[blockId] = latest.copyWith(
            presentation: presentation,
            isPending: false,
            highlightedPrefix: highlightedPrefix,
          );
          notifyListeners();
          return;
        }
        if (!latest.isPending) {
          return;
        }
        // The source moved on while this ran: show what is highlighted so
        // far, then run the latest source.
        final placeholder = highlightedPrefix?.extendTo(
          latest.request.source,
          styleSignature: latest.request.styleSignature,
          baseStyle: latest.request.baseStyle,
        );
        _entries[blockId] = latest.copyWith(
          presentation: placeholder ?? latest.presentation,
          highlightedPrefix: highlightedPrefix,
        );
        if (placeholder != null) {
          notifyListeners();
        }
      }
    } finally {
      _highlightingBlockIds.remove(blockId);
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

class _MarkdownCodeHighlightRequest {
  const _MarkdownCodeHighlightRequest({
    required this.source,
    required this.baseStyle,
    required this.theme,
    required this.language,
  });

  final String source;
  final TextStyle baseStyle;
  final MarkdownThemeData theme;
  final String? language;

  int get styleSignature => Object.hash(language, baseStyle, theme);
}

class _MarkdownHighlightedPrefix {
  const _MarkdownHighlightedPrefix({
    required this.source,
    required this.styleSignature,
    required this.presentation,
  });

  final String source;
  final int styleSignature;
  final MarkdownCodeHighlightPresentation presentation;

  /// This highlight followed by the rest of [source] in plain text, or null
  /// when [source] does not extend it in the same style.
  MarkdownCodeHighlightPresentation? extendTo(
    String source, {
    required int styleSignature,
    required TextStyle baseStyle,
  }) {
    if (styleSignature != this.styleSignature ||
        source.length <= this.source.length ||
        !source.startsWith(this.source)) {
      return null;
    }
    final suffix = source.substring(this.source.length);
    final span = presentation.span;
    return MarkdownCodeHighlightPresentation(
      span: TextSpan(
        style: span.style,
        children: <InlineSpan>[
          ...?span.children,
          if (span.text != null) TextSpan(text: span.text),
          TextSpan(text: suffix, style: baseStyle),
        ],
      ),
      runs: <MarkdownPretextInlineRun>[
        ...presentation.runs,
        MarkdownPretextInlineRun(text: suffix, style: baseStyle),
      ],
      isHighlighted: false,
    );
  }
}

class _MarkdownCodeHighlightCacheEntry {
  const _MarkdownCodeHighlightCacheEntry({
    required this.request,
    required this.contentSignature,
    required this.presentationSignature,
    required this.requestId,
    required this.presentation,
    required this.isPending,
    this.highlightedPrefix,
  });

  final _MarkdownCodeHighlightRequest request;
  final int contentSignature;
  final int presentationSignature;
  final int requestId;
  final MarkdownCodeHighlightPresentation presentation;
  final bool isPending;

  /// The latest real highlight of this block, kept to fill placeholders.
  final _MarkdownHighlightedPrefix? highlightedPrefix;

  _MarkdownCodeHighlightCacheEntry copyWith({
    required MarkdownCodeHighlightPresentation presentation,
    bool? isPending,
    _MarkdownHighlightedPrefix? highlightedPrefix,
  }) {
    return _MarkdownCodeHighlightCacheEntry(
      request: request,
      contentSignature: contentSignature,
      presentationSignature: presentationSignature,
      requestId: requestId,
      presentation: presentation,
      isPending: isPending ?? this.isPending,
      highlightedPrefix: highlightedPrefix ?? this.highlightedPrefix,
    );
  }
}

@immutable
class _MarkdownHighlightRequestKey {
  const _MarkdownHighlightRequestKey({
    required this.source,
    required this.language,
  });

  final String source;
  final String? language;

  @override
  bool operator ==(Object other) {
    return other is _MarkdownHighlightRequestKey &&
        other.source == source &&
        other.language == language;
  }

  @override
  int get hashCode => Object.hash(source, language);
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

// One highlighter for each isolate: registering every language takes a while,
// and an app's background isolates highlight many code blocks.
final _isolateHighlighter = Highlight()..registerLanguages(builtinAllLanguages);

/// Finds the highlight segments of the code blocks of [document] on the
/// calling isolate. See [cacheCodeHighlights].
List<Map<String, Object?>> highlightCodeBlocks(
  MarkdownDocument document, {
  required int maxLines,
}) {
  const highlighter = MarkdownCodeSyntaxHighlighter();
  final highlights = <Map<String, Object?>>[];
  late final void Function(List<BlockNode>) visitAll;
  void visit(BlockNode block) {
    switch (block) {
      case CodeBlock(:final code, :final language):
        if (code.isEmpty || highlighter.lineCountOf(code) > maxLines) return;
        final normalized = highlighter._normalizeLanguage(language);
        highlights.add(<String, Object?>{
          'source': code,
          'language': normalized,
          'segments': _highlightSegmentsInBackground(<String, Object?>{
            'source': code,
            'language': normalized,
          }),
        });
      case QuoteBlock(:final children) || DetailsBlock(:final children):
        visitAll(children);
      case ListBlock(:final items) || FootnoteListBlock(:final items):
        for (final item in items) {
          visitAll(item.children);
        }
      case DefinitionListBlock(:final items):
        for (final item in items) {
          item.definitions.forEach(visitAll);
        }
      default:
    }
  }

  visitAll = (blocks) => blocks.forEach(visit);
  visitAll(document.blocks);
  return highlights;
}

/// Stores highlights from [highlightCodeBlocks] for the code blocks that show
/// later on this isolate.
void cacheCodeHighlights(List<Map<String, Object?>> highlights) {
  final cache = MarkdownCodeSyntaxHighlighter._segmentCache;
  for (final highlight in highlights) {
    if (cache.length >= MarkdownCodeSyntaxHighlighter._maxSegmentCacheEntries) {
      cache.remove(cache.keys.first);
    }
    cache[_MarkdownHighlightRequestKey(
      source: highlight['source']! as String,
      language: highlight['language'] as String?,
    )] = (highlight['segments']! as List<Object?>)
        .map((segment) => _MarkdownHighlightSegment.fromMessage(
              segment! as Map<String, Object?>,
            ))
        .toList(growable: false);
  }
}

List<Map<String, Object?>> _highlightSegmentsInBackground(
  Map<String, Object?> request,
) {
  final highlighter = _isolateHighlighter;
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
