import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/document.dart';

enum SelectableBlockHitTestBehavior {
  text,
  block,
}

enum SelectableBlockSelectionPaintOrder {
  behindChild,
  aboveChild,
}

@immutable
class SelectableBlockSpec {
  const SelectableBlockSpec({
    required this.child,
    required this.plainText,
    required this.hitTestBehavior,
    this.textSpan,
    this.textAlign = TextAlign.start,
    this.measurementPadding = EdgeInsets.zero,
    this.highlightBorderRadius,
    this.selectionRectResolver,
    this.textOffsetResolver,
    this.selectionPaintOrder = SelectableBlockSelectionPaintOrder.behindChild,
    this.selectionColor,
  });

  final Widget child;
  final String plainText;
  final SelectableBlockHitTestBehavior hitTestBehavior;
  final InlineSpan? textSpan;
  final TextAlign textAlign;
  final EdgeInsets measurementPadding;
  final BorderRadius? highlightBorderRadius;
  final List<Rect> Function(
    BuildContext context,
    Size constraints,
    DocumentRange range,
  )? selectionRectResolver;
  final int? Function(
    BuildContext context,
    Size size,
    Offset localPosition,
  )? textOffsetResolver;
  final SelectableBlockSelectionPaintOrder selectionPaintOrder;
  final Color? selectionColor;
}

class SelectableMarkdownBlock extends StatefulWidget {
  const SelectableMarkdownBlock({
    super.key,
    required this.blockIndex,
    required this.spec,
    required this.selectionColor,
    this.selectionRange,
  });

  final int blockIndex;
  final SelectableBlockSpec spec;
  final Color selectionColor;
  final DocumentRange? selectionRange;

  @override
  State<SelectableMarkdownBlock> createState() =>
      SelectableMarkdownBlockState();
}

class SelectableMarkdownBlockState extends State<SelectableMarkdownBlock> {
  Rect? get globalRect {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  bool containsGlobal(Offset globalPosition) {
    final rect = globalRect;
    return rect != null && rect.contains(globalPosition);
  }

  String get plainText => widget.spec.plainText;

  int get textLength => widget.spec.plainText.length;

  DocumentSelection selectWholeBlock() {
    return DocumentSelection(
      base: DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: 0,
      ),
      extent: DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: textLength,
      ),
    );
  }

  DocumentSelection selectWord(DocumentPosition position) {
    if (widget.spec.hitTestBehavior == SelectableBlockHitTestBehavior.block ||
        widget.spec.plainText.isEmpty) {
      return selectWholeBlock();
    }
    var start = position.textOffset < 0
        ? 0
        : position.textOffset > widget.spec.plainText.length
            ? widget.spec.plainText.length
            : position.textOffset;
    var end = start;

    while (start > 0 && _isWordCharacter(widget.spec.plainText[start - 1])) {
      start -= 1;
    }
    while (end < widget.spec.plainText.length &&
        _isWordCharacter(widget.spec.plainText[end])) {
      end += 1;
    }

    if (start == end && widget.spec.plainText.isNotEmpty) {
      if (end < widget.spec.plainText.length) {
        end += 1;
      } else if (start > 0) {
        start -= 1;
      }
    }

    return DocumentSelection(
      base: DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: start,
      ),
      extent: DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: end,
      ),
    );
  }

  DocumentPosition? hitTestGlobal(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    if (!(Offset.zero & renderObject.size).contains(localPosition)) {
      return null;
    }
    return _hitTestLocal(localPosition, renderObject.size);
  }

  DocumentPosition boundaryPositionForGlobal(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: 0,
      );
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    final bool preferEnd = localPosition.dy > renderObject.size.height / 2 ||
        localPosition.dx > renderObject.size.width / 2;
    if ((Offset.zero & renderObject.size).contains(localPosition)) {
      return _hitTestLocal(localPosition, renderObject.size) ??
          _edgePosition(preferEnd: preferEnd);
    }
    if (localPosition.dy < 0 || localPosition.dx < 0) {
      return _edgePosition(preferEnd: false);
    }
    return _edgePosition(preferEnd: true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final range = _selectionForBlock();
        final selectionRects = range == null
            ? null
            : widget.spec.selectionRectResolver?.call(
                context,
                constraints.biggest,
                range,
              );
        final selectionPainter = _BlockSelectionPainter(
          range: range,
          spec: widget.spec,
          selectionColor: widget.spec.selectionColor ?? widget.selectionColor,
          textDirection: Directionality.of(context),
          selectionRects: selectionRects,
        );
        return CustomPaint(
          painter: widget.spec.selectionPaintOrder ==
                  SelectableBlockSelectionPaintOrder.behindChild
              ? selectionPainter
              : null,
          foregroundPainter: widget.spec.selectionPaintOrder ==
                  SelectableBlockSelectionPaintOrder.aboveChild
              ? selectionPainter
              : null,
          child: widget.spec.child,
        );
      },
    );
  }

  DocumentPosition? _hitTestLocal(Offset localPosition, Size size) {
    if (widget.spec.plainText.isEmpty) {
      return DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: 0,
      );
    }

    final resolvedOffset = widget.spec.textOffsetResolver?.call(
      context,
      size,
      localPosition,
    );
    if (resolvedOffset != null) {
      final textOffset = resolvedOffset < 0
          ? 0
          : resolvedOffset > widget.spec.plainText.length
              ? widget.spec.plainText.length
              : resolvedOffset;
      return DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: textOffset,
      );
    }

    if (widget.spec.hitTestBehavior == SelectableBlockHitTestBehavior.block ||
        widget.spec.textSpan == null) {
      return _edgePosition(
        preferEnd: localPosition.dy > size.height / 2 ||
            localPosition.dx > size.width / 2,
      );
    }

    final textPainter = _buildTextPainter(size, Directionality.of(context));
    final contentOffset = Offset(
      widget.spec.measurementPadding.left,
      widget.spec.measurementPadding.top,
    );
    final clampedOffset = Offset(
      (localPosition.dx - contentOffset.dx)
          .clamp(0.0, math.max(textPainter.width, 0.0)),
      (localPosition.dy - contentOffset.dy)
          .clamp(0.0, math.max(textPainter.height, 0.0)),
    );
    final position = textPainter.getPositionForOffset(clampedOffset);
    final textOffset = position.offset < 0
        ? 0
        : position.offset > widget.spec.plainText.length
            ? widget.spec.plainText.length
            : position.offset;
    return DocumentPosition(
      blockIndex: widget.blockIndex,
      path: const PathInBlock(<int>[0]),
      textOffset: textOffset,
    );
  }

  DocumentRange? _selectionForBlock() {
    final range = widget.selectionRange;
    if (range == null) {
      return null;
    }
    if (widget.blockIndex < range.start.blockIndex ||
        widget.blockIndex > range.end.blockIndex) {
      return null;
    }
    final start = widget.blockIndex == range.start.blockIndex
        ? range.start.textOffset
        : 0;
    final end = widget.blockIndex == range.end.blockIndex
        ? range.end.textOffset
        : widget.spec.plainText.length;
    if (start >= end) {
      return null;
    }
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: start,
      ),
      end: DocumentPosition(
        blockIndex: widget.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: end,
      ),
    );
  }

  DocumentPosition _edgePosition({required bool preferEnd}) {
    return DocumentPosition(
      blockIndex: widget.blockIndex,
      path: const PathInBlock(<int>[0]),
      textOffset: preferEnd ? textLength : 0,
    );
  }

  TextPainter _buildTextPainter(Size size, TextDirection textDirection) {
    final textPainter = TextPainter(
      text: widget.spec.textSpan,
      textAlign: widget.spec.textAlign,
      textDirection: textDirection,
      maxLines: null,
    );
    final maxWidth = math
        .max(
          size.width - widget.spec.measurementPadding.horizontal,
          0,
        )
        .toDouble();
    textPainter.layout(maxWidth: maxWidth);
    return textPainter;
  }

  bool _isWordCharacter(String character) {
    if (character.trim().isEmpty) {
      return false;
    }
    const separators = <String>{
      '.',
      ',',
      ';',
      ':',
      '!',
      '?',
      '(',
      ')',
      '[',
      ']',
      '{',
      '}',
      '<',
      '>',
      '/',
      '\\',
      '"',
      '\'',
      '`',
      '|',
      '-',
      '+',
      '=',
      '*',
      '&',
    };
    return !separators.contains(character);
  }
}

class _BlockSelectionPainter extends CustomPainter {
  const _BlockSelectionPainter({
    required this.range,
    required this.spec,
    required this.selectionColor,
    required this.textDirection,
    this.selectionRects,
  });

  final DocumentRange? range;
  final SelectableBlockSpec spec;
  final Color selectionColor;
  final TextDirection textDirection;
  final List<Rect>? selectionRects;

  @override
  void paint(Canvas canvas, Size size) {
    final range = this.range;
    if (range == null) {
      return;
    }
    final paint = Paint()..color = selectionColor;

    final selectionRects = this.selectionRects;
    if (selectionRects != null) {
      _paintSelectionRects(canvas, paint, selectionRects);
      return;
    }

    if (spec.hitTestBehavior == SelectableBlockHitTestBehavior.text &&
        spec.textSpan != null) {
      final textPainter = TextPainter(
        text: spec.textSpan,
        textAlign: spec.textAlign,
        textDirection: textDirection,
        maxLines: null,
      )..layout(
          maxWidth:
              math.max(size.width - spec.measurementPadding.horizontal, 0),
        );
      final textSelection = TextSelection(
        baseOffset: range.start.textOffset,
        extentOffset: range.end.textOffset,
      );
      final boxes = _mergeSelectionBoxes(
        textPainter.getBoxesForSelection(textSelection),
      );
      _paintSelectionRects(
        canvas,
        paint,
        boxes
            .map(
              (box) => Rect.fromLTRB(
                box.left + spec.measurementPadding.left - 1.5,
                box.top + spec.measurementPadding.top,
                box.right + spec.measurementPadding.left + 1.5,
                box.bottom + spec.measurementPadding.top,
              ),
            )
            .toList(growable: false),
      );
      return;
    }

    final borderRadius =
        spec.highlightBorderRadius ?? BorderRadius.circular(12);
    canvas.drawRRect(borderRadius.toRRect(Offset.zero & size), paint);
  }

  @override
  bool shouldRepaint(covariant _BlockSelectionPainter oldDelegate) {
    return oldDelegate.range != range ||
        oldDelegate.spec != spec ||
        oldDelegate.selectionColor != selectionColor ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.selectionRects != selectionRects;
  }

  void _paintSelectionRects(Canvas canvas, Paint paint, List<Rect> rects) {
    if (rects.isEmpty) {
      return;
    }

    final normalizedRects = rects.toList(growable: false)
      ..sort((a, b) {
        final topComparison = a.top.compareTo(b.top);
        if (topComparison != 0) {
          return topComparison;
        }
        return a.left.compareTo(b.left);
      });

    canvas.saveLayer(null, Paint());
    for (var index = 0; index < normalizedRects.length; index++) {
      canvas.drawRRect(
        _selectionRRectForIndex(normalizedRects, index),
        paint,
      );
    }
    _fillInnerCornerTransitions(canvas, normalizedRects, paint);
    canvas.restore();
  }

  RRect _selectionRRectForIndex(List<Rect> rects, int index) {
    const radius = Radius.circular(4);
    final rect = rects[index];

    final topLeftRounded = !_hasVerticalNeighborForCorner(
      rects,
      index,
      lookAbove: true,
      isLeftCorner: true,
    );
    final topRightRounded = !_hasVerticalNeighborForCorner(
      rects,
      index,
      lookAbove: true,
      isLeftCorner: false,
    );
    final bottomLeftRounded = !_hasVerticalNeighborForCorner(
      rects,
      index,
      lookAbove: false,
      isLeftCorner: true,
    );
    final bottomRightRounded = !_hasVerticalNeighborForCorner(
      rects,
      index,
      lookAbove: false,
      isLeftCorner: false,
    );

    return RRect.fromRectAndCorners(
      rect,
      topLeft: topLeftRounded ? radius : Radius.zero,
      topRight: topRightRounded ? radius : Radius.zero,
      bottomLeft: bottomLeftRounded ? radius : Radius.zero,
      bottomRight: bottomRightRounded ? radius : Radius.zero,
    );
  }

  bool _hasVerticalNeighborForCorner(
    List<Rect> rects,
    int index, {
    required bool lookAbove,
    required bool isLeftCorner,
  }) {
    const verticalTolerance = 2.0;
    const horizontalTolerance = 0.5;

    final target = rects[index];
    final testRadius = math.min(4.0, target.width / 2.0);

    for (var otherIndex = 0; otherIndex < rects.length; otherIndex++) {
      if (otherIndex == index) {
        continue;
      }

      final other = rects[otherIndex];
      final verticalGap = lookAbove
          ? (target.top - other.bottom).abs()
          : (other.top - target.bottom).abs();
      if (verticalGap > verticalTolerance) {
        continue;
      }

      if (lookAbove
          ? other.bottom > target.top + verticalTolerance
          : other.top < target.bottom - verticalTolerance) {
        continue;
      }

      if (isLeftCorner) {
        final isFlushLeft =
            (other.left - target.left).abs() <= horizontalTolerance;
        if (isFlushLeft) {
          return true;
        }
        if (other.right >= target.left + testRadius - horizontalTolerance &&
            other.left <= target.left + testRadius + horizontalTolerance) {
          return true;
        }
      } else {
        final isFlushRight =
            (other.right - target.right).abs() <= horizontalTolerance;
        if (isFlushRight) {
          return true;
        }
        if (other.left <= target.right - testRadius + horizontalTolerance &&
            other.right >= target.right - testRadius - horizontalTolerance) {
          return true;
        }
      }
    }
    return false;
  }

  void _fillInnerCornerTransitions(
    Canvas canvas,
    List<Rect> rects,
    Paint paint,
  ) {
    const sameLineTolerance = 2.0;
    const seamTolerance = 2.0;
    const maxRadius = 4.0;

    for (var index = 0; index < rects.length - 1; index++) {
      final current = rects[index];
      final next = rects[index + 1];
      if ((next.top - current.top).abs() <= sameLineTolerance) {
        continue;
      }

      final seamGap = next.top - current.bottom;
      if (seamGap.abs() > seamTolerance) {
        continue;
      }

      if (current.right <= next.left + 0.5 ||
          next.right <= current.left + 0.5) {
        continue;
      }

      if (next.left >= current.left + maxRadius * 2) {
        _fillQuarterTransition(
          canvas,
          paint,
          corner: Offset(next.left, current.bottom),
          radius: maxRadius,
          quadrant: _SelectionCornerQuadrant.bottomLeft,
        );
      } else if (current.left >= next.left + maxRadius * 2) {
        _fillQuarterTransition(
          canvas,
          paint,
          corner: Offset(current.left, next.top),
          radius: maxRadius,
          quadrant: _SelectionCornerQuadrant.topLeft,
        );
      }

      if (current.right >= next.right + maxRadius * 2) {
        _fillQuarterTransition(
          canvas,
          paint,
          corner: Offset(next.right, current.bottom),
          radius: maxRadius,
          quadrant: _SelectionCornerQuadrant.bottomRight,
        );
      } else if (next.right >= current.right + maxRadius * 2) {
        _fillQuarterTransition(
          canvas,
          paint,
          corner: Offset(current.right, next.top),
          radius: maxRadius,
          quadrant: _SelectionCornerQuadrant.topRight,
        );
      }
    }
  }

  void _fillQuarterTransition(
    Canvas canvas,
    Paint paint, {
    required Offset corner,
    required double radius,
    required _SelectionCornerQuadrant quadrant,
  }) {
    if (radius <= 0.5) {
      return;
    }

    final squareRect = switch (quadrant) {
      _SelectionCornerQuadrant.topLeft => Rect.fromLTRB(
          corner.dx - radius,
          corner.dy - radius,
          corner.dx,
          corner.dy,
        ),
      _SelectionCornerQuadrant.topRight => Rect.fromLTRB(
          corner.dx,
          corner.dy - radius,
          corner.dx + radius,
          corner.dy,
        ),
      _SelectionCornerQuadrant.bottomLeft => Rect.fromLTRB(
          corner.dx - radius,
          corner.dy,
          corner.dx,
          corner.dy + radius,
        ),
      _SelectionCornerQuadrant.bottomRight => Rect.fromLTRB(
          corner.dx,
          corner.dy,
          corner.dx + radius,
          corner.dy + radius,
        ),
    };
    // Circle centered at the far corner of squareRect (opposite to corner)
    final center = switch (quadrant) {
      _SelectionCornerQuadrant.topLeft =>
        Offset(corner.dx - radius, corner.dy - radius),
      _SelectionCornerQuadrant.topRight =>
        Offset(corner.dx + radius, corner.dy - radius),
      _SelectionCornerQuadrant.bottomLeft =>
        Offset(corner.dx - radius, corner.dy + radius),
      _SelectionCornerQuadrant.bottomRight =>
        Offset(corner.dx + radius, corner.dy + radius),
    };
    final oval = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final clip = Path()..addRect(squareRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, clip, oval),
      paint,
    );
  }

  List<TextBox> _mergeSelectionBoxes(List<TextBox> boxes) {
    if (boxes.length < 2) {
      return boxes;
    }

    const lineTolerance = 2.0;
    const gapTolerance = double.infinity;

    final sorted = boxes.toList()
      ..sort((a, b) {
        final topComparison = a.top.compareTo(b.top);
        if (topComparison != 0) {
          return topComparison;
        }
        return a.left.compareTo(b.left);
      });

    final merged = <TextBox>[];
    var current = sorted.first;

    for (final next in sorted.skip(1)) {
      final sameLine = (next.top - current.top).abs() <= lineTolerance &&
          (next.bottom - current.bottom).abs() <= lineTolerance;
      final horizontalGap = next.left - current.right;
      if (sameLine && horizontalGap <= gapTolerance) {
        current = TextBox.fromLTRBD(
          math.min(current.left, next.left),
          math.min(current.top, next.top),
          math.max(current.right, next.right),
          math.max(current.bottom, next.bottom),
          current.direction,
        );
        continue;
      }
      merged.add(current);
      current = next;
    }

    merged.add(current);
    return merged;
  }
}

enum _SelectionCornerQuadrant {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}
