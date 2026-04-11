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
  });

  final String text;
  final TextStyle style;
  final MouseCursor? mouseCursor;
  final GestureRecognizer? recognizer;
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
    runs.isEmpty ? <TextStyle>[fallbackStyle] : runs.map((run) => run.style),
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
  final result = layoutWithLines(prepared, safeMaxWidth, lineHeight);

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

      final textPainter = _buildLinePainter(line.span, textDirection);
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(
          baseOffset: selectionStart - line.startOffset,
          extentOffset: selectionEnd - line.startOffset,
        ),
      );
      final lineTop = lineIndex * lineHeight;
      for (final box in boxes) {
        rects.add(
          Rect.fromLTRB(
            box.left + line.leadingOffset,
            box.top + lineTop,
            box.right + line.leadingOffset,
            box.bottom + lineTop,
          ).inflate(1.5),
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

    final textPainter = _buildLinePainter(line.span, textDirection);
    final lineTop = clampedLineIndex * lineHeight;
    final clampedOffset = Offset(
      (localPosition.dx - line.leadingOffset)
          .clamp(0.0, math.max(textPainter.width, 0.0)),
      (localPosition.dy - lineTop)
          .clamp(0.0, math.max(textPainter.height, 0.0)),
    );
    final textPosition = textPainter.getPositionForOffset(clampedOffset);
    final offsetInLine = textPosition.offset.clamp(0, line.text.length);
    return line.startOffset + offsetInLine;
  }

  TextPainter _buildLinePainter(
    InlineSpan span,
    TextDirection textDirection,
  ) {
    final textPainter = TextPainter(
      text: span,
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
      maxLines: 1,
    );
    textPainter.layout(maxWidth: double.infinity);
    return textPainter;
  }
}

@immutable
class MarkdownPretextLayoutLine {
  const MarkdownPretextLayoutLine({
    required this.text,
    required this.span,
    required this.width,
    required this.leadingOffset,
    required this.startOffset,
    required this.endOffset,
    required this.visibleEndOffset,
  });

  final String text;
  final InlineSpan span;
  final double width;
  final double leadingOffset;
  final int startOffset;
  final int endOffset;
  final int visibleEndOffset;
}

InlineSpan _buildFullSpan({
  required List<MarkdownPretextInlineRun> runs,
  required TextStyle fallbackStyle,
}) {
  return TextSpan(
    style: fallbackStyle,
    children: <InlineSpan>[
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: run.style,
          mouseCursor: run.mouseCursor,
          recognizer: run.recognizer,
        ),
    ],
  );
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
}) {
  if (visibleTextLength <= 0) {
    return TextSpan(style: fallbackStyle, text: ' ');
  }

  final children = <InlineSpan>[];
  var remaining = visibleTextLength;
  for (var index = startSegmentIndex;
      index < endSegmentIndex && remaining > 0;
      index++) {
    final segment = segments[index];
    if (segment.kind == pretext_segment.SegmentKind.hardBreak) {
      continue;
    }
    if (segment.displayText.isEmpty) {
      continue;
    }
    final takeLength = math.min(segment.displayText.length, remaining);
    if (takeLength <= 0) {
      continue;
    }
    children.add(segment.toInlineSpan(takeLength: takeLength));
    remaining -= takeLength;
  }

  if (children.isEmpty) {
    return TextSpan(style: fallbackStyle, text: ' ');
  }
  return TextSpan(style: fallbackStyle, children: children);
}

double _measureMaxLineHeight(
  Iterable<TextStyle> styles,
  double textScaleFactor,
) {
  var lineHeight = 0.0;
  for (final style in styles) {
    final measured = _measureLineHeight(style, textScaleFactor);
    if (measured > lineHeight) {
      lineHeight = measured;
    }
  }
  return lineHeight;
}

double _measureLineHeight(TextStyle style, double textScaleFactor) {
  final textPainter = TextPainter(
    text: TextSpan(text: ' ', style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(textScaleFactor),
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  return textPainter.preferredLineHeight;
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
              startOffset: plainTextOffset,
              endOffset: plainTextOffset + 1,
            ),
          );
          index += 1;
          plainTextOffset += 1;
          continue;
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
            ),
            style: run.style,
            mouseCursor: run.mouseCursor,
            recognizer: run.recognizer,
            startOffset: startOffset,
            endOffset: plainTextOffset,
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
  });

  final String displayText;
  final pretext_segment.SegmentKind kind;
  final double width;
  final TextStyle style;
  final MouseCursor? mouseCursor;
  final GestureRecognizer? recognizer;
  final int startOffset;
  final int endOffset;

  InlineSpan toInlineSpan({int? takeLength}) {
    final text = takeLength == null || takeLength >= displayText.length
        ? displayText
        : displayText.substring(0, takeLength);
    return TextSpan(
      text: text,
      style: style,
      mouseCursor: mouseCursor,
      recognizer: recognizer,
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
    double textScaleFactor,
  ) {
    final key = Object.hash(segment, style, textScaleFactor);
    return _cache.putIfAbsent(key, () {
      _textPainter.text = TextSpan(text: segment, style: style);
      _textPainter.textScaler = TextScaler.linear(textScaleFactor);
      _textPainter.layout(maxWidth: double.infinity);
      return _textPainter.width;
    });
  }
}
