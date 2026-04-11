import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pretext/pretext.dart';

import '../core/document.dart';

class MarkdownPretextTextBlock extends StatelessWidget {
  const MarkdownPretextTextBlock({
    super.key,
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final textScaleFactor = textScaler.scale(1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = computeMarkdownPretextLayout(
          text: text,
          style: style,
          maxWidth: constraints.maxWidth,
          textScaleFactor: textScaleFactor,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final line in layout.lines)
              SizedBox(
                width: double.infinity,
                height: layout.lineHeight,
                child: Text(
                  line.text.isEmpty ? ' ' : line.text,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  textScaler: textScaler,
                ),
              ),
          ],
        );
      },
    );
  }
}

MarkdownPretextLayoutResult computeMarkdownPretextLayout({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double textScaleFactor,
}) {
  final lineHeight = _measureLineHeight(style, textScaleFactor);
  if (text.isEmpty) {
    return MarkdownPretextLayoutResult(
      lines: const <MarkdownPretextLayoutLine>[],
      lineHeight: lineHeight,
    );
  }

  final safeMaxWidth = maxWidth.isFinite ? math.max(maxWidth, 0.0) : 100000.0;
  final measurer = _TextPainterSegmentMeasurer(
    style,
    textScaleFactor: textScaleFactor,
  );
  final prepared = prepareWithSegments(
    text,
    measurer.measure,
    whiteSpace: WhiteSpace.preWrap,
  );
  final result = layoutWithLines(
    prepared,
    safeMaxWidth,
    lineHeight,
  );

  final lines = <MarkdownPretextLayoutLine>[];
  var cursor = 0;
  for (final line in result.lines) {
    final startOffset = cursor;
    final visibleEndOffset = _consumeVisibleText(text, cursor, line.text);
    var endOffset = visibleEndOffset;
    while (endOffset < text.length && text[endOffset] == ' ') {
      endOffset += 1;
    }
    if (endOffset < text.length && text[endOffset] == '\n') {
      endOffset += 1;
    }
    lines.add(
      MarkdownPretextLayoutLine(
        text: line.text,
        width: line.width,
        startOffset: startOffset,
        endOffset: endOffset,
        visibleEndOffset: visibleEndOffset,
      ),
    );
    cursor = endOffset;
  }

  return MarkdownPretextLayoutResult(
    lines: List<MarkdownPretextLayoutLine>.unmodifiable(lines),
    lineHeight: lineHeight,
  );
}

@immutable
class MarkdownPretextLayoutResult {
  const MarkdownPretextLayoutResult({
    required this.lines,
    required this.lineHeight,
  });

  final List<MarkdownPretextLayoutLine> lines;
  final double lineHeight;

  List<Rect> selectionRectsForRange(
    DocumentRange range, {
    required TextStyle style,
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

      final textPainter = _buildLinePainter(
        line.text,
        style,
        textDirection,
      );
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
            box.left,
            box.top + lineTop,
            box.right,
            box.bottom + lineTop,
          ).inflate(1.5),
        );
      }
    }
    return rects;
  }

  int textOffsetAt(
    Offset localPosition, {
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    if (lines.isEmpty) {
      return 0;
    }

    final clampedLineIndex =
        (localPosition.dy / lineHeight).floor().clamp(0, lines.length - 1);
    final line = lines[clampedLineIndex];
    if (line.text.isEmpty) {
      return localPosition.dx <= 0 ? line.startOffset : line.endOffset;
    }

    final textPainter = _buildLinePainter(line.text, style, textDirection);
    final lineTop = clampedLineIndex * lineHeight;
    final clampedOffset = Offset(
      localPosition.dx.clamp(0.0, math.max(textPainter.width, 0.0)),
      (localPosition.dy - lineTop)
          .clamp(0.0, math.max(textPainter.height, 0.0)),
    );
    final textPosition = textPainter.getPositionForOffset(clampedOffset);
    final offsetInLine = textPosition.offset.clamp(0, line.text.length);
    return line.startOffset + offsetInLine;
  }

  TextPainter _buildLinePainter(
    String text,
    TextStyle style,
    TextDirection textDirection,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
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
    required this.width,
    required this.startOffset,
    required this.endOffset,
    required this.visibleEndOffset,
  });

  final String text;
  final double width;
  final int startOffset;
  final int endOffset;
  final int visibleEndOffset;
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

class _TextPainterSegmentMeasurer {
  _TextPainterSegmentMeasurer(
    this.style, {
    required this.textScaleFactor,
  });

  final TextStyle style;
  final double textScaleFactor;
  final Map<String, double> _cache = <String, double>{};
  final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );

  double measure(String segment) {
    return _cache.putIfAbsent(segment, () {
      _textPainter.text = TextSpan(text: segment, style: style);
      _textPainter.textScaler = TextScaler.linear(textScaleFactor);
      _textPainter.layout(maxWidth: double.infinity);
      return _textPainter.width;
    });
  }
}
