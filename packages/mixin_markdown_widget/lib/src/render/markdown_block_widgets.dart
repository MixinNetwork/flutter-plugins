import 'image_caption_layout.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/document.dart';
import '../widgets/markdown_theme.dart';
import '../widgets/markdown_types.dart';

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
  TextAlign textAlign, {
  GlobalKey? directTextKey,
});

typedef MarkdownTableWidgetBuilder = Widget Function(
  Map<int, TableColumnWidth>? columnWidths,
  TableColumnWidth defaultColumnWidth,
);

int _estimateInlineTextLength(List<InlineNode> inlines) {
  int length = 0;
  for (final inline in inlines) {
    if (inline is TextInline) {
      length += inline.text.length;
    } else if (inline is InlineCode) {
      length += inline.text.length;
    } else if (inline is MathInline) {
      length += inline.tex.length;
    } else if (inline is EmphasisInline) {
      length += _estimateInlineTextLength(inline.children);
    } else if (inline is StrongInline) {
      length += _estimateInlineTextLength(inline.children);
    } else if (inline is StrikethroughInline) {
      length += _estimateInlineTextLength(inline.children);
    } else if (inline is HighlightInline) {
      length += _estimateInlineTextLength(inline.children);
    } else if (inline is SubscriptInline) {
      length += _estimateInlineTextLength(inline.children);
    } else if (inline is SuperscriptInline) {
      length += _estimateInlineTextLength(inline.children);
    } else if (inline is LinkInline) {
      length += _estimateInlineTextLength(inline.children);
    } else if (inline is SoftBreakInline || inline is HardBreakInline) {
      length += 1;
    }
  }
  return length;
}

class MarkdownAdaptiveTableLayout extends StatelessWidget {
  const MarkdownAdaptiveTableLayout({
    super.key,
    required this.block,
    required this.tableBuilder,
  });

  final TableBlock block;
  final MarkdownTableWidgetBuilder tableBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(constraints.maxWidth, 0.0);

        final columnCount = block.rows.fold<int>(
          0,
          (maxCount, row) =>
              row.cells.length > maxCount ? row.cells.length : maxCount,
        );

        if (columnCount == 0) {
          return const SizedBox.shrink();
        }

        final colMaxChars = List.filled(columnCount, 0);
        for (final row in block.rows) {
          for (var i = 0; i < row.cells.length && i < columnCount; i++) {
            final textLen = _estimateInlineTextLength(row.cells[i].inlines);
            if (textLen > colMaxChars[i]) {
              colMaxChars[i] = textLen;
            }
          }
        }

        final Map<int, TableColumnWidth> customWidths = {};
        double estimatedMins = 0;
        bool hasFlex = false;

        for (var i = 0; i < columnCount; i++) {
          if (colMaxChars[i] > 30) {
            customWidths[i] = FlexColumnWidth(colMaxChars[i].toDouble());
            estimatedMins +=
                80.0; // flex columns are given a generous minimum reasonable width before giving up and scrolling
            hasFlex = true;
          } else {
            customWidths[i] = const IntrinsicColumnWidth();
            // Estimate minimum required space for intrinsic columns to avoid horizontal squashing before scroll triggers
            estimatedMins += math.min(colMaxChars[i] * 10.0 + 24.0, 100.0);
          }
        }

        if (!hasFlex) {
          final table = tableBuilder(null, const IntrinsicColumnWidth());
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          );
        }

        final idealWidth = math.max(availableWidth, estimatedMins);
        final table = tableBuilder(customWidths, const FlexColumnWidth());

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: idealWidth,
              maxWidth: idealWidth,
            ),
            child: table,
          ),
        );
      },
    );
  }
}

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
        borderRadius: theme.quoteBorderRadius,
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
        borderRadius: theme.tableBorderRadius,
        selectionOverlayColor: selectionOverlayColor,
      ),
      child: ClipRRect(
        borderRadius: theme.tableBorderRadius,
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
    this.bulletBuilder,
  });

  final MarkdownThemeData theme;
  final ListBlock block;
  final Widget Function(int index, ListItemNode item) itemBuilder;
  final Key? Function(int index)? itemRowKeyBuilder;
  final Key? Function(int index)? itemContentKeyBuilder;
  final MarkdownBulletBuilder? bulletBuilder;

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
                          child: _buildMarker(context, index),
                        ),
                      ),
                      SizedBox(width: markerGap),
                      Expanded(
                        child: KeyedSubtree(
                          key: itemContentKeyBuilder?.call(index),
                          child: itemBuilder(index, block.items[index]),
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

  Widget _buildMarker(BuildContext context, int index) {
    final item = block.items[index];
    if (bulletBuilder != null) {
      return bulletBuilder!(
        context,
        index,
        block.ordered,
        block.ordered ? block.startIndex : null,
        item.taskState,
        theme,
      );
    }
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
            color: theme.bodyStyle.color?.withValues(alpha: 0.72),
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
    required this.scrollController,
    this.directTextKey,
  });

  final MarkdownThemeData theme;
  final InlineSpan codeSpan;
  final VoidCallback onCopyCode;
  final ScrollController scrollController;
  final GlobalKey? directTextKey;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding = theme.codeBlockPadding.resolve(TextDirection.ltr);
    final effectivePadding = EdgeInsets.fromLTRB(
      resolvedPadding.left,
      resolvedPadding.top,
      math.max(8, resolvedPadding.right - 4),
      resolvedPadding.top,
    );

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.inlineCodeBackgroundColor,
          borderRadius: theme.codeBlockBorderRadius,
        ),
        child: Padding(
          padding: effectivePadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: Text.rich(
                      key: directTextKey,
                      codeSpan,
                      style: theme.codeBlockStyle,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Copy code',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor:
                        theme.bodyStyle.color?.withValues(alpha: 0.72),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: onCopyCode,
                ),
              ),
            ],
          ),
        ),
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
    this.cellKeyBuilder,
    this.cellTextKeyBuilder,
  });

  final MarkdownThemeData theme;
  final TableBlock block;
  final MarkdownInlineTextWidgetBuilder textWidgetBuilder;
  final Key? Function(int rowIndex, int columnIndex)? cellKeyBuilder;
  final GlobalKey? Function(int rowIndex, int columnIndex)? cellTextKeyBuilder;

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
      child: MarkdownAdaptiveTableLayout(
        block: block,
        tableBuilder: (columnWidths, defaultColumnWidth) => Table(
          columnWidths: columnWidths,
          defaultColumnWidth: defaultColumnWidth,
          border: TableBorder(
            horizontalInside: BorderSide(color: theme.tableBorderColor),
            verticalInside: BorderSide(color: theme.tableBorderColor),
          ),
          children: <TableRow>[
            for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++)
              TableRow(
                decoration: BoxDecoration(
                  color: block.rows[rowIndex].isHeader
                      ? theme.tableHeaderBackgroundColor
                      : theme.tableRowBackgroundColor,
                ),
                children: <Widget>[
                  for (var index = 0; index < columnCount; index++)
                    _buildCell(
                      context: context,
                      row: block.rows[rowIndex],
                      rowIndex: rowIndex,
                      cellIndex: index,
                      alignment: index < block.alignments.length
                          ? block.alignments[index]
                          : MarkdownTableColumnAlignment.none,
                      directTextKey: cellTextKeyBuilder?.call(rowIndex, index),
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
    required int rowIndex,
    required int cellIndex,
    required MarkdownTableColumnAlignment alignment,
    GlobalKey? directTextKey,
  }) {
    final cell = cellIndex < row.cells.length
        ? row.cells[cellIndex]
        : const TableCellNode(inlines: <InlineNode>[]);
    final textStyle = row.isHeader ? theme.tableHeaderStyle : theme.bodyStyle;
    Widget child = Padding(
      padding: theme.tableCellPadding.resolve(Directionality.of(context)),
      child: Align(
        alignment: _alignmentFor(alignment),
        child: textWidgetBuilder(
          context,
          textStyle,
          cell.inlines,
          _textAlignFor(alignment),
          directTextKey: directTextKey,
        ),
      ),
    );
    if (cellKeyBuilder != null) {
      child = KeyedSubtree(
        key: cellKeyBuilder!(rowIndex, cellIndex),
        child: child,
      );
    }
    return child;
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
    required this.theme,
    required this.image,
    this.caption,
    this.hasErrorNotifier,
    this.hasKnownSize = false,
  });

  final MarkdownThemeData theme;
  final Widget image;
  final Widget? caption;
  final ValueNotifier<bool>? hasErrorNotifier;
  final bool hasKnownSize;

  @override
  Widget build(BuildContext context) {
    if (hasErrorNotifier == null) {
      return _buildContent(false, image);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: hasErrorNotifier!,
      child: image,
      builder: (context, hasError, imageChild) {
        return _buildContent(hasError, imageChild!);
      },
    );
  }

  Widget _buildContent(bool hasError, Widget imageChild) {
    if (caption == null) {
      return imageChild;
    }

    if (!hasKnownSize && hasError) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.imagePlaceholderBackgroundColor,
          borderRadius: theme.imageBorderRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            imageChild,
            const SizedBox(width: 8),
            Flexible(
              child: DefaultTextStyle.merge(
                style: theme.bodyStyle.copyWith(
                  color: theme.bodyStyle.color?.withValues(alpha: 0.72),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: caption!,
              ),
            ),
          ],
        ),
      );
    }

    final showCaption = hasKnownSize || !hasError;
    if (!showCaption) {
      return imageChild;
    }

    return ImageCaptionLayout(
      image: imageChild,
      spacing: theme.imageCaptionSpacing,
      caption: DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        child: caption!,
      ),
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
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkdownTableFramePainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.selectionOverlayColor != selectionOverlayColor;
  }
}
