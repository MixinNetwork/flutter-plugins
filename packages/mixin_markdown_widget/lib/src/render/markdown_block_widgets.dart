import 'package:flutter/material.dart';

import '../core/document.dart';
import '../widgets/markdown_theme.dart';

double markdownListMarkerWidth(ListBlock block, int index) {
  final item = block.items[index];
  if (item.taskState != null) {
    return 22;
  }
  if (!block.ordered) {
    return 14;
  }
  final digits = (block.startIndex + index).toString().length;
  return 10 + digits * 8;
}

double markdownListMarkerGap(ListBlock block, int index) {
  final item = block.items[index];
  return item.taskState == null ? 6 : 8;
}

double markdownListMarkerExtent(ListBlock block, int index) {
  return markdownListMarkerWidth(block, index) +
      markdownListMarkerGap(block, index);
}

typedef MarkdownInlineTextWidgetBuilder = Widget Function(
  BuildContext context,
  TextStyle style,
  List<InlineNode> inlines,
  TextAlign textAlign,
);

class MarkdownQuoteBlockView extends StatelessWidget {
  const MarkdownQuoteBlockView({
    super.key,
    required this.theme,
    required this.child,
    this.selectableContent,
  });

  final MarkdownThemeData theme;
  final Widget child;
  final Widget? selectableContent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.quoteBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(
            color: theme.quoteBorderColor,
            width: theme.quoteBorderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: theme.quotePadding,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final selectableContent = this.selectableContent;
    if (selectableContent == null) {
      return child;
    }

    return Stack(
      alignment: Alignment.topLeft,
      children: <Widget>[
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: 0,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: selectableContent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MarkdownTableFrame extends StatelessWidget {
  const MarkdownTableFrame({
    super.key,
    required this.theme,
    required this.child,
    this.selectionOverlayColor,
  });

  final MarkdownThemeData theme;
  final Widget child;
  final Color? selectionOverlayColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _MarkdownTableFramePainter(
        borderColor: theme.tableBorderColor,
        borderRadius: BorderRadius.circular(14),
        selectionOverlayColor: selectionOverlayColor,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

class MarkdownListBlockView extends StatelessWidget {
  const MarkdownListBlockView({
    super.key,
    required this.theme,
    required this.block,
    required this.itemBuilder,
    this.itemRowKeyBuilder,
    this.itemContentKeyBuilder,
  });

  final MarkdownThemeData theme;
  final ListBlock block;
  final Widget Function(ListItemNode item) itemBuilder;
  final Key? Function(int index)? itemRowKeyBuilder;
  final Key? Function(int index)? itemContentKeyBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < block.items.length; index++)
          Builder(
            builder: (context) {
              final markerWidth = markdownListMarkerWidth(block, index);
              final markerGap = markdownListMarkerGap(block, index);
              return KeyedSubtree(
                key: itemRowKeyBuilder?.call(index),
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: index == block.items.length - 1
                        ? 0
                        : theme.listItemSpacing,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: markerWidth,
                        child: Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: _buildMarker(index),
                        ),
                      ),
                      SizedBox(width: markerGap),
                      Expanded(
                        child: KeyedSubtree(
                          key: itemContentKeyBuilder?.call(index),
                          child: itemBuilder(block.items[index]),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMarker(int index) {
    final item = block.items[index];
    switch (item.taskState) {
      case MarkdownTaskListItemState.checked:
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_box_rounded,
            size: 18,
            color: theme.linkStyle.color ?? theme.bodyStyle.color,
          ),
        );
      case MarkdownTaskListItemState.unchecked:
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_box_outline_blank_rounded,
            size: 18,
            color: theme.bodyStyle.color?.withOpacity(0.72),
          ),
        );
      case null:
        return Text(
          block.ordered ? '${block.startIndex + index}.' : '•',
          style: theme.bodyStyle.copyWith(height: 1.45),
        );
    }
  }
}

class MarkdownCodeBlockView extends StatelessWidget {
  const MarkdownCodeBlockView({
    super.key,
    required this.theme,
    required this.codeSpan,
    required this.onCopyCode,
    required this.toolbarHeight,
    this.language,
  });

  final MarkdownThemeData theme;
  final InlineSpan codeSpan;
  final VoidCallback onCopyCode;
  final double toolbarHeight;
  final String? language;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.codeBlockBackgroundColor,
        borderRadius: theme.codeBlockBorderRadius,
        border: Border.all(
          color: theme.tableBorderColor.withOpacity(0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: toolbarHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
              child: Row(
                children: <Widget>[
                  if (language != null && language!.isNotEmpty)
                    Text(
                      language!,
                      style: theme.bodyStyle.copyWith(
                        fontSize: 12,
                        color: theme.bodyStyle.color?.withOpacity(0.72),
                      ),
                    ),
                  const Spacer(),
                  Tooltip(
                    message: 'Copy code',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: onCopyCode,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: theme.codeBlockPadding,
            child: Text.rich(
              codeSpan,
              style: theme.codeBlockStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class MarkdownTableBlockView extends StatelessWidget {
  const MarkdownTableBlockView({
    super.key,
    required this.theme,
    required this.block,
    required this.textWidgetBuilder,
  });

  final MarkdownThemeData theme;
  final TableBlock block;
  final MarkdownInlineTextWidgetBuilder textWidgetBuilder;

  @override
  Widget build(BuildContext context) {
    final columnCount = block.rows.fold<int>(
      0,
      (maxCount, row) =>
          row.cells.length > maxCount ? row.cells.length : maxCount,
    );
    if (columnCount == 0) {
      return const SizedBox.shrink();
    }

    return MarkdownTableFrame(
      theme: theme,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(color: theme.tableBorderColor),
            verticalInside: BorderSide(color: theme.tableBorderColor),
          ),
          children: <TableRow>[
            for (final row in block.rows)
              TableRow(
                decoration: BoxDecoration(
                  color: row.isHeader
                      ? theme.tableHeaderBackgroundColor
                      : theme.tableRowBackgroundColor,
                ),
                children: <Widget>[
                  for (var index = 0; index < columnCount; index++)
                    _buildCell(
                      context: context,
                      row: row,
                      cellIndex: index,
                      alignment: index < block.alignments.length
                          ? block.alignments[index]
                          : MarkdownTableColumnAlignment.none,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell({
    required BuildContext context,
    required TableRowNode row,
    required int cellIndex,
    required MarkdownTableColumnAlignment alignment,
  }) {
    final cell = cellIndex < row.cells.length
        ? row.cells[cellIndex]
        : const TableCellNode(inlines: <InlineNode>[]);
    final textStyle = row.isHeader ? theme.tableHeaderStyle : theme.bodyStyle;
    return Padding(
      padding: theme.tableCellPadding,
      child: Align(
        alignment: _alignmentFor(alignment),
        child: textWidgetBuilder(
          context,
          textStyle,
          cell.inlines,
          _textAlignFor(alignment),
        ),
      ),
    );
  }

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

class MarkdownImageBlockView extends StatelessWidget {
  const MarkdownImageBlockView({
    super.key,
    required this.image,
    this.caption,
  });

  final Widget image;
  final Widget? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        image,
        if (caption != null) ...<Widget>[
          const SizedBox(height: 8),
          caption!,
        ],
      ],
    );
  }
}

class _MarkdownTableFramePainter extends CustomPainter {
  const _MarkdownTableFramePainter({
    required this.borderColor,
    required this.borderRadius,
    this.selectionOverlayColor,
  });

  final Color borderColor;
  final BorderRadius borderRadius;
  final Color? selectionOverlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    final overlayColor = selectionOverlayColor;
    if (overlayColor != null) {
      canvas.drawRRect(rrect, Paint()..color = overlayColor);
    }

    canvas.drawRRect(
      borderRadius.toRRect(rect.deflate(0.5)),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkdownTableFramePainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.selectionOverlayColor != selectionOverlayColor;
  }
}
