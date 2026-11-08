import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/document.dart';
import '../../selection/structured_block_selection.dart';
import '../markdown_block_widgets.dart';
import '../selectable_block.dart';
import 'markdown_descriptor_extractor.dart';
import 'markdown_selectable_leaf.dart';

/// Selection geometry of container blocks: quotes, details, lists,
/// footnotes, and tables.
///
/// A container only orders its leaves. Each leaf answers its own rects and
/// offsets ([MarkdownSelectableLeafState]); this class walks the block's
/// selection tree, reads the boxes of leaves and slots in block coordinates,
/// and converts between leaf-local and block display offsets exactly once,
/// through the leaves of the block's [StructuredBlockSelection].
abstract final class MarkdownContainerSelectionGeometry {
  static List<Rect> rects(
    BuildContext context,
    BlockNode block,
    DocumentRange range,
  ) {
    final query = _Query.of(context, block);
    if (query == null) {
      return const <Rect>[];
    }
    return query.rects(
      query.root,
      range.start.textOffset,
      range.end.textOffset,
    );
  }

  static int? offsetAt(
    BuildContext context,
    BlockNode block,
    Offset localPosition,
  ) {
    final query = _Query.of(context, block);
    return query?.offsetAt(query.root, localPosition);
  }

  /// The range a triple click selects: the visual line of a leaf, a whole
  /// list item when on its marker, or a whole table cell. Without a pointer
  /// position, or when the pointer is outside every leaf, the unit is
  /// resolved from [position] alone.
  static DocumentRange? unitAt(
    BuildContext context,
    BlockNode block,
    Offset? localPosition,
    DocumentPosition position,
  ) {
    final root = _treeFor(block);
    if (root == null) {
      return null;
    }
    final query = localPosition == null ? null : _Query.of(context, block);
    final unit = query?.unitAt(root, localPosition!) ??
        _modelUnitAt(root, position.textOffset);
    if (unit == null) {
      return null;
    }
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: position.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: unit.start,
      ),
      end: DocumentPosition(
        blockIndex: position.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: unit.end,
      ),
    );
  }
}

typedef _Range = ({int start, int end});

/// A node of a block's selection tree. Nested nodes are found through the
/// slot at their [path], which is also the prefix of their leaf paths.
sealed class _Node {
  _Node(this.path);

  final PathInBlock path;

  int get start;

  int get end;
}

final class _LeafNode extends _Node {
  _LeafNode(super.path, this.leaf, {required this.leadsText})
      : start = leaf.displayedOffsetForLocalOffset(0),
        end = leaf.segmentEnd;

  final StructuredBlockSelectionLeaf leaf;

  /// Whether the leaf is a paragraph or heading, whose line selection takes
  /// the list marker along when it starts the item.
  final bool leadsText;

  @override
  final int start;

  @override
  final int end;
}

/// A quote or details: children stacked vertically.
final class _SequenceNode extends _Node {
  _SequenceNode(super.path, this.children);

  final List<_Node> children;

  @override
  int get start => children.first.start;

  @override
  int get end => children.last.end;
}

final class _ListNode extends _Node {
  _ListNode(super.path, this.list, this.items);

  final ListBlock list;
  final List<_ListItemNode> items;

  @override
  int get start => items.first.start;

  @override
  int get end => items.last.end;
}

final class _ListItemNode {
  _ListItemNode({
    required this.index,
    required this.path,
    required this.marker,
    required this.children,
    required this.leadTextChild,
  });

  final int index;
  final PathInBlock path;
  final StructuredBlockSelectionLeaf marker;
  final List<_Node> children;

  /// The first model child of the item when it is a paragraph or heading.
  final _Node? leadTextChild;

  int get start => marker.displayedOffsetForLocalOffset(0);

  int get contentStart => marker.segmentEnd;

  int get end => children.isEmpty ? marker.segmentEnd : children.last.end;
}

/// A table: each non-empty cell is a leaf.
final class _TableNode extends _Node {
  _TableNode(super.path, this.cells);

  final List<_LeafNode> cells;

  @override
  int get start => cells.first.start;

  @override
  int get end => cells.last.end;
}

final Expando<_Tree> _trees = Expando<_Tree>('MarkdownSelectionTree');

class _Tree {
  const _Tree(this.root);

  final _Node? root;
}

_Node? _treeFor(BlockNode block) {
  return (_trees[block] ??= _Tree(
    _TreeBuilder(StructuredBlockSelection.forBlock(block)).build(
      block,
      const <int>[],
    ),
  ))
      .root;
}

/// Builds the selection tree of a block from its model, following the same
/// paths as [StructuredBlockSelection] so that each node finds its leaves.
class _TreeBuilder {
  _TreeBuilder(this.structure);

  final StructuredBlockSelection structure;

  _Node? build(BlockNode block, List<int> path) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        final leaf = structure.leafForPath(
          PathInBlock(path.isEmpty ? const <int>[0] : path),
        );
        if (leaf == null) {
          return null;
        }
        return _LeafNode(
          PathInBlock(path),
          leaf,
          leadsText: block.kind == MarkdownBlockKind.paragraph ||
              block.kind == MarkdownBlockKind.heading,
        );
      case MarkdownBlockKind.quote:
        final quote = block as QuoteBlock;
        return _sequence(path, <_Node?>[
          for (var index = 0; index < quote.children.length; index++)
            build(quote.children[index], <int>[...path, index]),
        ]);
      case MarkdownBlockKind.details:
        final details = block as DetailsBlock;
        return _sequence(path, <_Node?>[
          build(
            ParagraphBlock(
              id: '${details.id}:summary',
              inlines: details.summary,
            ),
            <int>[...path, 0],
          ),
          for (var index = 0; index < details.children.length; index++)
            build(details.children[index], <int>[...path, index + 1]),
        ]);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _list(block as ListBlock, path);
      case MarkdownBlockKind.footnoteList:
        return _list(
          MarkdownDescriptorExtractor.footnoteListAsOrderedList(
            block as FootnoteListBlock,
          ),
          path,
        );
      case MarkdownBlockKind.table:
        final table = block as TableBlock;
        final cells = <_LeafNode>[
          for (var row = 0; row < table.rows.length; row++)
            for (var column = 0;
                column < table.rows[row].cells.length;
                column++)
              if (structure
                      .leafForPath(PathInBlock(<int>[...path, row, column]))
                  case final leaf?)
                _LeafNode(leaf.path, leaf, leadsText: false),
        ];
        return cells.isEmpty ? null : _TableNode(PathInBlock(path), cells);
    }
  }

  _Node? _sequence(List<int> path, List<_Node?> children) {
    final present = children.nonNulls.toList(growable: false);
    return present.isEmpty ? null : _SequenceNode(PathInBlock(path), present);
  }

  _Node? _list(ListBlock list, List<int> path) {
    final items = <_ListItemNode>[];
    for (var index = 0; index < list.items.length; index++) {
      final marker =
          structure.leafForPath(PathInBlock(<int>[...path, index, 0]));
      if (marker == null) {
        continue;
      }
      final item = list.items[index];
      _Node? leadTextChild;
      final children = <_Node>[];
      for (var child = 0; child < item.children.length; child++) {
        final node =
            build(item.children[child], <int>[...path, index, child + 1]);
        if (node == null) {
          continue;
        }
        if (child == 0 && node is _LeafNode && node.leadsText) {
          leadTextChild = node;
        }
        children.add(node);
      }
      items.add(
        _ListItemNode(
          index: index,
          path: PathInBlock(<int>[...path, index]),
          marker: marker,
          children: children,
          leadTextChild: leadTextChild,
        ),
      );
    }
    return items.isEmpty ? null : _ListNode(PathInBlock(path), list, items);
  }
}

/// The selection unit at [offset] from the model alone: the leaf or list
/// item that contains it, with the list marker taken along by a leading
/// paragraph.
_Range? _modelUnitAt(_Node node, int offset) {
  bool contains(int start, int end) => offset >= start && offset <= end;
  _Range rangeOf(_Node node) => (start: node.start, end: node.end);
  _Range childUnit(_Node child) =>
      (child is _LeafNode ? null : _modelUnitAt(child, offset)) ??
      rangeOf(child);

  switch (node) {
    case _LeafNode():
      return null;
    case _SequenceNode(:final children):
      for (final child in children) {
        if (contains(child.start, child.end)) {
          return childUnit(child);
        }
      }
      return rangeOf(children.last);
    case _ListNode(:final items):
      for (final item in items) {
        if (!contains(item.start, item.end)) {
          continue;
        }
        for (final child in item.children) {
          if (!contains(child.start, child.end)) {
            continue;
          }
          final unit = childUnit(child);
          return identical(child, item.leadTextChild)
              ? (start: item.start, end: unit.end)
              : unit;
        }
        return (start: item.start, end: item.end);
      }
      return (start: items.last.start, end: items.last.end);
    case _TableNode(:final cells):
      for (final cell in cells) {
        if (contains(cell.start, cell.end)) {
          return rangeOf(cell);
        }
      }
      return null;
  }
}

/// One geometry query against the live leaves and slots of a block, in the
/// block's coordinates.
class _Query {
  _Query._(this.registry, this.blockBox, this.root);

  static _Query? of(BuildContext context, BlockNode block) {
    final registry = SelectableMarkdownBlockState.leafRegistryOf(context);
    final blockBox = context.findRenderObject();
    final root = _treeFor(block);
    if (registry == null ||
        blockBox is! RenderBox ||
        !blockBox.hasSize ||
        root == null) {
      return null;
    }
    return _Query._(registry, blockBox, root);
  }

  final MarkdownSelectionLeafRegistry registry;
  final RenderBox blockBox;
  final _Node root;

  Rect? _slotRect(PathInBlock path, MarkdownSelectionSlotRole role) {
    final box = registry.slotBox(path, role);
    if (box == null) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: blockBox) & box.size;
  }

  Rect? _childRect(_Node node) {
    return _slotRect(node.path, MarkdownSelectionSlotRole.child);
  }

  ({MarkdownSelectableLeafState state, Offset origin})? _leaf(_LeafNode node) {
    final state = registry.leaf(node.leaf.path);
    final origin = state?.originIn(blockBox);
    if (state == null || origin == null) {
      return null;
    }
    return (state: state, origin: origin);
  }

  // Rects.

  List<Rect> rects(_Node node, int start, int end) {
    switch (node) {
      case _LeafNode():
        return _leafRects(node, start, end);
      case _SequenceNode(:final children):
        return _childrenRects(children, start, end);
      case _ListNode():
        return _listRects(node, start, end);
      case _TableNode(:final cells):
        return _childrenRects(cells, start, end);
    }
  }

  List<Rect> _childrenRects(List<_Node> children, int start, int end) {
    final rects = <Rect>[];
    for (final child in children) {
      final childStart = math.max(start, child.start);
      final childEnd = math.min(end, child.end);
      if (childStart < childEnd) {
        rects.addAll(this.rects(child, childStart, childEnd));
      }
    }
    return rects;
  }

  List<Rect> _leafRects(_LeafNode node, int start, int end) {
    final leaf = _leaf(node);
    if (leaf == null) {
      return const <Rect>[];
    }
    final rects = leaf.state
        .rectsFor(
          node.leaf.localOffsetForDisplayedOffset(start),
          node.leaf.localOffsetForDisplayedOffset(end),
        )
        .map((rect) => rect.shift(leaf.origin));
    final clipRect = leaf.state.clipRect?.shift(leaf.origin);
    if (clipRect == null) {
      return rects.toList(growable: false);
    }
    return rects
        .map((rect) => rect.intersect(clipRect))
        .where((rect) => !rect.isEmpty)
        .toList(growable: false);
  }

  List<Rect> _listRects(_ListNode list, int start, int end) {
    final rects = <Rect>[];
    for (final item in list.items) {
      final contentSelectionStart = math.max(start, item.contentStart);
      final contentSelectionEnd = math.min(end, item.end);
      final prefixSelectionStart = math.max(start, item.start);
      final prefixSelectionEnd = math.min(end, item.contentStart);
      if (contentSelectionStart >= contentSelectionEnd &&
          prefixSelectionStart >= prefixSelectionEnd) {
        continue;
      }

      final contentRect =
          _slotRect(item.path, MarkdownSelectionSlotRole.listContent);
      final rowRect = _slotRect(item.path, MarkdownSelectionSlotRole.listRow);
      final contentRects =
          contentSelectionStart < contentSelectionEnd && contentRect != null
              ? _childrenRects(
                  item.children,
                  contentSelectionStart,
                  contentSelectionEnd,
                )
              : const <Rect>[];
      final prefixRect =
          prefixSelectionStart < prefixSelectionEnd && rowRect != null
              ? _listPrefixRect(list, item, rowRect, contentRect)
              : null;

      if (contentSelectionStart >= contentSelectionEnd || contentRect == null) {
        if (prefixRect != null) {
          rects.add(prefixRect);
        }
        continue;
      }
      if (prefixRect != null && contentRects.isNotEmpty) {
        final firstContentRect = contentRects.first;
        if (_rectsShareLine(prefixRect, firstContentRect)) {
          rects
            ..add(
              Rect.fromLTRB(
                prefixRect.left,
                firstContentRect.top,
                firstContentRect.right,
                firstContentRect.bottom,
              ),
            )
            ..addAll(contentRects.skip(1));
          continue;
        }
        rects.add(prefixRect);
      }
      rects.addAll(contentRects);
    }
    return rects;
  }

  /// The marker part of a list item selection: as wide as the marker extent
  /// and aligned to the first line of the item's first child.
  Rect _listPrefixRect(
    _ListNode list,
    _ListItemNode item,
    Rect rowRect,
    Rect? contentRect,
  ) {
    var top = rowRect.top;
    var height = rowRect.height;
    final firstChild = item.children.isEmpty ? null : item.children.first;
    final firstChildRect = firstChild == null ? null : _childRect(firstChild);
    if (firstChild != null && firstChildRect != null) {
      final firstLineRect = _firstLineRect(firstChild);
      top = firstLineRect?.top ?? firstChildRect.top;
      height = firstLineRect?.height ?? firstChildRect.height;
    }
    final extent = _listMarkerExtent(list, item, rowRect, contentRect);
    return Rect.fromLTRB(
      rowRect.left,
      top,
      rowRect.left + extent,
      top + height,
    );
  }

  Rect? _firstLineRect(_Node node) {
    final rects = this
        .rects(
          node,
          node.start,
          math.min(node.start + 1, node.end),
        )
        .toList();
    if (rects.isEmpty) {
      return null;
    }
    rects.sort((a, b) {
      final topCompare = a.top.compareTo(b.top);
      return topCompare != 0 ? topCompare : a.left.compareTo(b.left);
    });
    return rects.first;
  }

  double _listMarkerExtent(
    _ListNode list,
    _ListItemNode item,
    Rect rowRect,
    Rect? contentRect,
  ) {
    if (contentRect != null) {
      final contentOriginDx = contentRect.left - rowRect.left;
      if (contentOriginDx > 0) {
        return math.min(contentOriginDx, rowRect.width);
      }
    }
    return math.min(
      markdownListMarkerExtent(list.list, item.index),
      rowRect.width,
    );
  }

  // Offsets.

  int? offsetAt(_Node node, Offset position) {
    switch (node) {
      case _LeafNode():
        final leaf = _leaf(node);
        if (leaf == null) {
          return null;
        }
        return node.leaf.displayedOffsetForLocalOffset(
          leaf.state.offsetAt(position - leaf.origin),
        );
      case _SequenceNode(:final children):
        return _childrenOffsetAt(children, position);
      case _ListNode():
        return _listOffsetAt(node, position);
      case _TableNode():
        final cell = _nearestCell(node, position);
        if (cell == null) {
          return null;
        }
        return cell.node.leaf.displayedOffsetForLocalOffset(
          cell.leaf.state.offsetAt(position - cell.leaf.origin),
        );
    }
  }

  /// The offset among stacked children: inside the child that contains the
  /// position; in a gap between two children, the end of the upper or the
  /// start of the lower one, split at the gap midpoint; otherwise an edge of
  /// the nearest child.
  int? _childrenOffsetAt(List<_Node> children, Offset position) {
    final resolved = <({_Node node, Rect rect})>[];
    _Node? nearest;
    Rect? nearestRect;
    var bestDistance = double.infinity;
    for (final child in children) {
      final rect = _childRect(child);
      if (rect == null) {
        continue;
      }
      resolved.add((node: child, rect: rect));
      if (rect.contains(position)) {
        return offsetAt(child, position) ?? child.start;
      }
      final distance = _distanceToRect(position, rect);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = child;
        nearestRect = rect;
      }
    }

    resolved.sort((a, b) => a.rect.top.compareTo(b.rect.top));
    for (var index = 0; index < resolved.length - 1; index++) {
      final current = resolved[index];
      final next = resolved[index + 1];
      if (position.dy < current.rect.bottom || position.dy > next.rect.top) {
        continue;
      }
      final overlapLeft = math.min(current.rect.right, next.rect.right);
      final overlapRight = math.max(current.rect.left, next.rect.left);
      if (position.dx < overlapRight - 24 || position.dx > overlapLeft + 24) {
        continue;
      }
      final midpointY = (current.rect.bottom + next.rect.top) / 2;
      return position.dy <= midpointY ? current.node.end : next.node.start;
    }

    if (nearest == null || nearestRect == null) {
      return null;
    }
    final preferEnd = position.dy > nearestRect.center.dy ||
        position.dx > nearestRect.center.dx;
    return preferEnd ? nearest.end : nearest.start;
  }

  int? _listOffsetAt(_ListNode list, Offset position) {
    _ListItemNode? nearest;
    Rect? nearestRowRect;
    var bestDistance = double.infinity;

    for (final item in list.items) {
      final contentRect =
          _slotRect(item.path, MarkdownSelectionSlotRole.listContent);
      int? childOffset;
      if (contentRect != null) {
        final childContainsPosition = item.children.any(
          (child) => _childRect(child)?.contains(position) ?? false,
        );
        childOffset = _childrenOffsetAt(item.children, position);
        if (contentRect.contains(position)) {
          if (!childContainsPosition) {
            final projected = _childrenOffsetAt(
              item.children,
              _projectIntoContent(contentRect, position),
            );
            if (projected != null) {
              return projected;
            }
          }
          return childOffset ?? item.contentStart;
        }
      }

      final rowRect = _slotRect(item.path, MarkdownSelectionSlotRole.listRow);
      if (rowRect == null) {
        continue;
      }
      final distance = _distanceToRect(position, rowRect);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = item;
        nearestRowRect = rowRect;
      }
      if (!rowRect.contains(position)) {
        continue;
      }
      final localDx = position.dx - rowRect.left;
      final markerWidth = math.min(
        markdownListMarkerWidth(list.list, item.index),
        rowRect.width,
      );
      if (localDx <= markerWidth) {
        return item.start;
      }
      if (contentRect != null &&
          position.dy >= contentRect.top &&
          position.dy <= contentRect.bottom) {
        final projected = _childrenOffsetAt(
          item.children,
          _projectIntoContent(contentRect, position),
        );
        if (projected != null) {
          return projected;
        }
      }
      if (localDx <= _listMarkerExtent(list, item, rowRect, contentRect)) {
        return item.start;
      }
      return childOffset ?? item.contentStart;
    }

    if (nearest == null || nearestRowRect == null) {
      return null;
    }
    final preferEnd = position.dy > nearestRowRect.center.dy ||
        position.dx > nearestRowRect.center.dx;
    return preferEnd ? nearest.end : nearest.start;
  }

  /// [position] moved to the left edge of the item content, at the same
  /// height inside it.
  Offset _projectIntoContent(Rect contentRect, Offset position) {
    final dy = contentRect.height < 1
        ? contentRect.center.dy
        : position.dy.clamp(contentRect.top + 0.5, contentRect.bottom - 0.5);
    return Offset(contentRect.left + 1, dy.toDouble());
  }

  /// The cell whose text is nearest to [position].
  ({
    _LeafNode node,
    ({MarkdownSelectableLeafState state, Offset origin}) leaf,
  })? _nearestCell(_TableNode table, Offset position) {
    ({
      _LeafNode node,
      ({MarkdownSelectableLeafState state, Offset origin}) leaf,
    })? nearest;
    var bestDistance = double.infinity;
    for (final cell in table.cells) {
      final leaf = _leaf(cell);
      final size = leaf?.state.box?.size;
      if (leaf == null || size == null) {
        continue;
      }
      final distance = _distanceToRect(position, leaf.origin & size);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = (node: cell, leaf: leaf);
      }
    }
    return nearest;
  }

  // Selection units.

  _Range? unitAt(_Node node, Offset position) {
    switch (node) {
      case _LeafNode():
        final leaf = _leaf(node);
        if (leaf == null) {
          return null;
        }
        if (leaf.state.selectsWhole) {
          return (start: node.start, end: node.end);
        }
        final localPosition = position - leaf.origin;
        final range = leaf.state.lineRangeAt(
          leaf.state.offsetAt(localPosition),
          localPosition: localPosition,
        );
        if (range == null) {
          return null;
        }
        return (
          start: node.leaf.displayedOffsetForLocalOffset(range.start),
          end: node.leaf.displayedOffsetForLocalOffset(range.end),
        );
      case _SequenceNode(:final children):
        final child = _childContaining(children, position);
        return child == null ? null : unitAt(child, position);
      case _ListNode():
        return _listUnitAt(node, position);
      case _TableNode():
        final cell = _nearestCell(node, position)?.node;
        return cell == null ? null : (start: cell.start, end: cell.end);
    }
  }

  _Range? _listUnitAt(_ListNode list, Offset position) {
    for (final item in list.items) {
      final rowRect = _slotRect(item.path, MarkdownSelectionSlotRole.listRow);
      if (rowRect != null &&
          rowRect.contains(position) &&
          position.dx - rowRect.left <=
              _listMarkerExtent(list, item, rowRect, null)) {
        return (start: item.start, end: item.end);
      }

      final contentRect =
          _slotRect(item.path, MarkdownSelectionSlotRole.listContent);
      if (contentRect == null || !contentRect.contains(position)) {
        continue;
      }
      final child = _childContaining(item.children, position) ??
          _childContaining(
            item.children,
            _projectIntoContent(contentRect, position),
          );
      if (child == null) {
        continue;
      }
      final unit = unitAt(child, position);
      if (unit == null) {
        return null;
      }
      final includeMarker =
          identical(child, item.leadTextChild) && unit.start == child.start;
      return (start: includeMarker ? item.start : unit.start, end: unit.end);
    }
    return null;
  }

  _Node? _childContaining(List<_Node> children, Offset position) {
    for (final child in children) {
      if (_childRect(child)?.contains(position) ?? false) {
        return child;
      }
    }
    return null;
  }
}

bool _rectsShareLine(Rect a, Rect b) {
  final overlapTop = math.max(a.top, b.top);
  final overlapBottom = math.min(a.bottom, b.bottom);
  return overlapBottom - overlapTop > 1.0;
}

double _distanceToRect(Offset point, Rect rect) {
  final dx = point.dx < rect.left
      ? rect.left - point.dx
      : point.dx > rect.right
          ? point.dx - rect.right
          : 0.0;
  final dy = point.dy < rect.top
      ? rect.top - point.dy
      : point.dy > rect.bottom
          ? point.dy - rect.bottom
          : 0.0;
  return dx * dx + dy * dy;
}
