import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../core/document.dart';
import '../selection/selection_controller.dart';
import '../widgets/markdown_theme.dart';
import 'markdown_block_widgets.dart';

class SelectableMarkdownTableBlock extends StatefulWidget {
  const SelectableMarkdownTableBlock({
    super.key,
    required this.blockIndex,
    required this.block,
    required this.theme,
    required this.selectionColor,
    required this.selectionController,
    required this.textWidgetBuilder,
    this.onRequestContextMenu,
    this.documentSelected = false,
  });

  final int blockIndex;
  final TableBlock block;
  final MarkdownThemeData theme;
  final Color selectionColor;
  final MarkdownSelectionController selectionController;
  final MarkdownInlineTextWidgetBuilder textWidgetBuilder;
  final ValueChanged<Offset>? onRequestContextMenu;
  final bool documentSelected;

  @override
  State<SelectableMarkdownTableBlock> createState() =>
      SelectableMarkdownTableBlockState();
}

class SelectableMarkdownTableBlockState
    extends State<SelectableMarkdownTableBlock> {
  final Map<String, GlobalKey> _cellKeys = <String, GlobalKey>{};

  TableCellPosition? _dragAnchor;
  TableCellPosition? _lastExtent;
  bool _isDragging = false;

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

  TableCellPosition? cellPositionAtGlobal(Offset globalPosition) {
    return _cellAtGlobal(globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final columnCount = widget.block.rows.fold<int>(
      0,
      (maxCount, row) =>
          row.cells.length > maxCount ? row.cells.length : maxCount,
    );
    if (columnCount == 0) {
      return const SizedBox.shrink();
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: MarkdownTableFrame(
        theme: widget.theme,
        selectionOverlayColor:
            widget.documentSelected ? widget.selectionColor : null,
        child: MarkdownAdaptiveTableLayout(
          block: widget.block,
          tableBuilder: (columnWidths, defaultColumnWidth) => Table(
            columnWidths: columnWidths,
            defaultColumnWidth: defaultColumnWidth,
            border: TableBorder(
              horizontalInside:
                  BorderSide(color: widget.theme.tableBorderColor),
              verticalInside: BorderSide(color: widget.theme.tableBorderColor),
            ),
            children: <TableRow>[
              for (var rowIndex = 0;
                  rowIndex < widget.block.rows.length;
                  rowIndex++)
                _buildRow(
                  row: widget.block.rows[rowIndex],
                  rowIndex: rowIndex,
                  columnCount: columnCount,
                ),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _buildRow({
    required TableRowNode row,
    required int rowIndex,
    required int columnCount,
  }) {
    return TableRow(
      decoration: BoxDecoration(
        color: row.isHeader
            ? widget.theme.tableHeaderBackgroundColor
            : widget.theme.tableRowBackgroundColor,
      ),
      children: <Widget>[
        for (var columnIndex = 0; columnIndex < columnCount; columnIndex++)
          _buildCell(
            row: row,
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            alignment: columnIndex < widget.block.alignments.length
                ? widget.block.alignments[columnIndex]
                : MarkdownTableColumnAlignment.none,
          ),
      ],
    );
  }

  Widget _buildCell({
    required TableRowNode row,
    required int rowIndex,
    required int columnIndex,
    required MarkdownTableColumnAlignment alignment,
  }) {
    final key = _cellKeys.putIfAbsent(
      _cellKey(rowIndex, columnIndex),
      () => GlobalKey(debugLabel: 'table-$rowIndex-$columnIndex'),
    );
    final cell = columnIndex < row.cells.length
        ? row.cells[columnIndex]
        : const TableCellNode(inlines: <InlineNode>[]);
    final textStyle =
        row.isHeader ? widget.theme.tableHeaderStyle : widget.theme.bodyStyle;
    final isSelected = _isCellSelected(rowIndex, columnIndex);
    final baseColor = row.isHeader
        ? widget.theme.tableHeaderBackgroundColor
        : widget.theme.tableRowBackgroundColor;

    return Listener(
      key: key,
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _handleCellPointerDown(
        TableCellPosition(rowIndex: rowIndex, columnIndex: columnIndex),
        event,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? Color.alphaBlend(widget.selectionColor, baseColor)
              : null,
        ),
        child: Padding(
          padding: widget.theme.tableCellPadding,
          child: Align(
            alignment: _alignmentFor(alignment),
            child: widget.textWidgetBuilder(
              context,
              textStyle,
              cell.inlines,
              _textAlignFor(alignment),
            ),
          ),
        ),
      ),
    );
  }

  void _handleCellPointerDown(
    TableCellPosition position,
    PointerDownEvent event,
  ) {
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      widget.selectionController.setTableCellSelection(
        TableCellSelection(
          blockIndex: widget.blockIndex,
          base: position,
          extent: position,
        ),
      );
      widget.onRequestContextMenu?.call(event.position);
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    _isDragging = true;
    _dragAnchor = position;
    _lastExtent = position;
    widget.selectionController.setTableCellSelection(
      TableCellSelection(
        blockIndex: widget.blockIndex,
        base: position,
        extent: position,
      ),
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDragging || (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    final extent = _cellAtGlobal(event.position);
    final anchor = _dragAnchor;
    if (anchor == null || extent == null || extent == _lastExtent) {
      return;
    }
    _lastExtent = extent;
    widget.selectionController.setTableCellSelection(
      TableCellSelection(
        blockIndex: widget.blockIndex,
        base: anchor,
        extent: extent,
      ),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    _isDragging = false;
    _dragAnchor = null;
    _lastExtent = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _isDragging = false;
    _dragAnchor = null;
    _lastExtent = null;
  }

  TableCellPosition? _cellAtGlobal(Offset globalPosition) {
    final columnCount = widget.block.rows.fold<int>(
      0,
      (maxCount, row) =>
          row.cells.length > maxCount ? row.cells.length : maxCount,
    );
    for (var rowIndex = 0; rowIndex < widget.block.rows.length; rowIndex++) {
      for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
        final key = _cellKeys[_cellKey(rowIndex, columnIndex)];
        final context = key?.currentContext;
        final renderObject = context?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.hasSize) {
          continue;
        }
        final rect =
            renderObject.localToGlobal(Offset.zero) & renderObject.size;
        if (rect.contains(globalPosition)) {
          return TableCellPosition(
            rowIndex: rowIndex,
            columnIndex: columnIndex,
          );
        }
      }
    }
    return null;
  }

  bool _isCellSelected(int rowIndex, int columnIndex) {
    final selection = widget.selectionController.tableCellSelection;
    if (selection == null || selection.blockIndex != widget.blockIndex) {
      return false;
    }
    return selection.normalizedRange.contains(rowIndex, columnIndex);
  }

  String _cellKey(int rowIndex, int columnIndex) => '$rowIndex:$columnIndex';

  Alignment _alignmentFor(MarkdownTableColumnAlignment alignment) {
    switch (alignment) {
      case MarkdownTableColumnAlignment.center:
        return Alignment.center;
      case MarkdownTableColumnAlignment.right:
        return Alignment.centerRight;
      case MarkdownTableColumnAlignment.left:
      case MarkdownTableColumnAlignment.none:
        return Alignment.centerLeft;
    }
  }

  TextAlign _textAlignFor(MarkdownTableColumnAlignment alignment) {
    switch (alignment) {
      case MarkdownTableColumnAlignment.center:
        return TextAlign.center;
      case MarkdownTableColumnAlignment.right:
        return TextAlign.right;
      case MarkdownTableColumnAlignment.left:
      case MarkdownTableColumnAlignment.none:
        return TextAlign.left;
    }
  }
}
