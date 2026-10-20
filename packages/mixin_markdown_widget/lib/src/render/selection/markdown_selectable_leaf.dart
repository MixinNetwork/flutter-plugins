import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../core/document.dart';
import '../pretext_text_block.dart';

/// The boxes a container block needs besides its text leaves.
enum MarkdownSelectionSlotRole {
  /// A child block of a quote, details, or list item, including the spacing
  /// below it.
  child,

  /// A whole list item row: marker, gap, and content.
  listRow,

  /// The content column of a list item, to the right of the marker.
  listContent,
}

/// The leaves and slots rendered inside one selectable block, keyed by their
/// [PathInBlock] in the block's selection structure.
class MarkdownSelectionLeafRegistry {
  final Map<PathInBlock, MarkdownSelectableLeafState> _leaves =
      <PathInBlock, MarkdownSelectableLeafState>{};
  final Map<(PathInBlock, MarkdownSelectionSlotRole),
          _MarkdownSelectionSlotState> _slots =
      <(PathInBlock, MarkdownSelectionSlotRole), _MarkdownSelectionSlotState>{};

  MarkdownSelectableLeafState? leaf(PathInBlock path) => _leaves[path];

  RenderBox? slotBox(PathInBlock path, MarkdownSelectionSlotRole role) {
    return _laidOutBox(_slots[(path, role)]?.context);
  }
}

/// Provides the [MarkdownSelectionLeafRegistry] of the enclosing selectable
/// block to the leaves and slots below it.
class MarkdownSelectionLeafScope extends InheritedWidget {
  const MarkdownSelectionLeafScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final MarkdownSelectionLeafRegistry registry;

  static MarkdownSelectionLeafRegistry? _maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MarkdownSelectionLeafScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(MarkdownSelectionLeafScope oldWidget) {
    return registry != oldWidget.registry;
  }
}

/// A selectable text leaf. It answers its own selection geometry in its box
/// coordinates and in offsets into its own visible text; the enclosing block
/// converts both to block space.
class MarkdownSelectableLeaf extends StatefulWidget {
  const MarkdownSelectableLeaf({
    super.key,
    required this.path,
    required this.geometry,
    required this.child,
  });

  final PathInBlock path;
  final MarkdownLeafGeometry geometry;
  final Widget child;

  @override
  State<MarkdownSelectableLeaf> createState() => MarkdownSelectableLeafState();
}

class MarkdownSelectableLeafState extends State<MarkdownSelectableLeaf> {
  MarkdownSelectionLeafRegistry? _registry;

  /// The laid-out box of the leaf, or null before its first layout.
  RenderBox? get box => _laidOutBox(context);

  /// Selection rects for local offsets [start, end), in leaf coordinates.
  List<Rect> rectsFor(int start, int end) {
    final box = this.box;
    if (box == null || start >= end) {
      return const <Rect>[];
    }
    return widget.geometry.rectsFor(context, box, start, end);
  }

  /// The local offset at [localPosition], in leaf coordinates.
  int offsetAt(Offset localPosition) {
    final box = this.box;
    if (box == null) {
      return 0;
    }
    return widget.geometry.offsetAt(context, box, localPosition);
  }

  /// The local range of the line at [offset], or under [localPosition] when
  /// it is given.
  ({int start, int end})? lineRangeAt(int offset, {Offset? localPosition}) {
    final box = this.box;
    if (box == null) {
      return null;
    }
    return widget.geometry.lineRangeAt(
      context,
      box,
      offset,
      localPosition: localPosition,
    );
  }

  /// The rect that selection rects of this leaf are clipped to, in leaf
  /// coordinates, such as the viewport of a horizontal scroll view.
  Rect? get clipRect {
    final box = this.box;
    return box == null ? null : widget.geometry.clipRect(box);
  }

  /// Whether selecting anywhere in the leaf selects all of it.
  bool get selectsWhole => widget.geometry.selectsWhole;

  /// The leaf origin in the coordinates of [ancestor].
  Offset? originIn(RenderBox ancestor) {
    final box = this.box;
    return box?.localToGlobal(Offset.zero, ancestor: ancestor);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = MarkdownSelectionLeafScope._maybeOf(context);
    if (!identical(registry, _registry)) {
      _unregister(widget.path);
      _registry = registry;
      _registry?._leaves[widget.path] = this;
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownSelectableLeaf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _unregister(oldWidget.path);
      _registry?._leaves[widget.path] = this;
    }
  }

  @override
  void dispose() {
    _unregister(widget.path);
    super.dispose();
  }

  void _unregister(PathInBlock path) {
    final leaves = _registry?._leaves;
    if (leaves != null && identical(leaves[path], this)) {
      leaves.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A structural box of a container block, such as a list item row, that the
/// container geometry reads besides its leaves.
class MarkdownSelectionSlot extends StatefulWidget {
  const MarkdownSelectionSlot({
    super.key,
    required this.path,
    required this.role,
    required this.child,
  });

  final PathInBlock path;
  final MarkdownSelectionSlotRole role;
  final Widget child;

  @override
  State<MarkdownSelectionSlot> createState() => _MarkdownSelectionSlotState();
}

class _MarkdownSelectionSlotState extends State<MarkdownSelectionSlot> {
  MarkdownSelectionLeafRegistry? _registry;

  (PathInBlock, MarkdownSelectionSlotRole) _keyOf(MarkdownSelectionSlot slot) {
    return (slot.path, slot.role);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = MarkdownSelectionLeafScope._maybeOf(context);
    if (!identical(registry, _registry)) {
      _unregister(_keyOf(widget));
      _registry = registry;
      _registry?._slots[_keyOf(widget)] = this;
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownSelectionSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_keyOf(oldWidget) != _keyOf(widget)) {
      _unregister(_keyOf(oldWidget));
      _registry?._slots[_keyOf(widget)] = this;
    }
  }

  @override
  void dispose() {
    _unregister(_keyOf(widget));
    super.dispose();
  }

  void _unregister((PathInBlock, MarkdownSelectionSlotRole) key) {
    final slots = _registry?._slots;
    if (slots != null && identical(slots[key], this)) {
      slots.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

RenderBox? _laidOutBox(BuildContext? context) {
  if (context == null || !context.mounted) {
    return null;
  }
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return null;
  }
  return renderObject;
}

/// How a leaf maps between its local text offsets and its box coordinates.
abstract class MarkdownLeafGeometry {
  const MarkdownLeafGeometry();

  List<Rect> rectsFor(BuildContext context, RenderBox box, int start, int end);

  int offsetAt(BuildContext context, RenderBox box, Offset localPosition);

  ({int start, int end})? lineRangeAt(
    BuildContext context,
    RenderBox box,
    int offset, {
    Offset? localPosition,
  });

  Rect? clipRect(RenderBox box) => null;

  bool get selectsWhole => false;
}

/// A leaf drawn as a box rather than text, such as an image, a thematic
/// break, or a standalone line break. It is selected as a whole.
class MarkdownPlaceholderLeafGeometry extends MarkdownLeafGeometry {
  const MarkdownPlaceholderLeafGeometry({required this.textLength});

  final int textLength;

  @override
  bool get selectsWhole => true;

  @override
  List<Rect> rectsFor(BuildContext context, RenderBox box, int start, int end) {
    final size = box.size;
    return <Rect>[Rect.fromLTRB(-1.5, 0, size.width + 1.5, size.height)];
  }

  @override
  int offsetAt(BuildContext context, RenderBox box, Offset localPosition) {
    final size = box.size;
    final preferEnd =
        localPosition.dy > size.height / 2 || localPosition.dx > size.width / 2;
    return preferEnd ? textLength : 0;
  }

  @override
  ({int start, int end})? lineRangeAt(
    BuildContext context,
    RenderBox box,
    int offset, {
    Offset? localPosition,
  }) {
    return (start: 0, end: textLength);
  }
}

/// A leaf rendered from pretext runs, either as one rich text paragraph or as
/// pretext lines. Paragraph geometry is read from the live [RenderParagraph]
/// whose text matches [runs]; pretext geometry is computed from the runs.
class MarkdownTextLeafGeometry extends MarkdownLeafGeometry {
  MarkdownTextLeafGeometry({
    required this.runs,
    required this.fallbackStyle,
    this.textAlign = TextAlign.start,
    bool? direct,
    this.viewportKey,
  }) : direct = direct ?? markdownPretextCanUseDirectRichTextGeometry(runs);

  final List<MarkdownPretextInlineRun> runs;
  final TextStyle fallbackStyle;
  final TextAlign textAlign;

  /// Whether the leaf renders [runs] as a single rich text paragraph.
  final bool direct;

  /// The viewport of an enclosing horizontal scroll view, if any.
  final GlobalKey? viewportKey;

  late final String _renderText = markdownPretextRenderText(runs);
  late final String _plainText = runs.map((run) => run.text).join();

  @override
  Rect? clipRect(RenderBox box) {
    final viewport = viewportKey?.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return null;
    }
    return box.globalToLocal(viewport.localToGlobal(Offset.zero)) &
        viewport.size;
  }

  @override
  List<Rect> rectsFor(BuildContext context, RenderBox box, int start, int end) {
    final paragraph = _paragraphIn(box);
    if (paragraph != null) {
      final rects = _paragraphRects(box, paragraph, start, end);
      if (rects != null) {
        return rects;
      }
    }
    return _layout(context, box.size.width).selectionRectsForRange(
      _localRange(start, end),
      textDirection: Directionality.of(context),
    );
  }

  @override
  int offsetAt(BuildContext context, RenderBox box, Offset localPosition) {
    final paragraph = _paragraphIn(box);
    if (paragraph != null) {
      final position = paragraph.getPositionForOffset(
        paragraph.globalToLocal(box.localToGlobal(localPosition)),
      );
      return markdownPretextPlainOffsetForRenderOffset(runs, position.offset);
    }
    return _layout(context, box.size.width).textOffsetAt(
      localPosition,
      textDirection: Directionality.of(context),
    );
  }

  @override
  ({int start, int end})? lineRangeAt(
    BuildContext context,
    RenderBox box,
    int offset, {
    Offset? localPosition,
  }) {
    final paragraph = _paragraphIn(box);
    if (paragraph != null) {
      final range = _paragraphLineRange(box, paragraph, offset, localPosition);
      if (range != null) {
        return range;
      }
    }
    final layout = _layout(context, box.size.width);
    return localPosition == null
        ? layout.lineRangeForTextOffset(offset)
        : layout.visualLineRangeForLocalPosition(localPosition) ??
            layout.lineRangeForTextOffset(offset);
  }

  /// Pretext geometry of the runs at [maxWidth], for when no live paragraph
  /// is available.
  MarkdownPretextLayoutResult _layout(BuildContext context, double maxWidth) {
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    return computeMarkdownPretextLayoutFromRuns(
      runs: runs,
      fallbackStyle: fallbackStyle,
      maxWidth: maxWidth,
      textScaleFactor: textScaler.scale(1.0),
      textAlign: textAlign,
      textDirection: Directionality.of(context),
    );
  }

  /// Rects from the pretext layout at [maxWidth], in the coordinates the
  /// runs would be laid out in. Used before the leaf has been laid out.
  List<Rect> layoutRects(
    BuildContext context,
    double maxWidth,
    int start,
    int end,
  ) {
    return _layout(context, maxWidth).selectionRectsForRange(
      _localRange(start, end),
      textDirection: Directionality.of(context),
    );
  }

  int layoutOffsetAt(BuildContext context, double maxWidth, Offset position) {
    return _layout(context, maxWidth).textOffsetAt(
      position,
      textDirection: Directionality.of(context),
    );
  }

  ({int start, int end})? layoutLineRangeAt(
    BuildContext context,
    double maxWidth,
    int offset, {
    Offset? localPosition,
  }) {
    final layout = _layout(context, maxWidth);
    return localPosition == null
        ? layout.lineRangeForTextOffset(offset)
        : layout.visualLineRangeForLocalPosition(localPosition) ??
            layout.lineRangeForTextOffset(offset);
  }

  RenderParagraph? _paragraphIn(RenderBox box) {
    if (!direct) {
      return null;
    }
    RenderParagraph? paragraph;
    void visit(RenderObject node) {
      if (paragraph != null) {
        return;
      }
      if (node is RenderParagraph &&
          node.hasSize &&
          node.text.toPlainText(includePlaceholders: true) == _renderText) {
        paragraph = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(box);
    return paragraph;
  }

  List<Rect>? _paragraphRects(
    RenderBox box,
    RenderParagraph paragraph,
    int start,
    int end,
  ) {
    final renderSelection = TextSelection(
      baseOffset: markdownPretextRenderOffsetForPlainOffset(
        runs,
        start,
        preferEnd: false,
      ),
      extentOffset: markdownPretextRenderOffsetForPlainOffset(
        runs,
        end,
        preferEnd: true,
      ),
    );
    final origin = box.globalToLocal(paragraph.localToGlobal(Offset.zero));
    // The paragraph may not have completed layout in the current frame, for
    // example during scroll-triggered rebuilds.
    final List<TextBox> boxes;
    final List<_LineExtent> lineExtents;
    try {
      lineExtents = _paragraphLineExtents(paragraph);
      boxes = paragraph.getBoxesForSelection(renderSelection);
    } on AssertionError {
      return null;
    }
    return _mergeSameLineBoxes(_normalizeBoxesToLineExtents(boxes, lineExtents))
        .map(
          (box) => Rect.fromLTRB(
            box.left + origin.dx - 1.5,
            box.top + origin.dy,
            box.right + origin.dx + 1.5,
            box.bottom + origin.dy,
          ),
        )
        .toList(growable: false);
  }

  ({int start, int end})? _paragraphLineRange(
    RenderBox box,
    RenderParagraph paragraph,
    int offset,
    Offset? localPosition,
  ) {
    final renderOffset = localPosition == null
        ? markdownPretextRenderOffsetForPlainOffset(
            runs,
            offset,
            preferEnd: false,
          )
        : paragraph
            .getPositionForOffset(
              paragraph.globalToLocal(box.localToGlobal(localPosition)),
            )
            .offset;
    final boundary = _paragraphLineBoundary(paragraph, renderOffset);
    if (boundary == null) {
      return null;
    }
    var start = markdownPretextPlainOffsetForRenderOffset(runs, boundary.start);
    var end = markdownPretextPlainOffsetForRenderOffset(runs, boundary.end);
    if (start < _plainText.length && _plainText.codeUnitAt(start) == 0x0A) {
      start += 1;
    }
    if (end > start &&
        end <= _plainText.length &&
        _plainText.codeUnitAt(end - 1) == 0x0A) {
      end -= 1;
    }
    return (start: start, end: end);
  }

  DocumentRange _localRange(int start, int end) {
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: start,
      ),
      end: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: end,
      ),
    );
  }
}

typedef _LineExtent = ({double top, double bottom});

/// The render-text range of the visual line that contains [renderOffset].
({int start, int end})? _paragraphLineBoundary(
  RenderParagraph paragraph,
  int renderOffset,
) {
  final fullText = paragraph.text.toPlainText(includePlaceholders: true);
  if (fullText.isEmpty) {
    return const (start: 0, end: 0);
  }
  final lineExtents = _paragraphLineExtents(paragraph);
  if (lineExtents.isEmpty) {
    return null;
  }

  var probe = renderOffset.clamp(0, fullText.length).toInt();
  if (probe == fullText.length && probe > 0) {
    probe -= 1;
  }

  var probeBoxes = _characterBoxes(paragraph, fullText, probe);
  while (probeBoxes.isEmpty && probe > 0) {
    probe -= 1;
    probeBoxes = _characterBoxes(paragraph, fullText, probe);
  }
  while (probeBoxes.isEmpty && probe < fullText.length - 1) {
    probe += 1;
    probeBoxes = _characterBoxes(paragraph, fullText, probe);
  }
  if (probeBoxes.isEmpty) {
    return null;
  }

  final lineExtent = lineExtents.firstWhere(
    (extent) => _boxesOverlapLineExtent(probeBoxes, extent),
    orElse: () => lineExtents.last,
  );

  var start = probe;
  while (start > 0) {
    final previousBoxes = _characterBoxes(paragraph, fullText, start - 1);
    if (previousBoxes.isEmpty ||
        !_boxesOverlapLineExtent(previousBoxes, lineExtent)) {
      break;
    }
    start -= 1;
  }

  var end = probe + 1;
  while (end < fullText.length) {
    final nextBoxes = _characterBoxes(paragraph, fullText, end);
    if (nextBoxes.isEmpty || !_boxesOverlapLineExtent(nextBoxes, lineExtent)) {
      break;
    }
    end += 1;
  }
  return (start: start, end: end);
}

List<TextBox> _characterBoxes(
  RenderParagraph paragraph,
  String fullText,
  int renderOffset,
) {
  if (fullText.isEmpty) {
    return const <TextBox>[];
  }
  final start = renderOffset.clamp(0, fullText.length - 1).toInt();
  final end = math.min(start + 1, fullText.length);
  if (start >= end) {
    return const <TextBox>[];
  }
  return paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
}

bool _boxesOverlapLineExtent(List<TextBox> boxes, _LineExtent lineExtent) {
  for (final box in boxes) {
    final overlapTop = math.max(box.top, lineExtent.top);
    final overlapBottom = math.min(box.bottom, lineExtent.bottom);
    if (overlapBottom - overlapTop > 0.5) {
      return true;
    }
  }
  return false;
}

/// Each visual line's vertical extent, with the gaps between lines split
/// halfway so that selection rects of adjacent lines meet.
List<_LineExtent> _paragraphLineExtents(RenderParagraph paragraph) {
  final fullText = paragraph.text.toPlainText(includePlaceholders: true);
  if (fullText.isEmpty) {
    return const <_LineExtent>[];
  }
  if (fullText.contains('\uFFFC')) {
    return _contiguousLinesFromBoxes(
      paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: fullText.length),
      ),
    );
  }

  final textPainter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: null,
  )..layout(maxWidth: paragraph.size.width);
  final lines = textPainter.computeLineMetrics();
  textPainter.dispose();
  final contiguousLines = <_LineExtent>[];
  for (var i = 0; i < lines.length; i++) {
    final current = lines[i];
    final previous = i > 0 ? lines[i - 1] : null;
    final next = i < lines.length - 1 ? lines[i + 1] : null;
    final currentTop = current.baseline - current.ascent;
    final currentBottom = currentTop + current.height;
    contiguousLines.add((
      top: previous != null
          ? (previous.baseline -
                  previous.ascent +
                  previous.height +
                  currentTop) /
              2.0
          : currentTop,
      bottom: next != null
          ? (currentBottom + next.baseline - next.ascent) / 2.0
          : currentBottom,
    ));
  }
  return contiguousLines;
}

List<_LineExtent> _contiguousLinesFromBoxes(List<TextBox> allBoxes) {
  if (allBoxes.isEmpty) {
    return const <_LineExtent>[];
  }
  final sorted = allBoxes.toList(growable: false)
    ..sort((a, b) => a.top.compareTo(b.top));

  final lines = <_LineExtent>[];
  var lineTop = sorted.first.top;
  var lineBottom = sorted.first.bottom;
  for (final box in sorted.skip(1)) {
    if (box.top < lineBottom - 1.0) {
      lineTop = math.min(lineTop, box.top);
      lineBottom = math.max(lineBottom, box.bottom);
    } else {
      lines.add((top: lineTop, bottom: lineBottom));
      lineTop = box.top;
      lineBottom = box.bottom;
    }
  }
  lines.add((top: lineTop, bottom: lineBottom));

  final contiguousLines = <_LineExtent>[];
  for (var i = 0; i < lines.length; i++) {
    final current = lines[i];
    final previous = i > 0 ? lines[i - 1] : null;
    final next = i < lines.length - 1 ? lines[i + 1] : null;
    contiguousLines.add((
      top: previous != null
          ? (previous.bottom + current.top) / 2.0
          : current.top,
      bottom: next != null ? (current.bottom + next.top) / 2.0 : current.bottom,
    ));
  }
  return contiguousLines;
}

List<TextBox> _normalizeBoxesToLineExtents(
  List<TextBox> boxes,
  List<_LineExtent> lineExtents,
) {
  if (lineExtents.isEmpty) {
    return boxes;
  }
  return boxes.map((box) {
    for (final extent in lineExtents) {
      final overlapTop = math.max(box.top, extent.top);
      final overlapBottom = math.min(box.bottom, extent.bottom);
      if (overlapBottom - overlapTop > 0.5) {
        return TextBox.fromLTRBD(
          box.left,
          extent.top,
          box.right,
          extent.bottom,
          box.direction,
        );
      }
    }
    return box;
  }).toList(growable: false);
}

/// Merges the boxes of each line into one box spanning them.
List<TextBox> _mergeSameLineBoxes(List<TextBox> boxes) {
  if (boxes.length < 2) {
    return boxes;
  }
  const lineTolerance = 2.0;

  final sorted = boxes.toList(growable: false)
    ..sort((a, b) {
      final topCompare = a.top.compareTo(b.top);
      if (topCompare != 0) {
        return topCompare;
      }
      return a.left.compareTo(b.left);
    });

  final merged = <TextBox>[];
  var current = sorted.first;
  for (final next in sorted.skip(1)) {
    final sameLine = (next.top - current.top).abs() <= lineTolerance &&
        (next.bottom - current.bottom).abs() <= lineTolerance;
    if (sameLine) {
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
