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
  });

  final String text;
  final TextStyle style;
  final MouseCursor? mouseCursor;
  final GestureRecognizer? recognizer;
  final MarkdownPretextInlineDecoration? decoration;
  final bool allowCharacterWrap;
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
  })  : runs = null,
        fallbackStyle = style;

  const MarkdownPretextTextBlock.rich({
    super.key,
    required this.runs,
    required this.fallbackStyle,
    this.textAlign = TextAlign.start,
    this.intrinsicWidthSafe = false,
  })  : text = '',
        style = fallbackStyle;

  final String text;
  final TextStyle style;
  final List<MarkdownPretextInlineRun>? runs;
  final TextStyle fallbackStyle;
  final TextAlign textAlign;
  final bool intrinsicWidthSafe;

  @override
  Widget build(BuildContext context) {
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final textDirection = Directionality.of(context);
    if (intrinsicWidthSafe) {
      return Text.rich(
        _buildFullSpan(
          runs: runs ??
              <MarkdownPretextInlineRun>[
                MarkdownPretextInlineRun(text: text, style: style),
              ],
          fallbackStyle: fallbackStyle,
        ),
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
                height: constrainedLayout.lineHeight,
                child: Padding(
                  padding: EdgeInsets.only(left: line.leadingOffset),
                  child: Text.rich(
                    line.span,
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
        (current, run) => math.max(
          current,
          run.decoration!.padding.horizontal,
        ),
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
  for (final line in result.lines) {
    final startOffset = cursor;
    final visibleEndOffset = _consumeVisibleText(plainText, cursor, line.text);
    var endOffset = visibleEndOffset;
    while (endOffset < plainText.length && plainText[endOffset] == ' ') {
      endOffset += 1;
    }
    if (endOffset < plainText.length && plainText[endOffset] == '\n') {
      endOffset += 1;
    }
    lines.add(
      MarkdownPretextLayoutLine(
        text: line.text,
        span: _buildLineSpan(
          segments: segments,
          startSegmentIndex: line.start.segmentIndex,
          endSegmentIndex: line.end.segmentIndex,
          visibleTextLength: line.text.length,
          fallbackStyle: fallbackStyle,
          maxRenderedWidth: safeMaxWidth,
          textScaleFactor: textScaleFactor,
        ),
        segments: _buildLineSegments(
          segments: segments,
          startSegmentIndex: line.start.segmentIndex,
          endSegmentIndex: line.end.segmentIndex,
          visibleTextLength: line.text.length,
          maxRenderedWidth: safeMaxWidth,
          textScaleFactor: textScaleFactor,
        ),
        width: line.width,
        leadingOffset: _resolveLineLeadingOffset(
          lineWidth: line.width,
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
  }

  return MarkdownPretextLayoutResult(
    plainText: plainText,
    lines: List<MarkdownPretextLayoutLine>.unmodifiable(lines),
    lineHeight: lineHeight,
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
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final selectionStart = math.max(range.start.textOffset, line.startOffset);
      final selectionEnd =
          math.min(range.end.textOffset, line.visibleEndOffset);
      if (selectionStart >= selectionEnd || line.text.isEmpty) {
        continue;
      }

      final lineTop = lineIndex * lineHeight;
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
    return rects;
  }

  int textOffsetAt(
    Offset localPosition, {
    required TextDirection textDirection,
  }) {
    if (lines.isEmpty) {
      return 0;
    }

    final clampedLineIndex =
        (localPosition.dy / lineHeight).floor().clamp(0, lines.length - 1);
    final line = lines[clampedLineIndex];
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
          right + line.leadingOffset, lineTop + lineHeight);
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
    required this.leadingOffset,
    required this.startOffset,
    required this.endOffset,
    required this.visibleEndOffset,
  });

  final String text;
  final InlineSpan span;
  final List<MarkdownPretextLayoutSegment> segments;
  final double width;
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
    this.decoration,
    this.padding = EdgeInsets.zero,
  });

  final String text;
  final TextStyle style;
  final int startOffset;
  final int endOffset;
  final double left;
  final double right;
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
        if (run.decoration == null)
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

class _DecoratedInlineText extends StatelessWidget {
  const _DecoratedInlineText({
    required this.text,
    required this.style,
    required this.decoration,
  });

  final String text;
  final TextStyle style;
  final MarkdownPretextInlineDecoration decoration;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: decoration.backgroundColor,
        borderRadius: decoration.borderRadius,
      ),
      child: Padding(
        padding: decoration.padding,
        child: Text(text, style: style),
      ),
    );
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

InlineSpan _buildLineSpan({
  required List<_MarkdownPretextMeasuredSegment> segments,
  required int startSegmentIndex,
  required int endSegmentIndex,
  required int visibleTextLength,
  required TextStyle fallbackStyle,
  required double maxRenderedWidth,
  required double textScaleFactor,
}) {
  if (visibleTextLength <= 0) {
    return TextSpan(style: fallbackStyle, text: ' ');
  }

  final children = <InlineSpan>[];
  for (final fragment in _buildLineFragments(
    segments: segments,
    startSegmentIndex: startSegmentIndex,
    endSegmentIndex: endSegmentIndex,
    visibleTextLength: visibleTextLength,
    maxRenderedWidth: maxRenderedWidth,
    textScaleFactor: textScaleFactor,
  )) {
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

List<MarkdownPretextLayoutSegment> _buildLineSegments({
  required List<_MarkdownPretextMeasuredSegment> segments,
  required int startSegmentIndex,
  required int endSegmentIndex,
  required int visibleTextLength,
  required double maxRenderedWidth,
  required double textScaleFactor,
}) {
  final lineSegments = <MarkdownPretextLayoutSegment>[];
  final measurer = _TextPainterSegmentMeasurer();
  var cursor = 0.0;

  for (final fragment in _buildLineFragments(
    segments: segments,
    startSegmentIndex: startSegmentIndex,
    endSegmentIndex: endSegmentIndex,
    visibleTextLength: visibleTextLength,
    maxRenderedWidth: maxRenderedWidth,
    textScaleFactor: textScaleFactor,
  )) {
    final width = measurer.measure(
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
        decoration: fragment.decoration,
        padding: fragment.padding,
      ),
    );
    cursor += width;
  }

  return List<MarkdownPretextLayoutSegment>.unmodifiable(lineSegments);
}

List<_MarkdownPretextLineFragment> _buildLineFragments({
  required List<_MarkdownPretextMeasuredSegment> segments,
  required int startSegmentIndex,
  required int endSegmentIndex,
  required int visibleTextLength,
  required double maxRenderedWidth,
  required double textScaleFactor,
}) {
  final fragments = <_MarkdownPretextLineFragment>[];
  var remaining = visibleTextLength;

  for (var index = startSegmentIndex;
      index < endSegmentIndex && remaining > 0;
      index++) {
    final segment = segments[index];
    if (segment.kind == pretext_segment.SegmentKind.hardBreak ||
        segment.displayText.isEmpty) {
      continue;
    }
    final takeLength = math.min(segment.displayText.length, remaining);
    if (takeLength <= 0) {
      continue;
    }
    final text = takeLength == segment.displayText.length
        ? segment.displayText
        : segment.displayText.substring(0, takeLength);
    final startOffset = segment.startOffset;
    final endOffset = segment.startOffset + text.length;
    fragments.add(
      _MarkdownPretextLineFragment(
        text: text,
        style: segment.style,
        mouseCursor: segment.mouseCursor,
        recognizer: segment.recognizer,
        decoration: segment.decoration,
        padding: _paddingForDecoratedFragment(segment),
        startOffset: startOffset,
        endOffset: endOffset,
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

EdgeInsets _paddingForDecoratedFragment(
    _MarkdownPretextMeasuredSegment segment) {
  final decoration = segment.decoration;
  if (decoration == null) {
    return EdgeInsets.zero;
  }
  return EdgeInsets.only(
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
        measurer.measure(fragment.text, fragment.style, textScaleFactor),
  );
  final horizontalPaddingBudget = math.max(maxRenderedWidth - baseWidth, 0.0);
  final desiredHorizontalPadding =
      fragments.fold<double>(0, (current, fragment) {
    final decoration = fragment.decoration;
    if (decoration == null) {
      return current;
    }
    return current + decoration.padding.left + decoration.padding.right;
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
            left:
                isFirst ? decoration.padding.left * horizontalPaddingScale : 0,
            right:
                isLast ? decoration.padding.right * horizontalPaddingScale : 0,
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
    final measured = _measureLineHeight(
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
  final textPainter = TextPainter(
    text: TextSpan(text: ' ', style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(textScaleFactor),
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  return textPainter.preferredLineHeight + (padding?.vertical ?? 0);
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
    required this.decoration,
    required this.padding,
    required this.startOffset,
    required this.endOffset,
  });

  final String text;
  final TextStyle style;
  final MouseCursor? mouseCursor;
  final GestureRecognizer? recognizer;
  final MarkdownPretextInlineDecoration? decoration;
  final EdgeInsets padding;
  final int startOffset;
  final int endOffset;

  _MarkdownPretextLineFragment copyWith({
    MarkdownPretextInlineDecoration? decoration,
    EdgeInsets? padding,
  }) {
    return _MarkdownPretextLineFragment(
      text: text,
      style: style,
      mouseCursor: mouseCursor,
      recognizer: recognizer,
      decoration: decoration ?? this.decoration,
      padding: padding ?? this.padding,
      startOffset: startOffset,
      endOffset: endOffset,
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
