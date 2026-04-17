// ignore_for_file: implementation_imports

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pretext/pretext.dart';
import 'package:pretext/src/segment.dart' as pretext_segment;

import '../core/document.dart';

@immutable
class MarkdownPretextInlineRun {
  const MarkdownPretextInlineRun({
    required this.text,
    required this.style,
    this.mouseCursor,
    this.recognizer,
    this.decoration,
    this.allowCharacterWrap = false,
    this.renderSpan,
    this.estimatedWidth,
    this.estimatedLineHeight,
  })  : assert(renderSpan == null || decoration == null),
        assert(renderSpan == null || allowCharacterWrap == false);

  final String text;
  final TextStyle style;
  final MouseCursor? mouseCursor;
  final GestureRecognizer? recognizer;
  final MarkdownPretextInlineDecoration? decoration;
  final bool allowCharacterWrap;
  final InlineSpan? renderSpan;
  final double? estimatedWidth;
  final double? estimatedLineHeight;

  MarkdownPretextInlineRun copyWithText(String text) {
    final preserveRenderSpan = renderSpan != null && text == this.text;
    return MarkdownPretextInlineRun(
      text: text,
      style: style,
      mouseCursor: mouseCursor,
      recognizer: recognizer,
      decoration: decoration,
      allowCharacterWrap: allowCharacterWrap,
      renderSpan: preserveRenderSpan ? renderSpan : null,
      estimatedWidth: preserveRenderSpan ? estimatedWidth : null,
      estimatedLineHeight: estimatedLineHeight,
    );
  }
}

@immutable
class MarkdownPretextInlineDecoration {
  const MarkdownPretextInlineDecoration({
    required this.backgroundColor,
    required this.borderRadius,
    required this.padding,
  });

  final Color backgroundColor;
  final BorderRadius borderRadius;
  final EdgeInsets padding;

  MarkdownPretextInlineDecoration copyWith({
    Color? backgroundColor,
    BorderRadius? borderRadius,
    EdgeInsets? padding,
  }) {
    return MarkdownPretextInlineDecoration(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderRadius: borderRadius ?? this.borderRadius,
      padding: padding ?? this.padding,
    );
  }
}

class MarkdownPretextTextBlock extends StatelessWidget {
  const MarkdownPretextTextBlock({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
    this.intrinsicWidthSafe = false,
    this.directTextKey,
    this.preferDirectRichText = false,
  })  : runs = null,
        fallbackStyle = style;

  const MarkdownPretextTextBlock.rich({
    super.key,
    required this.runs,
    required this.fallbackStyle,
    this.textAlign = TextAlign.start,
    this.intrinsicWidthSafe = false,
    this.directTextKey,
    this.preferDirectRichText = false,
  })  : text = '',
        style = fallbackStyle;

  final String text;
  final TextStyle style;
  final List<MarkdownPretextInlineRun>? runs;
  final TextStyle fallbackStyle;
  final TextAlign textAlign;
  final bool intrinsicWidthSafe;
  final GlobalKey? directTextKey;
  final bool preferDirectRichText;

  @override
  Widget build(BuildContext context) {
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final textDirection = Directionality.of(context);
    final effectiveRuns = runs ??
        <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(text: text, style: style),
        ];
    if (intrinsicWidthSafe ||
        preferDirectRichText ||
        _requiresDirectTextRichRendering(effectiveRuns)) {
      return Text.rich(
        buildMarkdownPretextSpan(
          runs: effectiveRuns,
          fallbackStyle: fallbackStyle,
        ),
        key: directTextKey,
        style: fallbackStyle,
        textAlign: textAlign,
        textScaler: textScaler,
        textDirection: textDirection,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedLayout = _computeLayout(
          maxWidth: constraints.maxWidth,
          textScaleFactor: textScaler.scale(1.0),
          textDirection: textDirection,
        );
        if (constrainedLayout.lines.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final line in constrainedLayout.lines)
              SizedBox(
                width: double.infinity,
                height: line.height,
                child: Padding(
                  padding: EdgeInsets.only(left: line.leadingOffset),
                  child: Text.rich(
                    line.span,
                    style: fallbackStyle,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textScaler: textScaler,
                    textAlign: textAlign,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  MarkdownPretextLayoutResult _computeLayout({
    required double maxWidth,
    required double textScaleFactor,
    required TextDirection textDirection,
  }) {
    final runs = this.runs;
    if (runs != null) {
      return computeMarkdownPretextLayoutFromRuns(
        runs: runs,
        fallbackStyle: fallbackStyle,
        maxWidth: maxWidth,
        textScaleFactor: textScaleFactor,
        textAlign: textAlign,
        textDirection: textDirection,
      );
    }

    return computeMarkdownPretextLayout(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      textAlign: textAlign,
      textDirection: textDirection,
    );
  }
}

bool _requiresDirectTextRichRendering(List<MarkdownPretextInlineRun> runs) {
  return runs.any((run) => run.renderSpan != null);
}

bool markdownPretextCanUseDirectRichTextGeometry(
  List<MarkdownPretextInlineRun> runs,
) {
  return runs.every((run) => run.decoration == null) ||
      runs.any((run) => run.renderSpan != null);
}

InlineSpan buildMarkdownPretextSpan({
  required List<MarkdownPretextInlineRun> runs,
  required TextStyle fallbackStyle,
}) {
  return _buildFullSpan(runs: runs, fallbackStyle: fallbackStyle);
}

String markdownPretextRenderText(List<MarkdownPretextInlineRun> runs) {
  final buffer = StringBuffer();
  for (final run in runs) {
    if (run.renderSpan != null) {
      buffer.writeCharCode(0xFFFC);
      continue;
    }
    if (run.decoration != null) {
      if (!run.allowCharacterWrap) {
        buffer.writeCharCode(0xFFFC);
        continue;
      }
      for (var index = 0; index < run.text.length; index++) {
        final character = run.text[index];
        if (character == '\n') {
          buffer.write(character);
        } else {
          buffer.writeCharCode(0xFFFC);
        }
      }
      continue;
    }
    buffer.write(run.text);
  }
  return buffer.toString();
}

int _markdownPretextRenderLengthForRun(MarkdownPretextInlineRun run) {
  if (run.renderSpan != null) {
    return 1;
  }
  if (run.decoration != null && !run.allowCharacterWrap) {
    return 1;
  }
  return run.text.length;
}

int markdownPretextRenderOffsetForPlainOffset(
  List<MarkdownPretextInlineRun> runs,
  int plainOffset, {
  required bool preferEnd,
}) {
  final clampedPlainOffset = math.max(plainOffset, 0);
  var plainCursor = 0;
  var renderCursor = 0;

  for (final run in runs) {
    final plainStart = plainCursor;
    final plainEnd = plainStart + run.text.length;
    final renderLength = _markdownPretextRenderLengthForRun(run);
    final renderStart = renderCursor;
    final renderEnd = renderStart + renderLength;

    if (clampedPlainOffset <= plainStart) {
      return renderStart;
    }
    if (clampedPlainOffset < plainEnd) {
      if (run.renderSpan != null ||
          (run.decoration != null && renderLength == 1)) {
        return preferEnd ? renderEnd : renderStart;
      }
      return renderStart + (clampedPlainOffset - plainStart);
    }
    if (clampedPlainOffset == plainEnd) {
      return renderEnd;
    }

    plainCursor = plainEnd;
    renderCursor = renderEnd;
  }

  return renderCursor;
}

int markdownPretextPlainOffsetForRenderOffset(
  List<MarkdownPretextInlineRun> runs,
  int renderOffset,
) {
  final clampedRenderOffset = math.max(renderOffset, 0);
  var plainCursor = 0;
  var renderCursor = 0;

  for (final run in runs) {
    final plainStart = plainCursor;
    final plainEnd = plainStart + run.text.length;
    final renderLength = _markdownPretextRenderLengthForRun(run);
    final renderStart = renderCursor;
    final renderEnd = renderStart + renderLength;

    if (clampedRenderOffset <= renderStart) {
      return plainStart;
    }
    if (clampedRenderOffset < renderEnd) {
      if (run.renderSpan != null ||
          (run.decoration != null && renderLength == 1)) {
        return plainStart;
      }
      return plainStart + (clampedRenderOffset - renderStart);
    }
    if (clampedRenderOffset == renderEnd) {
      return plainEnd;
    }

    plainCursor = plainEnd;
    renderCursor = renderEnd;
  }

  return plainCursor;
}

MarkdownPretextLayoutResult computeMarkdownPretextLayout({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double textScaleFactor,
  TextAlign textAlign = TextAlign.start,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return computeMarkdownPretextLayoutFromRuns(
    runs: <MarkdownPretextInlineRun>[
      MarkdownPretextInlineRun(text: text, style: style),
    ],
    fallbackStyle: style,
    maxWidth: maxWidth,
    textScaleFactor: textScaleFactor,
    textAlign: textAlign,
    textDirection: textDirection,
  );
}

MarkdownPretextLayoutResult computeMarkdownPretextLayoutFromRuns({
  required List<MarkdownPretextInlineRun> runs,
  required TextStyle fallbackStyle,
  required double maxWidth,
  required double textScaleFactor,
  TextAlign textAlign = TextAlign.start,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final plainText = runs.map((run) => run.text).join();
  final lineHeight = _measureMaxLineHeight(
    runs.isEmpty
        ? <MarkdownPretextInlineRun>[
            MarkdownPretextInlineRun(text: '', style: fallbackStyle),
          ]
        : runs,
    textScaleFactor,
  );
  if (runs.isEmpty || plainText.isEmpty) {
    return MarkdownPretextLayoutResult(
      plainText: plainText,
      lines: const <MarkdownPretextLayoutLine>[],
      lineHeight: lineHeight,
      textScaleFactor: textScaleFactor,
    );
  }

  final safeMaxWidth = maxWidth.isFinite ? math.max(maxWidth, 0.0) : 100000.0;
  final alignmentWidth = maxWidth.isFinite ? math.max(maxWidth, 0.0) : 0.0;
  final reservedDecoratedWrapPadding = runs
      .where((run) => run.decoration != null && run.allowCharacterWrap)
      .fold<double>(
        0,
        (current, run) => current + run.decoration!.padding.horizontal,
      );
  final segmentBuilder = _MarkdownPretextSegmentBuilder(
    textScaleFactor: textScaleFactor,
  );
  final segments = segmentBuilder.build(runs);
  final prepared = PreparedTextWithSegments.fromSegments(
    segments
        .map(
          (segment) => pretext_segment.Segment(
            text: segment.displayText,
            kind: segment.kind,
            width: segment.width,
          ),
        )
        .toList(growable: false),
  );
  final result = layoutWithLines(
    prepared,
    math.max(safeMaxWidth - reservedDecoratedWrapPadding, 0),
    lineHeight,
  );

  final lines = <MarkdownPretextLayoutLine>[];
  var cursor = 0;
  var originalCursor = 0;
  for (final line in result.lines) {
    final carryLength = math.max(originalCursor - cursor, 0);
    final visibleTextLength = carryLength + line.text.length;
    final fittedVisibleTextLength =
        _fitVisibleTextLengthToRenderedWidthFromOffset(
      segments: segments,
      startOffset: cursor,
      endSegmentIndex: line.end.segmentIndex,
      visibleTextLength: visibleTextLength,
      maxRenderedWidth: safeMaxWidth,
      textScaleFactor: textScaleFactor,
    );
    final lineFragments = _buildLineFragmentsFromOffset(
      segments: segments,
      startOffset: cursor,
      endSegmentIndex: line.end.segmentIndex,
      visibleTextLength: fittedVisibleTextLength,
      maxRenderedWidth: safeMaxWidth,
      textScaleFactor: textScaleFactor,
    );
    final renderedLineText =
        lineFragments.map((fragment) => fragment.text).join();
    final startOffset = cursor;
    final visibleEndOffset =
        _consumeVisibleText(plainText, cursor, renderedLineText);
    var endOffset = visibleEndOffset;
    while (endOffset < plainText.length && plainText[endOffset] == ' ') {
      endOffset += 1;
    }
    if (endOffset < plainText.length && plainText[endOffset] == '\n') {
      endOffset += 1;
    }
    final originalVisibleEndOffset =
        _consumeVisibleText(plainText, originalCursor, line.text);
    var originalEndOffset = originalVisibleEndOffset;
    while (originalEndOffset < plainText.length &&
        plainText[originalEndOffset] == ' ') {
      originalEndOffset += 1;
    }
    if (originalEndOffset < plainText.length &&
        plainText[originalEndOffset] == '\n') {
      originalEndOffset += 1;
    }
    lines.add(
      MarkdownPretextLayoutLine(
        text: renderedLineText,
        span: _buildLineSpanFromFragments(
          lineFragments,
          fallbackStyle: fallbackStyle,
        ),
        segments: _buildLineSegmentsFromFragments(
          lineFragments,
          textScaleFactor: textScaleFactor,
        ),
        width: math.min(
          _measureRenderedFragmentWidth(
            lineFragments,
            textScaleFactor: textScaleFactor,
          ),
          safeMaxWidth,
        ),
        height: _measureRenderedFragmentLineHeight(
          lineFragments,
          fallbackStyle: fallbackStyle,
          textScaleFactor: textScaleFactor,
        ),
        leadingOffset: _resolveLineLeadingOffset(
          lineWidth: math.min(
            _measureRenderedFragmentWidth(
              lineFragments,
              textScaleFactor: textScaleFactor,
            ),
            safeMaxWidth,
          ),
          maxWidth: alignmentWidth,
          textAlign: textAlign,
          textDirection: textDirection,
        ),
        startOffset: startOffset,
        endOffset: endOffset,
        visibleEndOffset: visibleEndOffset,
      ),
    );
    cursor = endOffset;
    originalCursor = originalEndOffset;
  }

  return MarkdownPretextLayoutResult(
    plainText: plainText,
    lines: List<MarkdownPretextLayoutLine>.unmodifiable(lines),
    lineHeight: lines.fold<double>(
      lineHeight,
      (current, line) => math.max(current, line.height),
    ),
    textScaleFactor: textScaleFactor,
  );
}

@immutable
class MarkdownPretextLayoutResult {
  const MarkdownPretextLayoutResult({
    required this.plainText,
    required this.lines,
    required this.lineHeight,
    required this.textScaleFactor,
  });

  final String plainText;
  final List<MarkdownPretextLayoutLine> lines;
  final double lineHeight;
  final double textScaleFactor;

  List<Rect> selectionRectsForRange(
    DocumentRange range, {
    required TextDirection textDirection,
  }) {
    final rects = <Rect>[];
    var lineTop = 0.0;
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final selectionStart = math.max(range.start.textOffset, line.startOffset);
      final selectionEnd =
          math.min(range.end.textOffset, line.visibleEndOffset);
      if (selectionStart < selectionEnd && line.text.isNotEmpty) {
        final mergedBoxes = _mergeSelectionBoxes(
          _selectionBoxesForLine(
            line,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            lineTop: lineTop,
            textDirection: textDirection,
          ),
        );
        for (final box in mergedBoxes) {
          rects.add(
            Rect.fromLTRB(
              box.left - 1.0,
              box.top,
              box.right + 1.0,
              box.bottom,
            ),
          );
        }
      }
      lineTop += line.height;
    }
    return rects;
  }

  int textOffsetAt(
    Offset localPosition, {
    required TextDirection textDirection,
  }) {
    final line = _lineForLocalPosition(localPosition);
    if (line == null) {
      return 0;
    }
    if (line.text.isEmpty) {
      return localPosition.dx <= line.leadingOffset
          ? line.startOffset
          : line.endOffset;
    }

    final localDx = (localPosition.dx - line.leadingOffset)
        .clamp(0.0, math.max(line.width, 0.0));
    return _textOffsetAtLineDx(
      line,
      localDx.toDouble(),
      textDirection: textDirection,
    );
  }

  ({int start, int end})? visualLineRangeForLocalPosition(
    Offset localPosition,
  ) {
    final line = _lineForLocalPosition(localPosition);
    if (line == null) {
      return null;
    }
    return (start: line.startOffset, end: line.visibleEndOffset);
  }

  ({int start, int end})? lineRangeForTextOffset(int textOffset) {
    if (lines.isEmpty) {
      return null;
    }
    if (plainText.isEmpty) {
      return (start: 0, end: 0);
    }

    var clampedOffset = textOffset.clamp(0, plainText.length).toInt();
    if (clampedOffset == plainText.length && clampedOffset > 0) {
      clampedOffset -= 1;
    }
    if (clampedOffset > 0 &&
        clampedOffset < plainText.length &&
        plainText.codeUnitAt(clampedOffset) == 0x0A) {
      clampedOffset -= 1;
    }

    var start = clampedOffset;
    while (start > 0 && plainText.codeUnitAt(start - 1) != 0x0A) {
      start -= 1;
    }
    var end = clampedOffset;
    while (end < plainText.length && plainText.codeUnitAt(end) != 0x0A) {
      end += 1;
    }
    return (start: start, end: end);
  }

  MarkdownPretextLayoutLine? _lineForLocalPosition(Offset localPosition) {
    if (lines.isEmpty) {
      return null;
    }

    var lineTop = 0.0;
    var line = lines.last;
    for (final candidate in lines) {
      final lineBottom = lineTop + candidate.height;
      if (localPosition.dy <= lineBottom) {
        line = candidate;
        break;
      }
      lineTop = lineBottom;
    }
    return line;
  }

  Iterable<Rect> _selectionBoxesForLine(
    MarkdownPretextLayoutLine line, {
    required int selectionStart,
    required int selectionEnd,
    required double lineTop,
    required TextDirection textDirection,
  }) sync* {
    for (final segment in line.segments) {
      final segmentSelectionStart =
          math.max(selectionStart, segment.startOffset);
      final segmentSelectionEnd = math.min(selectionEnd, segment.endOffset);
      if (segmentSelectionStart >= segmentSelectionEnd) {
        continue;
      }
      final left = segmentSelectionStart == segment.startOffset
          ? segment.left
          : segment.left +
              _horizontalOffsetForTextOffset(
                segment,
                segmentSelectionStart - segment.startOffset,
                textDirection: textDirection,
              );
      final right = segmentSelectionEnd == segment.endOffset
          ? segment.right
          : segment.left +
              _horizontalOffsetForTextOffset(
                segment,
                segmentSelectionEnd - segment.startOffset,
                textDirection: textDirection,
              );
      yield Rect.fromLTRB(left + line.leadingOffset, lineTop,
          right + line.leadingOffset, lineTop + line.height);
    }
  }

  int _textOffsetAtLineDx(
    MarkdownPretextLayoutLine line,
    double localDx, {
    required TextDirection textDirection,
  }) {
    for (final segment in line.segments) {
      if (localDx > segment.right) {
        continue;
      }
      if (localDx <= segment.left) {
        return segment.startOffset;
      }
      final offsetInSegment = _textOffsetForHorizontalPosition(
        segment,
        localDx - segment.left,
        textDirection: textDirection,
      );
      return segment.startOffset + offsetInSegment;
    }
    return line.endOffset;
  }

  Iterable<Rect> _mergeSelectionBoxes(Iterable<Rect> boxes) sync* {
    final sorted = boxes.toList(growable: false)
      ..sort((a, b) {
        final topCompare = a.top.compareTo(b.top);
        if (topCompare != 0) {
          return topCompare;
        }
        return a.left.compareTo(b.left);
      });
    if (sorted.isEmpty) {
      return;
    }

    var current = sorted.first;
    for (final next in sorted.skip(1)) {
      if (next.left <= current.right + 0.5) {
        current = Rect.fromLTRB(
          current.left,
          current.top,
          math.max(current.right, next.right),
          current.bottom,
        );
        continue;
      }
      yield current;
      current = next;
    }
    yield current;
  }
}

@immutable
class MarkdownPretextLayoutLine {
  const MarkdownPretextLayoutLine({
    required this.text,
    required this.span,
    required this.segments,
    required this.width,
    required this.height,
    required this.leadingOffset,
    required this.startOffset,
    required this.endOffset,
    required this.visibleEndOffset,
  });

  final String text;
  final InlineSpan span;
  final List<MarkdownPretextLayoutSegment> segments;
  final double width;
  final double height;
  final double leadingOffset;
  final int startOffset;
  final int endOffset;
  final int visibleEndOffset;
}

@immutable
class MarkdownPretextLayoutSegment {
  const MarkdownPretextLayoutSegment({
    required this.text,
    required this.style,
    required this.startOffset,
    required this.endOffset,
    required this.left,
    required this.right,
    this.renderSpan,
    this.decoration,
    this.padding = EdgeInsets.zero,
  });

  final String text;
  final TextStyle style;
  final int startOffset;
  final int endOffset;
  final double left;
  final double right;
  final InlineSpan? renderSpan;
  final MarkdownPretextInlineDecoration? decoration;
  final EdgeInsets padding;
}

InlineSpan _buildFullSpan({
  required List<MarkdownPretextInlineRun> runs,
  required TextStyle fallbackStyle,
}) {
  return TextSpan(
    style: fallbackStyle,
    children: <InlineSpan>[
      for (final run in runs)
        if (run.renderSpan != null)
          run.renderSpan!
        else if (run.decoration == null)
          TextSpan(
            text: run.text,
            style: run.style,
            mouseCursor: run.mouseCursor,
            recognizer: run.recognizer,
          )
        else if (run.allowCharacterWrap)
          ..._buildBreakableDecoratedFullSpans(run)
        else
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _DecoratedInlineText(
              text: run.text,
              style: run.style,
              decoration: run.decoration!,
            ),
          ),
    ],
  );
}

List<InlineSpan> _buildBreakableDecoratedFullSpans(
  MarkdownPretextInlineRun run,
) {
  final text = run.text;
  if (text.isEmpty) {
    return const <InlineSpan>[];
  }

  final spans = <InlineSpan>[];
  var chunkStart = 0;
  while (chunkStart < text.length) {
    final newlineIndex = text.indexOf('\n', chunkStart);
    final chunkEnd = newlineIndex == -1 ? text.length : newlineIndex;
    if (chunkEnd > chunkStart) {
      final chunk = text.substring(chunkStart, chunkEnd);
      final baseBorderRadius = run.decoration!.borderRadius;
      for (var index = 0; index < chunk.length; index++) {
        final character = chunk[index];
        final isFirst = index == 0;
        final isLast = index == chunk.length - 1;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _DecoratedInlineText(
              text: character,
              style: run.style,
              decoration: run.decoration!.copyWith(
                borderRadius: BorderRadius.only(
                  topLeft: isFirst ? baseBorderRadius.topLeft : Radius.zero,
                  bottomLeft:
                      isFirst ? baseBorderRadius.bottomLeft : Radius.zero,
                  topRight: isLast ? baseBorderRadius.topRight : Radius.zero,
                  bottomRight:
                      isLast ? baseBorderRadius.bottomRight : Radius.zero,
                ),
                padding: EdgeInsets.only(
                  left: isFirst ? run.decoration!.padding.left : 0,
                  right: isLast ? run.decoration!.padding.right : 0,
                  top: run.decoration!.padding.top,
                  bottom: run.decoration!.padding.bottom,
                ),
              ),
            ),
          ),
        );
      }
    }
    if (newlineIndex != -1) {
      spans.add(const TextSpan(text: '\n'));
      chunkStart = newlineIndex + 1;
    } else {
      chunkStart = text.length;
    }
  }

  return spans;
}

class _DecoratedInlineText extends LeafRenderObjectWidget {
  const _DecoratedInlineText({
    required this.text,
    required this.style,
    required this.decoration,
  });

  final String text;
  final TextStyle style;
  final MarkdownPretextInlineDecoration decoration;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDecoratedInlineText(
      text,
      style,
      decoration,
      (MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling)
          .scale(1.0),
      View.of(context).devicePixelRatio,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDecoratedInlineText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..decoration = decoration
      ..textScaleFactor =
          (MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling)
              .scale(1.0)
      ..devicePixelRatio = View.of(context).devicePixelRatio;
  }
}

class _RenderDecoratedInlineText extends RenderBox {
  _RenderDecoratedInlineText(
    this._text,
    this._style,
    this._decoration,
    this._textScaleFactor,
    this._devicePixelRatio,
  ) {
    _textPainter.textDirection = TextDirection.ltr;
    _textPainter.maxLines = 1;
    _recomputeMetrics();
  }

  final TextPainter _textPainter = TextPainter();
  _TightTextMetrics _metrics = const _TightTextMetrics(
    tightTop: 0,
    tightBottom: 0,
    tightBaseline: 0,
  );

  String _text;
  TextStyle _style;
  MarkdownPretextInlineDecoration _decoration;
  double _textScaleFactor;
  double _devicePixelRatio;

  String get text => _text;
  set text(String value) {
    if (value == _text) {
      return;
    }
    _text = value;
    _recomputeMetrics();
    markNeedsLayout();
    markNeedsPaint();
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    _recomputeMetrics();
    markNeedsLayout();
    markNeedsPaint();
  }

  MarkdownPretextInlineDecoration get decoration => _decoration;
  set decoration(MarkdownPretextInlineDecoration value) {
    if (value == _decoration) {
      return;
    }
    _decoration = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  double get textScaleFactor => _textScaleFactor;
  set textScaleFactor(double value) {
    if (value == _textScaleFactor) {
      return;
    }
    _textScaleFactor = value;
    _recomputeMetrics();
    markNeedsLayout();
    markNeedsPaint();
  }

  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  void _recomputeMetrics() {
    _textPainter
      ..text = TextSpan(text: _text, style: _style)
      ..textScaler = TextScaler.linear(_textScaleFactor)
      ..layout(maxWidth: double.infinity);
    _metrics = _measureTightTextMetrics(
      _text,
      _style,
      _textScaleFactor,
    );
  }

  Size _computeSize(BoxConstraints constraints) {
    final desiredSize = Size(
      _textPainter.width + _decoration.padding.horizontal,
      _metrics.tightHeight + _decoration.padding.vertical,
    );
    return constraints.constrain(desiredSize);
  }

  @override
  void performLayout() {
    size = _computeSize(constraints);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return _computeSize(constraints);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return _textPainter.width + _decoration.padding.horizontal;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return _textPainter.width + _decoration.padding.horizontal;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _metrics.tightHeight + _decoration.padding.vertical;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _metrics.tightHeight + _decoration.padding.vertical;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    if (baseline != TextBaseline.alphabetic) {
      return super.computeDistanceToActualBaseline(baseline);
    }
    return _snapToPixel(
      _metrics.tightBaseline + _decoration.padding.top + _opticalBaselineLift,
    );
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    if (baseline != TextBaseline.alphabetic) {
      return super.computeDryBaseline(constraints, baseline);
    }
    return _snapToPixel(
      _metrics.tightBaseline + _decoration.padding.top + _opticalBaselineLift,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final backgroundRect = offset & size;
    canvas.drawRRect(
      _decoration.borderRadius.toRRect(backgroundRect),
      Paint()..color = _decoration.backgroundColor,
    );
    _textPainter.paint(
      canvas,
      offset +
          Offset(
            _decoration.padding.left,
            _snapToPixel(_decoration.padding.top - _metrics.tightTop),
          ),
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;

  double _snapToPixel(double value) {
    final dpr = _devicePixelRatio <= 0 ? 1.0 : _devicePixelRatio;
    return (value * dpr).roundToDouble() / dpr;
  }

  double get _opticalBaselineLift {
    // Tight glyph bounds on monospace fonts often look slightly bottom-heavy
    // even when the mathematical baseline is correct, so nudge the chip up a
    // touch for optical alignment.
    return _snapToPixel(math.min(_metrics.tightTop, 1.0));
  }
}

double _resolveLineLeadingOffset({
  required double lineWidth,
  required double maxWidth,
  required TextAlign textAlign,
  required TextDirection textDirection,
}) {
  if (maxWidth <= 0 || lineWidth >= maxWidth) {
    return 0;
  }

  switch (textAlign) {
    case TextAlign.left:
    case TextAlign.justify:
      return 0;
    case TextAlign.right:
      return maxWidth - lineWidth;
    case TextAlign.center:
      return (maxWidth - lineWidth) / 2;
    case TextAlign.start:
      return textDirection == TextDirection.ltr ? 0 : maxWidth - lineWidth;
    case TextAlign.end:
      return textDirection == TextDirection.ltr ? maxWidth - lineWidth : 0;
  }
}

InlineSpan _buildLineSpanFromFragments(
  List<_MarkdownPretextLineFragment> fragments, {
  required TextStyle fallbackStyle,
}) {
  final children = <InlineSpan>[];
  for (final fragment in fragments) {
    if (fragment.renderSpan != null) {
      children.add(fragment.renderSpan!);
      continue;
    }
    if (fragment.decoration == null) {
      children.add(
        TextSpan(
          text: fragment.text,
          style: fragment.style,
          mouseCursor: fragment.mouseCursor,
          recognizer: fragment.recognizer,
        ),
      );
      continue;
    }
    children.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _DecoratedInlineText(
          text: fragment.text,
          style: fragment.style,
          decoration: fragment.decoration!.copyWith(padding: fragment.padding),
        ),
      ),
    );
  }

  if (children.isEmpty) {
    return TextSpan(style: fallbackStyle, text: ' ');
  }
  return TextSpan(style: fallbackStyle, children: children);
}

List<MarkdownPretextLayoutSegment> _buildLineSegmentsFromFragments(
  List<_MarkdownPretextLineFragment> fragments, {
  required double textScaleFactor,
}) {
  final lineSegments = <MarkdownPretextLayoutSegment>[];
  final measurer = _TextPainterSegmentMeasurer();
  var cursor = 0.0;

  for (final fragment in fragments) {
    final width = fragment.estimatedWidth ??
        measurer.measure(
          fragment.text,
          fragment.style,
          textScaleFactor,
          padding: fragment.padding,
        );
    lineSegments.add(
      MarkdownPretextLayoutSegment(
        text: fragment.text,
        style: fragment.style,
        startOffset: fragment.startOffset,
        endOffset: fragment.endOffset,
        left: cursor,
        right: cursor + width,
        renderSpan: fragment.renderSpan,
        decoration: fragment.decoration,
        padding: fragment.padding,
      ),
    );
    cursor += width;
  }

  return List<MarkdownPretextLayoutSegment>.unmodifiable(lineSegments);
}

List<_MarkdownPretextLineFragment> _buildLineFragmentsFromOffset({
  required List<_MarkdownPretextMeasuredSegment> segments,
  required int startOffset,
  required int endSegmentIndex,
  required int visibleTextLength,
  required double maxRenderedWidth,
  required double textScaleFactor,
}) {
  if (visibleTextLength <= 0) {
    return const <_MarkdownPretextLineFragment>[];
  }

  final fragments = <_MarkdownPretextLineFragment>[];
  var remaining = visibleTextLength;
  var startSegmentIndex = _segmentIndexForOffset(segments, startOffset);
  if (startSegmentIndex < 0) {
    startSegmentIndex = 0;
  }

  for (var index = startSegmentIndex;
      index < endSegmentIndex && index < segments.length && remaining > 0;
      index++) {
    final segment = segments[index];
    if (segment.kind == pretext_segment.SegmentKind.hardBreak ||
        segment.displayText.isEmpty) {
      continue;
    }

    final localStartOffset = math.max(startOffset, segment.startOffset);
    if (localStartOffset >= segment.endOffset) {
      continue;
    }

    final startIndexInSegment = localStartOffset - segment.startOffset;
    final availableText = segment.displayText.substring(startIndexInSegment);
    final takeLength = segment.renderSpan != null
        ? availableText.length
        : math.min(availableText.length, remaining);
    if (takeLength <= 0) {
      continue;
    }

    final text = takeLength == availableText.length
        ? availableText
        : availableText.substring(0, takeLength);
    final endOffset = localStartOffset + text.length;
    fragments.add(
      _MarkdownPretextLineFragment(
        text: text,
        style: segment.style,
        mouseCursor: segment.mouseCursor,
        recognizer: segment.recognizer,
        renderSpan: segment.renderSpan,
        decoration: segment.decoration,
        estimatedWidth: segment.renderSpan != null ? segment.width : null,
        estimatedLineHeight: segment.estimatedLineHeight,
        padding: _paddingForDecoratedFragmentSlice(
          segment,
          startOffset: localStartOffset,
          endOffset: endOffset,
        ),
        startOffset: localStartOffset,
        endOffset: endOffset,
        startsDecoratedChunk: segment.startsDecoratedChunk &&
            localStartOffset == segment.startOffset,
        endsDecoratedChunk:
            segment.endsDecoratedChunk && endOffset == segment.endOffset,
      ),
    );
    remaining -= takeLength;
  }

  return _applyLineLocalDecoratedPadding(
    fragments,
    maxRenderedWidth: maxRenderedWidth,
    textScaleFactor: textScaleFactor,
  );
}

int _segmentIndexForOffset(
  List<_MarkdownPretextMeasuredSegment> segments,
  int offset,
) {
  for (var index = 0; index < segments.length; index++) {
    if (segments[index].endOffset > offset) {
      return index;
    }
  }
  return segments.length - 1;
}

int _fitVisibleTextLengthToRenderedWidthFromOffset({
  required List<_MarkdownPretextMeasuredSegment> segments,
  required int startOffset,
  required int endSegmentIndex,
  required int visibleTextLength,
  required double maxRenderedWidth,
  required double textScaleFactor,
}) {
  final startSegmentIndex = _segmentIndexForOffset(segments, startOffset);
  for (var index = startSegmentIndex;
      index < endSegmentIndex && index < segments.length;
      index++) {
    if (segments[index].renderSpan != null) {
      return visibleTextLength;
    }
  }
  var fittedLength = visibleTextLength;
  while (fittedLength > 0) {
    final fragments = _buildLineFragmentsFromOffset(
      segments: segments,
      startOffset: startOffset,
      endSegmentIndex: endSegmentIndex,
      visibleTextLength: fittedLength,
      maxRenderedWidth: maxRenderedWidth,
      textScaleFactor: textScaleFactor,
    );
    final renderedWidth = _measureRenderedFragmentWidth(
      fragments,
      textScaleFactor: textScaleFactor,
    );
    if (renderedWidth <= maxRenderedWidth + 0.01) {
      return fittedLength;
    }
    fittedLength -= 1;
  }
  return visibleTextLength > 0 ? 1 : 0;
}

double _measureRenderedFragmentWidth(
  List<_MarkdownPretextLineFragment> fragments, {
  required double textScaleFactor,
}) {
  final measurer = _TextPainterSegmentMeasurer();
  return fragments.fold<double>(
    0,
    (current, fragment) =>
        current +
        (fragment.estimatedWidth ??
            measurer.measure(
              fragment.text,
              fragment.style,
              textScaleFactor,
              padding: fragment.padding,
            )),
  );
}

double _measureRenderedFragmentLineHeight(
  List<_MarkdownPretextLineFragment> fragments, {
  required TextStyle fallbackStyle,
  required double textScaleFactor,
}) {
  if (fragments.isEmpty) {
    return _measureLineHeight(fallbackStyle, textScaleFactor);
  }

  var height = 0.0;
  for (final fragment in fragments) {
    final measured = fragment.renderSpan != null
        ? fragment.estimatedLineHeight ??
            _measureLineHeight(fragment.style, textScaleFactor)
        : _measureLineHeight(
            fragment.style,
            textScaleFactor,
            padding: fragment.decoration == null ? null : fragment.padding,
          );
    if (measured > height) {
      height = measured;
    }
  }
  return height;
}

EdgeInsets _paddingForDecoratedFragmentSlice(
  _MarkdownPretextMeasuredSegment segment, {
  required int startOffset,
  required int endOffset,
}) {
  final decoration = segment.decoration;
  if (decoration == null) {
    return EdgeInsets.zero;
  }
  return EdgeInsets.only(
    left: segment.startsDecoratedChunk && startOffset == segment.startOffset
        ? decoration.padding.left
        : 0,
    right: segment.endsDecoratedChunk && endOffset == segment.endOffset
        ? decoration.padding.right
        : 0,
    top: decoration.padding.top,
    bottom: decoration.padding.bottom,
  );
}

List<_MarkdownPretextLineFragment> _applyLineLocalDecoratedPadding(
  List<_MarkdownPretextLineFragment> fragments, {
  required double maxRenderedWidth,
  required double textScaleFactor,
}) {
  if (fragments.isEmpty) {
    return fragments;
  }

  final measurer = _TextPainterSegmentMeasurer();
  final baseWidth = fragments.fold<double>(
    0,
    (current, fragment) =>
        current +
        (fragment.estimatedWidth ??
            measurer.measure(
              fragment.text,
              fragment.style,
              textScaleFactor,
              padding: fragment.padding,
            )),
  );
  final horizontalPaddingBudget = math.max(maxRenderedWidth - baseWidth, 0.0);
  final desiredHorizontalPadding =
      fragments.fold<double>(0, (current, fragment) {
    final decoration = fragment.decoration;
    if (decoration == null) {
      return current;
    }
    return current +
        (fragment.startsDecoratedChunk ? 0 : decoration.padding.left) +
        (fragment.endsDecoratedChunk ? 0 : decoration.padding.right);
  });
  final horizontalPaddingScale = desiredHorizontalPadding <= 0
      ? 1.0
      : math.min(horizontalPaddingBudget / desiredHorizontalPadding, 1.0);

  final normalized = <_MarkdownPretextLineFragment>[];
  var index = 0;
  while (index < fragments.length) {
    final fragment = fragments[index];
    if (fragment.decoration == null) {
      normalized.add(fragment);
      index += 1;
      continue;
    }

    var end = index + 1;
    while (end < fragments.length && fragments[end].decoration != null) {
      end += 1;
    }

    for (var current = index; current < end; current++) {
      final currentFragment = fragments[current];
      final decoration = currentFragment.decoration!;
      final isFirst = current == index;
      final isLast = current == end - 1;
      normalized.add(
        currentFragment.copyWith(
          decoration: decoration.copyWith(
            borderRadius: BorderRadius.only(
              topLeft: isFirst ? decoration.borderRadius.topLeft : Radius.zero,
              bottomLeft:
                  isFirst ? decoration.borderRadius.bottomLeft : Radius.zero,
              topRight: isLast ? decoration.borderRadius.topRight : Radius.zero,
              bottomRight:
                  isLast ? decoration.borderRadius.bottomRight : Radius.zero,
            ),
          ),
          padding: EdgeInsets.only(
            left: currentFragment.padding.left +
                (isFirst && !currentFragment.startsDecoratedChunk
                    ? decoration.padding.left * horizontalPaddingScale
                    : 0),
            right: currentFragment.padding.right +
                (isLast && !currentFragment.endsDecoratedChunk
                    ? decoration.padding.right * horizontalPaddingScale
                    : 0),
            top: decoration.padding.top,
            bottom: decoration.padding.bottom,
          ),
        ),
      );
    }
    index = end;
  }

  return normalized;
}

double _measureMaxLineHeight(
  Iterable<MarkdownPretextInlineRun> runs,
  double textScaleFactor,
) {
  var lineHeight = 0.0;
  for (final run in runs) {
    final measured = run.estimatedLineHeight ??
        _measureLineHeight(
          run.style,
          textScaleFactor,
          padding: run.decoration?.padding,
        );
    if (measured > lineHeight) {
      lineHeight = measured;
    }
  }
  return lineHeight;
}

double _measureLineHeight(
  TextStyle style,
  double textScaleFactor, {
  EdgeInsets? padding,
}) {
  if (padding != null) {
    final metrics = _measureTightTextMetrics(' ', style, textScaleFactor);
    return metrics.tightHeight + padding.vertical;
  }
  final textPainter = TextPainter(
    text: TextSpan(text: ' ', style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(textScaleFactor),
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  return textPainter.preferredLineHeight + (padding?.vertical ?? 0);
}

@immutable
class _TightTextMetrics {
  const _TightTextMetrics({
    required this.tightTop,
    required this.tightBottom,
    required this.tightBaseline,
  });

  final double tightTop;
  final double tightBottom;
  final double tightBaseline;

  double get tightHeight => tightBottom - tightTop;

  @override
  bool operator ==(Object other) {
    return other is _TightTextMetrics &&
        other.tightTop == tightTop &&
        other.tightBottom == tightBottom &&
        other.tightBaseline == tightBaseline;
  }

  @override
  int get hashCode => Object.hash(tightTop, tightBottom, tightBaseline);
}

_TightTextMetrics _measureTightTextMetrics(
  String text,
  TextStyle style,
  double textScaleFactor,
) {
  final sampleText = text.isEmpty ? ' ' : text;
  final textPainter = TextPainter(
    text: TextSpan(text: sampleText, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(textScaleFactor),
    maxLines: 1,
  )..layout(maxWidth: double.infinity);

  final lineMetrics = textPainter.computeLineMetrics().first;
  final boxes = textPainter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: sampleText.length),
  );
  if (boxes.isEmpty) {
    final top = lineMetrics.baseline - lineMetrics.ascent;
    return _TightTextMetrics(
      tightTop: top,
      tightBottom: lineMetrics.baseline + lineMetrics.descent,
      tightBaseline: lineMetrics.baseline - top,
    );
  }

  var top = boxes.first.top;
  var bottom = boxes.first.bottom;
  for (final box in boxes.skip(1)) {
    top = math.min(top, box.top);
    bottom = math.max(bottom, box.bottom);
  }
  return _TightTextMetrics(
    tightTop: top,
    tightBottom: bottom,
    tightBaseline: lineMetrics.baseline - top,
  );
}

int _consumeVisibleText(String source, int startOffset, String visibleText) {
  var cursor = startOffset;
  for (final codeUnit in visibleText.codeUnits) {
    if (cursor >= source.length || source.codeUnitAt(cursor) != codeUnit) {
      return startOffset + visibleText.length;
    }
    cursor += 1;
  }
  return cursor;
}

double _horizontalOffsetForTextOffset(
  MarkdownPretextLayoutSegment segment,
  int textOffset, {
  required TextDirection textDirection,
}) {
  final clampedOffset = textOffset.clamp(0, segment.text.length);
  if (segment.renderSpan != null) {
    if (segment.text.isEmpty) {
      return 0;
    }
    final segmentWidth = segment.right - segment.left;
    return segmentWidth * clampedOffset / segment.text.length;
  }
  final prefix = segment.text.substring(0, clampedOffset);
  final textWidth = _measureInlineTextWidth(prefix, segment.style,
      textDirection: textDirection);
  if (segment.decoration == null) {
    return textWidth;
  }
  return segment.padding.left + textWidth;
}

int _textOffsetForHorizontalPosition(
  MarkdownPretextLayoutSegment segment,
  double dx, {
  required TextDirection textDirection,
}) {
  if (segment.renderSpan != null) {
    final segmentWidth = segment.right - segment.left;
    if (segmentWidth <= 0 || segment.text.isEmpty) {
      return 0;
    }
    return ((dx.clamp(0.0, segmentWidth) / segmentWidth) * segment.text.length)
        .round()
        .clamp(0, segment.text.length);
  }
  final decoration = segment.decoration;
  if (decoration != null) {
    final textWidth = _measureInlineTextWidth(
      segment.text,
      segment.style,
      textDirection: textDirection,
    );
    if (dx <= segment.padding.left) {
      return 0;
    }
    if (dx >= segment.padding.left + textWidth) {
      return segment.text.length;
    }
    return _resolveTextOffsetForSegment(
      segment.text,
      segment.style,
      dx - segment.padding.left,
      textDirection: textDirection,
    );
  }
  return _resolveTextOffsetForSegment(
    segment.text,
    segment.style,
    dx,
    textDirection: textDirection,
  );
}

class _MarkdownPretextSegmentBuilder {
  _MarkdownPretextSegmentBuilder({required this.textScaleFactor});

  final double textScaleFactor;
  final _TextPainterSegmentMeasurer _measurer = _TextPainterSegmentMeasurer();

  List<_MarkdownPretextMeasuredSegment> build(
    List<MarkdownPretextInlineRun> runs,
  ) {
    final segments = <_MarkdownPretextMeasuredSegment>[];
    var plainTextOffset = 0;

    for (final run in runs) {
      final text = run.text;
      if (run.renderSpan != null) {
        if (text.isEmpty) {
          continue;
        }
        segments.add(
          _MarkdownPretextMeasuredSegment(
            displayText: text,
            kind: pretext_segment.SegmentKind.word,
            width: run.estimatedWidth ??
                _measurer.measure(text, run.style, textScaleFactor),
            style: run.style,
            mouseCursor: run.mouseCursor,
            recognizer: run.recognizer,
            renderSpan: run.renderSpan,
            estimatedLineHeight: run.estimatedLineHeight,
            startOffset: plainTextOffset,
            endOffset: plainTextOffset + text.length,
          ),
        );
        plainTextOffset += text.length;
        continue;
      }
      var index = 0;
      while (index < text.length) {
        final character = text[index];
        if (character == '\n') {
          segments.add(
            _MarkdownPretextMeasuredSegment(
              displayText: '\n',
              kind: pretext_segment.SegmentKind.hardBreak,
              width: 0,
              style: run.style,
              mouseCursor: run.mouseCursor,
              recognizer: run.recognizer,
              renderSpan: run.renderSpan,
              decoration: run.decoration,
              startOffset: plainTextOffset,
              endOffset: plainTextOffset + 1,
              startsDecoratedChunk: false,
              endsDecoratedChunk: false,
            ),
          );
          index += 1;
          plainTextOffset += 1;
          continue;
        }

        if (run.decoration != null && run.allowCharacterWrap) {
          final chunkStartOffset = plainTextOffset;
          while (index < text.length && text[index] != '\n') {
            final displayText = text[index];
            final isChunkStart = plainTextOffset == chunkStartOffset;
            segments.add(
              _MarkdownPretextMeasuredSegment(
                displayText: displayText,
                kind: pretext_segment.SegmentKind.word,
                width: _measurer.measure(
                  displayText,
                  run.style,
                  textScaleFactor,
                ),
                style: run.style,
                mouseCursor: run.mouseCursor,
                recognizer: run.recognizer,
                renderSpan: run.renderSpan,
                decoration: run.decoration,
                startOffset: plainTextOffset,
                endOffset: plainTextOffset + displayText.length,
                startsDecoratedChunk: isChunkStart,
                endsDecoratedChunk: false,
              ),
            );
            index += 1;
            plainTextOffset += displayText.length;
          }
          if (plainTextOffset > chunkStartOffset) {
            final last = segments.removeLast();
            segments.add(
              _MarkdownPretextMeasuredSegment(
                displayText: last.displayText,
                kind: last.kind,
                width: last.width,
                style: last.style,
                startOffset: last.startOffset,
                endOffset: last.endOffset,
                mouseCursor: last.mouseCursor,
                recognizer: last.recognizer,
                renderSpan: last.renderSpan,
                estimatedLineHeight: last.estimatedLineHeight,
                decoration: last.decoration,
                startsDecoratedChunk: last.startsDecoratedChunk,
                endsDecoratedChunk: true,
              ),
            );
          }
          continue;
        }

        if (run.decoration != null) {
          final displayText = text.substring(index);
          segments.add(
            _MarkdownPretextMeasuredSegment(
              displayText: displayText,
              kind: pretext_segment.SegmentKind.word,
              width: _measurer.measure(
                displayText,
                run.style,
                textScaleFactor,
                padding: run.decoration?.padding,
              ),
              style: run.style,
              mouseCursor: run.mouseCursor,
              recognizer: run.recognizer,
              renderSpan: run.renderSpan,
              decoration: run.decoration,
              startOffset: plainTextOffset,
              endOffset: plainTextOffset + displayText.length,
              startsDecoratedChunk: true,
              endsDecoratedChunk: true,
            ),
          );
          plainTextOffset += displayText.length;
          break;
        }

        final isWhitespace = character.trim().isEmpty;
        final buffer = StringBuffer();
        final startOffset = plainTextOffset;
        while (index < text.length) {
          final nextCharacter = text[index];
          if (nextCharacter == '\n') {
            break;
          }
          final nextIsWhitespace = nextCharacter.trim().isEmpty;
          if (nextIsWhitespace != isWhitespace) {
            break;
          }
          buffer.write(nextCharacter == '\t' ? ' ' : nextCharacter);
          index += 1;
          plainTextOffset += 1;
        }
        final displayText = buffer.toString();
        if (displayText.isEmpty) {
          continue;
        }
        segments.add(
          _MarkdownPretextMeasuredSegment(
            displayText: displayText,
            kind: isWhitespace
                ? pretext_segment.SegmentKind.space
                : pretext_segment.SegmentKind.word,
            width: _measurer.measure(
              displayText,
              run.style,
              textScaleFactor,
              padding: run.decoration?.padding,
            ),
            style: run.style,
            mouseCursor: run.mouseCursor,
            recognizer: run.recognizer,
            renderSpan: run.renderSpan,
            decoration: run.decoration,
            startOffset: startOffset,
            endOffset: plainTextOffset,
            startsDecoratedChunk: false,
            endsDecoratedChunk: false,
          ),
        );
      }
    }

    return segments;
  }
}

@immutable
class _MarkdownPretextMeasuredSegment {
  const _MarkdownPretextMeasuredSegment({
    required this.displayText,
    required this.kind,
    required this.width,
    required this.style,
    required this.startOffset,
    required this.endOffset,
    this.mouseCursor,
    this.recognizer,
    this.renderSpan,
    this.estimatedLineHeight,
    this.decoration,
    this.startsDecoratedChunk = false,
    this.endsDecoratedChunk = false,
  });

  final String displayText;
  final pretext_segment.SegmentKind kind;
  final double width;
  final TextStyle style;
  final MouseCursor? mouseCursor;
  final GestureRecognizer? recognizer;
  final InlineSpan? renderSpan;
  final double? estimatedLineHeight;
  final MarkdownPretextInlineDecoration? decoration;
  final int startOffset;
  final int endOffset;
  final bool startsDecoratedChunk;
  final bool endsDecoratedChunk;
}

@immutable
class _MarkdownPretextLineFragment {
  const _MarkdownPretextLineFragment({
    required this.text,
    required this.style,
    required this.mouseCursor,
    required this.recognizer,
    required this.renderSpan,
    required this.decoration,
    required this.estimatedWidth,
    required this.estimatedLineHeight,
    required this.padding,
    required this.startOffset,
    required this.endOffset,
    required this.startsDecoratedChunk,
    required this.endsDecoratedChunk,
  });

  final String text;
  final TextStyle style;
  final MouseCursor? mouseCursor;
  final GestureRecognizer? recognizer;
  final InlineSpan? renderSpan;
  final MarkdownPretextInlineDecoration? decoration;
  final double? estimatedWidth;
  final double? estimatedLineHeight;
  final EdgeInsets padding;
  final int startOffset;
  final int endOffset;
  final bool startsDecoratedChunk;
  final bool endsDecoratedChunk;

  _MarkdownPretextLineFragment copyWith({
    MarkdownPretextInlineDecoration? decoration,
    EdgeInsets? padding,
  }) {
    return _MarkdownPretextLineFragment(
      text: text,
      style: style,
      mouseCursor: mouseCursor,
      recognizer: recognizer,
      renderSpan: renderSpan,
      decoration: decoration ?? this.decoration,
      estimatedWidth: estimatedWidth,
      estimatedLineHeight: estimatedLineHeight,
      padding: padding ?? this.padding,
      startOffset: startOffset,
      endOffset: endOffset,
      startsDecoratedChunk: startsDecoratedChunk,
      endsDecoratedChunk: endsDecoratedChunk,
    );
  }
}

class _TextPainterSegmentMeasurer {
  final Map<Object, double> _cache = <Object, double>{};
  final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );

  double measure(
    String segment,
    TextStyle style,
    double textScaleFactor, {
    EdgeInsets? padding,
  }) {
    final key = Object.hash(segment, style, textScaleFactor, padding);
    return _cache.putIfAbsent(key, () {
      _textPainter.text = TextSpan(text: segment, style: style);
      _textPainter.textScaler = TextScaler.linear(textScaleFactor);
      _textPainter.layout(maxWidth: double.infinity);
      return _textPainter.width + (padding?.horizontal ?? 0);
    });
  }
}

double _measureInlineTextWidth(
  String text,
  TextStyle style, {
  required TextDirection textDirection,
}) {
  if (text.isEmpty) {
    return 0;
  }
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  return textPainter.width;
}

int _resolveTextOffsetForSegment(
  String text,
  TextStyle style,
  double dx, {
  required TextDirection textDirection,
}) {
  if (text.isEmpty) {
    return 0;
  }
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  final position = textPainter.getPositionForOffset(
    Offset(dx.clamp(0.0, math.max(textPainter.width, 0.0)), 0),
  );
  return position.offset.clamp(0, text.length);
}
