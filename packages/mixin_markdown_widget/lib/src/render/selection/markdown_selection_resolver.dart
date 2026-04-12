import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderObject, RenderParagraph;

import '../../core/document.dart';
import '../../widgets/markdown_theme.dart';
import '../code_syntax_highlighter.dart';
import '../markdown_block_widgets.dart';
import '../pretext_text_block.dart';
import 'markdown_descriptor_extractor.dart';
import '../builder/markdown_inline_builder.dart';

class MarkdownBlockKeysRegistry {
  final Map<String, GlobalKey<State<StatefulWidget>>> blockKeys = {};
  final Map<String, List<GlobalKey>> listItemKeysByBlock = {};
  final Map<String, List<GlobalKey>> listItemContentKeysByBlock = {};
  final Map<String, List<List<GlobalKey>>> listItemChildKeysByBlock = {};
  final Map<String, List<GlobalKey>> quoteChildKeysByBlock = {};
  final Map<String, GlobalKey<State<StatefulWidget>>> tableBlockKeys = {};

  List<GlobalKey> listItemKeysFor(ListBlock block) {
    final keys = listItemKeysByBlock.putIfAbsent(block.id, () => <GlobalKey>[]);
    while (keys.length < block.items.length) {
      keys.add(GlobalKey(debugLabel: 'list-${block.id}-${keys.length}'));
    }
    if (keys.length > block.items.length) {
      keys.removeRange(block.items.length, keys.length);
    }
    return keys;
  }

  List<GlobalKey> listItemContentKeysFor(ListBlock block) {
    final keys =
        listItemContentKeysByBlock.putIfAbsent(block.id, () => <GlobalKey>[]);
    while (keys.length < block.items.length) {
      keys.add(
          GlobalKey(debugLabel: 'list-content-${block.id}-${keys.length}'));
    }
    if (keys.length > block.items.length) {
      keys.removeRange(block.items.length, keys.length);
    }
    return keys;
  }

  List<GlobalKey> listItemChildKeysFor(ListBlock block, int itemIndex) {
    final keySets = listItemChildKeysByBlock.putIfAbsent(
        block.id, () => <List<GlobalKey>>[]);
    while (keySets.length < block.items.length) {
      keySets.add(<GlobalKey>[]);
    }
    if (keySets.length > block.items.length) {
      keySets.removeRange(block.items.length, keySets.length);
    }

    final keys = keySets[itemIndex];
    final childCount = block.items[itemIndex].children.length;
    while (keys.length < childCount) {
      keys.add(GlobalKey(
          debugLabel: 'list-child-${block.id}-$itemIndex-${keys.length}'));
    }
    if (keys.length > childCount) {
      keys.removeRange(childCount, keys.length);
    }
    return keys;
  }

  List<GlobalKey> quoteChildKeysFor(QuoteBlock block) {
    final keys =
        quoteChildKeysByBlock.putIfAbsent(block.id, () => <GlobalKey>[]);
    while (keys.length < block.children.length) {
      keys.add(GlobalKey(debugLabel: 'quote-${block.id}-${keys.length}'));
    }
    if (keys.length > block.children.length) {
      keys.removeRange(block.children.length, keys.length);
    }
    return keys;
  }

  void cleanupKeys(Set<String> validIds) {
    blockKeys.removeWhere((key, _) => !validIds.contains(key));
    listItemKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    listItemContentKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    listItemChildKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    quoteChildKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    tableBlockKeys.removeWhere((key, _) => !validIds.contains(key));
  }
}

class MarkdownSelectionResolver {
  const MarkdownSelectionResolver({
    required this.theme,
    required this.extractor,
    required this.keysRegistry,
    required this.codeSyntaxHighlighter,
  });

  final MarkdownThemeData theme;
  final MarkdownDescriptorExtractor extractor;
  final MarkdownBlockKeysRegistry keysRegistry;
  final MarkdownCodeSyntaxHighlighter codeSyntaxHighlighter;

  int tableTextOffsetForCell(
    TableBlock block,
    TableCellPosition position, {
    required bool preferEnd,
  }) {
    var offset = 0;
    for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++) {
      final row = block.rows[rowIndex];
      if (rowIndex > 0) {
        offset += 1;
      }
      for (var columnIndex = 0; columnIndex < row.cells.length; columnIndex++) {
        if (columnIndex > 0) {
          offset += 1;
        }
        final cellText = MarkdownInlineBuilder.flattenInlineText(
            row.cells[columnIndex].inlines);
        final cellStart = offset;
        final cellEnd = cellStart + cellText.length;
        if (rowIndex == position.rowIndex &&
            columnIndex == position.columnIndex) {
          return preferEnd ? cellEnd : cellStart;
        }
        offset = cellEnd;
      }
    }
    return preferEnd ? offset : 0;
  }

  int? resolveListTextOffset(
    BuildContext context,
    ListBlock block,
    Offset localPosition,
  ) {
    final rootRenderObject = context.findRenderObject();
    if (rootRenderObject is! RenderBox || !rootRenderObject.hasSize) {
      return null;
    }

    return _resolveListTextOffsetInRoot(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      globalPosition: rootRenderObject.localToGlobal(localPosition),
    );
  }

  int? _resolveListTextOffsetInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required ListBlock block,
    required Offset globalPosition,
    int indentLevel = 0,
  }) {
    final indexedDescriptors = extractor.buildIndexedListSelectionDescriptors(
      block,
      indentLevel: indentLevel,
    );
    if (indexedDescriptors.isEmpty) {
      return null;
    }

    final contentKeys = keysRegistry.listItemContentKeysFor(block);
    final rowKeys = keysRegistry.listItemKeysFor(block);
    IndexedListSelectionDescriptor? nearestEntry;
    Rect? nearestRowRect;
    double bestDistance = double.infinity;

    for (final entry in indexedDescriptors) {
      final contentContext = contentKeys[entry.itemIndex].currentContext;
      final contentRenderObject = contentContext?.findRenderObject();
      Rect? contentRect;
      List<IndexedBlockDescriptor>? childEntries;
      int? childOffset;
      if (contentRenderObject is RenderBox && contentRenderObject.hasSize) {
        contentRect = contentRenderObject.localToGlobal(Offset.zero) &
            contentRenderObject.size;
        childEntries = extractor.buildIndexedBlockDescriptors(
          block.items[entry.itemIndex].children,
          indentLevel: entry.contentIndentLevel,
          separator: '\n',
        );
        childOffset = resolveIndexedBlockTextOffsetInRoot(
          context,
          rootRenderObject: rootRenderObject,
          entries: childEntries,
          childKeys: keysRegistry.listItemChildKeysFor(block, entry.itemIndex),
          globalPosition: globalPosition,
        );
        if (contentRect.contains(globalPosition)) {
          return entry.startOffset + entry.prefixLength + (childOffset ?? 0);
        }
      }

      final rowContext = rowKeys[entry.itemIndex].currentContext;
      final rowRenderObject = rowContext?.findRenderObject();
      if (rowRenderObject is RenderBox && rowRenderObject.hasSize) {
        final rect =
            rowRenderObject.localToGlobal(Offset.zero) & rowRenderObject.size;
        final dx = globalPosition.dx < rect.left
            ? rect.left - globalPosition.dx
            : globalPosition.dx > rect.right
                ? globalPosition.dx - rect.right
                : 0.0;
        final dy = globalPosition.dy < rect.top
            ? rect.top - globalPosition.dy
            : globalPosition.dy > rect.bottom
                ? globalPosition.dy - rect.bottom
                : 0.0;
        final distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
          bestDistance = distance;
          nearestEntry = entry;
          nearestRowRect = rect;
        }
        if (rect.contains(globalPosition)) {
          final localRowPosition =
              rowRenderObject.globalToLocal(globalPosition);
          final markerWidth = math.min(
            markdownListMarkerWidth(block, entry.itemIndex),
            rowRenderObject.size.width,
          );
          final markerExtent = _resolveListMarkerExtent(
            block: block,
            itemIndex: entry.itemIndex,
            rowRenderObject: rowRenderObject,
            contentRenderObject:
                contentRenderObject is RenderBox ? contentRenderObject : null,
          );
          if (localRowPosition.dx <= markerWidth) {
            return entry.startOffset;
          }
          if (contentRect != null &&
              childEntries != null &&
              globalPosition.dy >= contentRect.top &&
              globalPosition.dy <= contentRect.bottom) {
            final projectedChildOffset = resolveIndexedBlockTextOffsetInRoot(
              context,
              rootRenderObject: rootRenderObject,
              entries: childEntries,
              childKeys:
                  keysRegistry.listItemChildKeysFor(block, entry.itemIndex),
              globalPosition: Offset(
                contentRect.left + 1,
                globalPosition.dy.clamp(
                  contentRect.top + 0.5,
                  contentRect.bottom - 0.5,
                ),
              ),
            );
            if (projectedChildOffset != null) {
              return entry.startOffset +
                  entry.prefixLength +
                  projectedChildOffset;
            }
          }
          if (localRowPosition.dx <= markerExtent) {
            return entry.startOffset;
          }
          return entry.startOffset + entry.prefixLength + (childOffset ?? 0);
        }
      }
    }

    if (nearestEntry != null && nearestRowRect != null) {
      final preferEnd = globalPosition.dy > nearestRowRect.center.dy ||
          globalPosition.dx > nearestRowRect.center.dx;
      return nearestEntry.startOffset +
          (preferEnd ? nearestEntry.descriptor.plainText.length : 0);
    }

    return null;
  }

  int resolveTextOffsetInBox(
    InlineSpan span,
    int textLength,
    Offset localPosition,
    Size size,
    TextDirection textDirection,
  ) {
    final textPainter = TextPainter(
      text: span,
      textDirection: textDirection,
      maxLines: null,
    )..layout(maxWidth: size.width);
    final clampedOffset = Offset(
      localPosition.dx.clamp(0.0, math.max(textPainter.width, 0.0)),
      localPosition.dy.clamp(0.0, math.max(textPainter.height, 0.0)),
    );
    final textPosition = textPainter.getPositionForOffset(clampedOffset);
    final offset = textPosition.offset;
    if (offset < 0) {
      return 0;
    }
    if (offset > textLength) {
      return textLength;
    }
    return offset;
  }

  int resolveDescriptorTextOffset(
    BuildContext context, {
    required SelectableTextDescriptor descriptor,
    required Offset localPosition,
    required Size size,
    required TextDirection textDirection,
  }) {
    final pretext = descriptor.pretext;
    if (pretext != null) {
      final layout = computeDescriptorPretextLayout(
        context,
        descriptor: descriptor,
        maxWidth: size.width,
        textDirection: textDirection,
      );
      return layout.textOffsetAt(
        localPosition,
        textDirection: textDirection,
      );
    }

    return resolveTextOffsetInBox(
      descriptor.span,
      descriptor.plainText.length,
      localPosition,
      size,
      textDirection,
    );
  }

  MarkdownPretextLayoutResult computeDescriptorPretextLayout(
    BuildContext context, {
    required SelectableTextDescriptor descriptor,
    required double maxWidth,
    required TextDirection textDirection,
  }) {
    final pretext = descriptor.pretext!;
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    return computeMarkdownPretextLayoutFromRuns(
      runs: pretext.runs,
      fallbackStyle: pretext.fallbackStyle,
      maxWidth: maxWidth,
      textScaleFactor: textScaler.scale(1.0),
      textAlign: pretext.textAlign,
      textDirection: textDirection,
    );
  }

  bool _descriptorUsesDirectRichTextMetrics(
    SelectableTextDescriptor descriptor,
  ) {
    final pretext = descriptor.pretext;
    return pretext != null &&
        markdownPretextCanUseDirectRichTextGeometry(pretext.runs);
  }

  RenderParagraph? _findDirectRenderParagraphForRuns(
    RenderObject renderObject,
    List<MarkdownPretextInlineRun> runs,
  ) {
    final expectedRenderText = markdownPretextRenderText(runs);
    RenderParagraph? paragraph;

    void visit(RenderObject node) {
      if (node is RenderParagraph &&
          node.text.toPlainText(includePlaceholders: true) ==
              expectedRenderText) {
        paragraph = node;
        return;
      }
      if (paragraph != null) {
        return;
      }
      node.visitChildren(visit);
    }

    visit(renderObject);
    return paragraph;
  }

  int? _resolveDirectRenderParagraphTextOffset(
    RenderObject renderObject, {
    required Offset globalPosition,
    required List<MarkdownPretextInlineRun> runs,
  }) {
    final paragraph = _findDirectRenderParagraphForRuns(renderObject, runs);
    if (paragraph == null || !paragraph.hasSize) {
      return null;
    }

    final localPosition = paragraph.globalToLocal(globalPosition);
    final textPosition = paragraph.getPositionForOffset(localPosition);
    return markdownPretextPlainOffsetForRenderOffset(runs, textPosition.offset);
  }

  List<Rect>? _resolveDirectRenderParagraphSelectionRects(
    RenderBox renderObject, {
    required DocumentRange range,
    required Offset origin,
    required List<MarkdownPretextInlineRun> runs,
  }) {
    final paragraph = _findDirectRenderParagraphForRuns(renderObject, runs);
    if (paragraph == null || !paragraph.hasSize) {
      return null;
    }

    final renderSelection = TextSelection(
      baseOffset: markdownPretextRenderOffsetForPlainOffset(
        runs,
        range.start.textOffset,
        preferEnd: false,
      ),
      extentOffset: markdownPretextRenderOffsetForPlainOffset(
        runs,
        range.end.textOffset,
        preferEnd: true,
      ),
    );
    final paragraphOrigin = renderObject.globalToLocal(
      paragraph.localToGlobal(Offset.zero),
    );
    final lineExtents = _computeParagraphLineExtents(paragraph);
    final boxes = _mergeAdjacentTextSelectionBoxes(
      _normalizeBoxesToLineExtents(
        paragraph.getBoxesForSelection(renderSelection),
        lineExtents,
      ),
    );
    return boxes
        .map(
          (box) => Rect.fromLTRB(
            box.left + paragraphOrigin.dx + origin.dx - 1.5,
            box.top + paragraphOrigin.dy + origin.dy,
            box.right + paragraphOrigin.dx + origin.dx + 1.5,
            box.bottom + paragraphOrigin.dy + origin.dy,
          ),
        )
        .toList(growable: false);
  }

  FlutterError _missingDirectRenderParagraphError(
    SelectableTextDescriptor descriptor,
  ) {
    final plainText = descriptor.plainText;
    final snippet = plainText.length <= 120
        ? plainText
        : '${plainText.substring(0, 120)}...';
    final renderText = descriptor.pretext == null
        ? plainText
        : markdownPretextRenderText(descriptor.pretext!.runs);
    return FlutterError(
      'Expected a live RenderParagraph for a direct-geometry markdown block, '
      'but none could be resolved. This block must not fall back to a different '
      'geometry model because that produces incorrect selection rects and hit '
      'testing. plainText="$snippet" renderText="$renderText"',
    );
  }

  List<Rect> resolveDescriptorSelectionRects(
    BuildContext context, {
    required SelectableTextDescriptor descriptor,
    required DocumentRange range,
    required Size size,
    required TextDirection textDirection,
    Offset origin = Offset.zero,
  }) {
    final pretext = descriptor.pretext;
    if (pretext != null) {
      final layout = computeDescriptorPretextLayout(
        context,
        descriptor: descriptor,
        maxWidth: size.width,
        textDirection: textDirection,
      );
      return layout
          .selectionRectsForRange(range, textDirection: textDirection)
          .map((rect) => rect.shift(origin))
          .toList(growable: false);
    }

    final textPainter = TextPainter(
      text: descriptor.span,
      textDirection: textDirection,
      maxLines: null,
    )..layout(maxWidth: size.width);
    final boxes = textPainter.getBoxesForSelection(
      TextSelection(
        baseOffset: range.start.textOffset,
        extentOffset: range.end.textOffset,
      ),
    );
    return boxes
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

  List<Rect> resolveListSelectionRects(
    BuildContext context,
    ListBlock block,
    DocumentRange range,
  ) {
    final rootRenderObject = context.findRenderObject();
    if (rootRenderObject is! RenderBox || !rootRenderObject.hasSize) {
      return const <Rect>[];
    }

    return _resolveListSelectionRectsInRoot(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      range: range,
    );
  }

  List<Rect> _resolveListSelectionRectsInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required ListBlock block,
    required DocumentRange range,
    int indentLevel = 0,
  }) {
    final indexedDescriptors = extractor.buildIndexedListSelectionDescriptors(
      block,
      indentLevel: indentLevel,
    );
    if (indexedDescriptors.isEmpty) {
      return const <Rect>[];
    }

    final rects = <Rect>[];
    final rowKeys = keysRegistry.listItemKeysFor(block);
    final contentKeys = keysRegistry.listItemContentKeysFor(block);

    for (final entry in indexedDescriptors) {
      final itemStart = entry.startOffset;
      final itemEnd = itemStart + entry.descriptor.plainText.length;
      final contentSelectionStart = math.max(
        range.start.textOffset,
        itemStart + entry.prefixLength,
      );
      final contentSelectionEnd = math.min(range.end.textOffset, itemEnd);
      final prefixSelectionStart = math.max(range.start.textOffset, itemStart);
      final prefixSelectionEnd = math.min(
        range.end.textOffset,
        itemStart + entry.prefixLength,
      );
      if (contentSelectionStart >= contentSelectionEnd &&
          prefixSelectionStart >= prefixSelectionEnd) {
        continue;
      }

      final contentContext = contentKeys[entry.itemIndex].currentContext;
      final contentRenderObject = contentContext?.findRenderObject();
      final rowContext = rowKeys[entry.itemIndex].currentContext;
      final rowRenderObject = rowContext?.findRenderObject();
      Rect? prefixRect;
      var contentRects = const <Rect>[];
      if (contentSelectionStart < contentSelectionEnd &&
          contentRenderObject is RenderBox &&
          contentRenderObject.hasSize) {
        final itemRange = DocumentRange(
          start: DocumentPosition(
            blockIndex: 0,
            path: const PathInBlock(<int>[0]),
            textOffset: contentSelectionStart - itemStart - entry.prefixLength,
          ),
          end: DocumentPosition(
            blockIndex: 0,
            path: const PathInBlock(<int>[0]),
            textOffset: contentSelectionEnd - itemStart - entry.prefixLength,
          ),
        );
        final childEntries = extractor.buildIndexedBlockDescriptors(
          block.items[entry.itemIndex].children,
          indentLevel: entry.contentIndentLevel,
          separator: '\n',
        );
        contentRects = resolveIndexedBlockSelectionRectsInRoot(
          context,
          rootRenderObject: rootRenderObject,
          entries: childEntries,
          childKeys: keysRegistry.listItemChildKeysFor(block, entry.itemIndex),
          range: itemRange,
        );
      }

      if (prefixSelectionStart < prefixSelectionEnd &&
          rowRenderObject is RenderBox &&
          rowRenderObject.hasSize) {
        prefixRect = _resolveListPrefixSelectionRectInRoot(
          context: context,
          rootRenderObject: rootRenderObject,
          block: block,
          itemIndex: entry.itemIndex,
          rowRenderObject: rowRenderObject,
          contentRenderObject:
              contentRenderObject is RenderBox ? contentRenderObject : null,
          contentIndentLevel: entry.contentIndentLevel,
          textDirection: Directionality.of(context),
        );
      }

      if (contentSelectionStart >= contentSelectionEnd) {
        if (prefixRect != null) {
          rects.add(prefixRect);
        }
        continue;
      }

      if (contentRenderObject is! RenderBox || !contentRenderObject.hasSize) {
        if (prefixRect != null) {
          rects.add(prefixRect);
        }
        continue;
      }

      if (prefixRect != null && contentRects.isNotEmpty) {
        final firstContentRect = contentRects.first;
        if (_rectsShareLine(prefixRect, firstContentRect)) {
          rects.add(
            Rect.fromLTRB(
              prefixRect.left,
              firstContentRect.top,
              firstContentRect.right,
              firstContentRect.bottom,
            ),
          );
          rects.addAll(contentRects.skip(1));
          continue;
        }
        rects.add(prefixRect);
      }

      rects.addAll(contentRects);
    }

    return rects;
  }

  Rect _resolveListPrefixSelectionRectInRoot({
    required BuildContext context,
    required RenderBox rootRenderObject,
    required ListBlock block,
    required int itemIndex,
    required RenderBox rowRenderObject,
    RenderBox? contentRenderObject,
    required int contentIndentLevel,
    required TextDirection textDirection,
  }) {
    final rowOrigin = rootRenderObject.globalToLocal(
      rowRenderObject.localToGlobal(Offset.zero),
    );
    var top = rowOrigin.dy;
    var height = rowRenderObject.size.height;
    final childEntries = extractor.buildIndexedBlockDescriptors(
      block.items[itemIndex].children,
      indentLevel: contentIndentLevel,
      separator: '\n',
    );
    final childKeys = keysRegistry.listItemChildKeysFor(block, itemIndex);
    if (childEntries.isNotEmpty && childKeys.isNotEmpty) {
      final firstEntry = childEntries.first;
      final firstChildContext = childKeys[firstEntry.childIndex].currentContext;
      final firstChildRenderObject = firstChildContext?.findRenderObject();
      if (firstChildRenderObject is RenderBox &&
          firstChildRenderObject.hasSize) {
        final firstChildOrigin = rootRenderObject.globalToLocal(
          firstChildRenderObject.localToGlobal(Offset.zero),
        );
        final firstLineRect = _resolveFirstLineRectForNestedBlockInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: firstEntry.block,
          descriptor: firstEntry.descriptor,
          renderObject: firstChildRenderObject,
          origin: firstChildOrigin,
          textDirection: textDirection,
          indentLevel: firstEntry.indentLevel,
        );
        if (firstLineRect != null) {
          top = firstLineRect.top;
          height = firstLineRect.height;
        } else {
          top = firstChildOrigin.dy;
          height = firstChildRenderObject.size.height;
        }
      }
    }

    final extent = _resolveListMarkerExtent(
      block: block,
      itemIndex: itemIndex,
      rowRenderObject: rowRenderObject,
      contentRenderObject: contentRenderObject,
    );
    return Rect.fromLTRB(
      rowOrigin.dx,
      top,
      rowOrigin.dx + extent,
      top + height,
    );
  }

  bool _rectsShareLine(Rect a, Rect b) {
    final overlapTop = math.max(a.top, b.top);
    final overlapBottom = math.min(a.bottom, b.bottom);
    return overlapBottom - overlapTop > 1.0;
  }

  double _resolveListMarkerExtent({
    required ListBlock block,
    required int itemIndex,
    required RenderBox rowRenderObject,
    RenderBox? contentRenderObject,
  }) {
    if (contentRenderObject != null && contentRenderObject.hasSize) {
      final contentOrigin = rowRenderObject.globalToLocal(
        contentRenderObject.localToGlobal(Offset.zero),
      );
      if (contentOrigin.dx > 0) {
        return math.min(contentOrigin.dx, rowRenderObject.size.width);
      }
    }
    return math.min(
      markdownListMarkerExtent(block, itemIndex),
      rowRenderObject.size.width,
    );
  }

  Rect? _resolveFirstLineRectForNestedBlockInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required BlockNode block,
    required SelectableTextDescriptor descriptor,
    required RenderBox renderObject,
    required Offset origin,
    required TextDirection textDirection,
    required int indentLevel,
  }) {
    if (descriptor.plainText.isEmpty) {
      return null;
    }

    final rects = resolveNestedBlockSelectionRects(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      descriptor: descriptor,
      range: DocumentRange(
        start: const DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: math.min(1, descriptor.plainText.length),
        ),
      ),
      renderObject: renderObject,
      origin: origin,
      textDirection: textDirection,
      indentLevel: indentLevel,
    );
    if (rects.isEmpty) {
      return null;
    }
    rects.sort((a, b) {
      final topCompare = a.top.compareTo(b.top);
      if (topCompare != 0) {
        return topCompare;
      }
      return a.left.compareTo(b.left);
    });
    return rects.first;
  }

  List<Rect> resolveQuoteSelectionRects(
    BuildContext context,
    QuoteBlock block,
    DocumentRange range,
  ) {
    final rootRenderObject = context.findRenderObject();
    if (rootRenderObject is! RenderBox || !rootRenderObject.hasSize) {
      return const <Rect>[];
    }
    return _resolveQuoteSelectionRectsInRoot(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      range: range,
    );
  }

  List<Rect> _resolveQuoteSelectionRectsInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required QuoteBlock block,
    required DocumentRange range,
  }) {
    final entries = extractor.buildIndexedBlockDescriptors(
      block.children,
      separator: '\n\n',
    );
    if (entries.isEmpty) {
      return const <Rect>[];
    }
    return resolveIndexedBlockSelectionRectsInRoot(
      context,
      rootRenderObject: rootRenderObject,
      entries: entries,
      childKeys: keysRegistry.quoteChildKeysFor(block),
      range: range,
    );
  }

  int? resolveQuoteTextOffset(
    BuildContext context,
    QuoteBlock block,
    Offset localPosition,
  ) {
    final rootRenderObject = context.findRenderObject();
    if (rootRenderObject is! RenderBox || !rootRenderObject.hasSize) {
      return null;
    }
    return _resolveQuoteTextOffsetInRoot(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      globalPosition: rootRenderObject.localToGlobal(localPosition),
    );
  }

  int? _resolveQuoteTextOffsetInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required QuoteBlock block,
    required Offset globalPosition,
  }) {
    final entries = extractor.buildIndexedBlockDescriptors(
      block.children,
      separator: '\n\n',
    );
    if (entries.isEmpty) {
      return null;
    }
    return resolveIndexedBlockTextOffsetInRoot(
      context,
      rootRenderObject: rootRenderObject,
      entries: entries,
      childKeys: keysRegistry.quoteChildKeysFor(block),
      globalPosition: globalPosition,
    );
  }

  List<Rect> resolveIndexedBlockSelectionRectsInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required List<IndexedBlockDescriptor> entries,
    required List<GlobalKey> childKeys,
    required DocumentRange range,
  }) {
    final textDirection = Directionality.of(context);
    final rects = <Rect>[];

    for (final entry in entries) {
      final childStart = entry.startOffset;
      final childEnd = childStart + entry.descriptor.plainText.length;
      final selectionStart = math.max(range.start.textOffset, childStart);
      final selectionEnd = math.min(range.end.textOffset, childEnd);
      if (selectionStart >= selectionEnd) {
        continue;
      }

      final childContext = childKeys[entry.childIndex].currentContext;
      final childRenderObject = childContext?.findRenderObject();
      if (childRenderObject is! RenderBox || !childRenderObject.hasSize) {
        continue;
      }
      final childOrigin = rootRenderObject.globalToLocal(
        childRenderObject.localToGlobal(Offset.zero),
      );
      final childRange = DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: selectionStart - childStart,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: selectionEnd - childStart,
        ),
      );

      rects.addAll(
        resolveNestedBlockSelectionRects(
          context,
          rootRenderObject: rootRenderObject,
          block: entry.block,
          descriptor: entry.descriptor,
          range: childRange,
          renderObject: childRenderObject,
          origin: childOrigin,
          textDirection: textDirection,
          indentLevel: entry.indentLevel,
        ),
      );
    }

    return rects;
  }

  int? resolveIndexedBlockTextOffsetInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required List<IndexedBlockDescriptor> entries,
    required List<GlobalKey> childKeys,
    required Offset globalPosition,
  }) {
    final textDirection = Directionality.of(context);
    final resolvedEntries = <ResolvedIndexedBlockEntry>[];
    IndexedBlockDescriptor? nearestEntry;
    double bestDistance = double.infinity;

    for (final entry in entries) {
      final childContext = childKeys[entry.childIndex].currentContext;
      final childRenderObject = childContext?.findRenderObject();
      if (childRenderObject is! RenderBox || !childRenderObject.hasSize) {
        continue;
      }
      final rect =
          childRenderObject.localToGlobal(Offset.zero) & childRenderObject.size;
      resolvedEntries.add(
        ResolvedIndexedBlockEntry(
          entry: entry,
          renderObject: childRenderObject,
          rect: rect,
        ),
      );
      if (rect.contains(globalPosition)) {
        return entry.startOffset +
            resolveNestedBlockTextOffset(
              context,
              rootRenderObject: rootRenderObject,
              block: entry.block,
              descriptor: entry.descriptor,
              renderObject: childRenderObject,
              globalPosition: globalPosition,
              textDirection: textDirection,
              indentLevel: entry.indentLevel,
            );
      }
      final dx = globalPosition.dx < rect.left
          ? rect.left - globalPosition.dx
          : globalPosition.dx > rect.right
              ? globalPosition.dx - rect.right
              : 0.0;
      final dy = globalPosition.dy < rect.top
          ? rect.top - globalPosition.dy
          : globalPosition.dy > rect.bottom
              ? globalPosition.dy - rect.bottom
              : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        nearestEntry = entry;
      }
    }

    resolvedEntries.sort((a, b) => a.rect.top.compareTo(b.rect.top));
    for (var index = 0; index < resolvedEntries.length - 1; index++) {
      final current = resolvedEntries[index];
      final next = resolvedEntries[index + 1];
      if (globalPosition.dy < current.rect.bottom ||
          globalPosition.dy > next.rect.top) {
        continue;
      }

      final overlapLeft = math.min(current.rect.right, next.rect.right);
      final overlapRight = math.max(current.rect.left, next.rect.left);
      if (globalPosition.dx < overlapRight - 24 ||
          globalPosition.dx > overlapLeft + 24) {
        continue;
      }

      final midpointY = (current.rect.bottom + next.rect.top) / 2;
      if (globalPosition.dy <= midpointY) {
        return current.entry.startOffset +
            current.entry.descriptor.plainText.length;
      }
      return next.entry.startOffset;
    }

    if (nearestEntry == null) {
      return null;
    }

    final childContext = childKeys[nearestEntry.childIndex].currentContext;
    final childRenderObject = childContext?.findRenderObject();
    if (childRenderObject is! RenderBox || !childRenderObject.hasSize) {
      return null;
    }
    final childRect =
        childRenderObject.localToGlobal(Offset.zero) & childRenderObject.size;
    final preferEnd = globalPosition.dy > childRect.center.dy ||
        globalPosition.dx > childRect.center.dx;
    return nearestEntry.startOffset +
        (preferEnd ? nearestEntry.descriptor.plainText.length : 0);
  }

  List<Rect> resolveNestedBlockSelectionRects(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required BlockNode block,
    required SelectableTextDescriptor descriptor,
    required DocumentRange range,
    required RenderBox renderObject,
    required Offset origin,
    required TextDirection textDirection,
    int indentLevel = 0,
  }) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.definitionList:
        if (_descriptorUsesDirectRichTextMetrics(descriptor)) {
          final directRects = _resolveDirectRenderParagraphSelectionRects(
            renderObject,
            range: range,
            origin: origin,
            runs: descriptor.pretext!.runs,
          );
          if (directRects != null) {
            return directRects;
          }
          throw _missingDirectRenderParagraphError(descriptor);
        }
        return resolveDescriptorSelectionRects(
          context,
          descriptor: descriptor,
          range: range,
          size: renderObject.size,
          textDirection: textDirection,
          origin: origin,
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _resolveListSelectionRectsInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: block as ListBlock,
          range: range,
          indentLevel: indentLevel,
        );
      case MarkdownBlockKind.footnoteList:
        return _resolveListSelectionRectsInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: MarkdownDescriptorExtractor.footnoteListAsOrderedList(
              block as FootnoteListBlock),
          range: range,
          indentLevel: indentLevel,
        );
      case MarkdownBlockKind.quote:
        return _resolveQuoteSelectionRectsInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: block as QuoteBlock,
          range: range,
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        final codeRuns = codeSyntaxHighlighter.buildPretextRuns(
          source: codeBlock.code,
          baseStyle: theme.codeBlockStyle,
          theme: theme,
          language: codeBlock.language,
        );
        if (markdownPretextCanUseDirectRichTextGeometry(codeRuns)) {
          final directRects = _resolveDirectRenderParagraphSelectionRects(
            renderObject,
            range: range,
            origin: origin,
            runs: codeRuns,
          );
          if (directRects != null) {
            return directRects;
          }
          throw _missingDirectRenderParagraphError(descriptor);
        }
        return resolveTextSpanSelectionRects(
          codeSyntaxHighlighter.buildTextSpan(
            source: codeBlock.code,
            baseStyle: theme.codeBlockStyle,
            theme: theme,
            language: codeBlock.language,
          ),
          range,
          size: renderObject.size,
          textDirection: textDirection,
          measurementPadding:
              theme.codeBlockPadding.resolve(Directionality.of(context)) +
                  const EdgeInsets.only(top: 36), // _codeToolbarHeight
          origin: origin,
        );
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        final rect = origin & renderObject.size;
        return <Rect>[
          Rect.fromLTRB(rect.left - 1.5, rect.top, rect.right + 1.5, rect.bottom),
        ];
    }
  }

  int resolveNestedBlockTextOffset(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required BlockNode block,
    required SelectableTextDescriptor descriptor,
    required RenderBox renderObject,
    required Offset globalPosition,
    required TextDirection textDirection,
    int indentLevel = 0,
  }) {
    final localPosition = renderObject.globalToLocal(globalPosition);
    switch (block.kind) {
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.definitionList:
        if (_descriptorUsesDirectRichTextMetrics(descriptor)) {
          final directOffset = _resolveDirectRenderParagraphTextOffset(
            renderObject,
            globalPosition: globalPosition,
            runs: descriptor.pretext!.runs,
          );
          if (directOffset != null) {
            return directOffset;
          }
          throw _missingDirectRenderParagraphError(descriptor);
        }
        return resolveDescriptorTextOffset(
          context,
          descriptor: descriptor,
          localPosition: localPosition,
          size: renderObject.size,
          textDirection: textDirection,
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _resolveListTextOffsetInRoot(
              context,
              rootRenderObject: rootRenderObject,
              block: block as ListBlock,
              globalPosition: globalPosition,
              indentLevel: indentLevel,
            ) ??
            0;
      case MarkdownBlockKind.footnoteList:
        return _resolveListTextOffsetInRoot(
              context,
              rootRenderObject: rootRenderObject,
              block: MarkdownDescriptorExtractor.footnoteListAsOrderedList(
                  block as FootnoteListBlock),
              globalPosition: globalPosition,
              indentLevel: indentLevel,
            ) ??
            0;
      case MarkdownBlockKind.quote:
        return _resolveQuoteTextOffsetInRoot(
              context,
              rootRenderObject: rootRenderObject,
              block: block as QuoteBlock,
              globalPosition: globalPosition,
            ) ??
            0;
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        final codeRuns = codeSyntaxHighlighter.buildPretextRuns(
          source: codeBlock.code,
          baseStyle: theme.codeBlockStyle,
          theme: theme,
          language: codeBlock.language,
        );
        if (markdownPretextCanUseDirectRichTextGeometry(codeRuns)) {
          final directOffset = _resolveDirectRenderParagraphTextOffset(
            renderObject,
            globalPosition: globalPosition,
            runs: codeRuns,
          );
          if (directOffset != null) {
            return directOffset;
          }
          throw _missingDirectRenderParagraphError(descriptor);
        }
        return resolveTextSpanTextOffset(
          codeSyntaxHighlighter.buildTextSpan(
            source: codeBlock.code,
            baseStyle: theme.codeBlockStyle,
            theme: theme,
            language: codeBlock.language,
          ),
          descriptor.plainText.length,
          localPosition: localPosition,
          size: renderObject.size,
          textDirection: textDirection,
          measurementPadding:
              theme.codeBlockPadding.resolve(Directionality.of(context)) +
                  const EdgeInsets.only(top: 36), // _codeToolbarHeight
        );
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        return localPosition.dy > renderObject.size.height / 2 ||
                localPosition.dx > renderObject.size.width / 2
            ? descriptor.plainText.length
            : 0;
    }
  }

  List<Rect> resolveTextSpanSelectionRects(
    InlineSpan span,
    DocumentRange range, {
    required Size size,
    required TextDirection textDirection,
    required EdgeInsets measurementPadding,
    Offset origin = Offset.zero,
  }) {
    final textPainter = TextPainter(
      text: span,
      textDirection: textDirection,
      maxLines: null,
    )..layout(
        maxWidth: math.max(size.width - measurementPadding.horizontal, 0),
      );
    final lineExtents = _computeTextPainterLineExtents(textPainter);
    final boxes = _mergeAdjacentTextSelectionBoxes(
      _normalizeBoxesToLineExtents(
        textPainter.getBoxesForSelection(
          TextSelection(
            baseOffset: range.start.textOffset,
            extentOffset: range.end.textOffset,
          ),
        ),
        lineExtents,
      ),
    );
    return boxes
        .map(
          (box) => Rect.fromLTRB(
            box.left + measurementPadding.left + origin.dx - 1.5,
            box.top + measurementPadding.top + origin.dy,
            box.right + measurementPadding.left + origin.dx + 1.5,
            box.bottom + measurementPadding.top + origin.dy,
          ),
        )
        .toList(growable: false);
  }

  List<({double top, double bottom})> _computeParagraphLineExtents(
    RenderParagraph renderParagraph,
  ) {
    final fullText =
        renderParagraph.text.toPlainText(includePlaceholders: true);
    if (fullText.isEmpty) {
      return const <({double top, double bottom})>[];
    }
    final allBoxes = renderParagraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: fullText.length),
    );
    if (allBoxes.isEmpty) {
      return const <({double top, double bottom})>[];
    }
    return _resolveContiguousLinesFromBoxes(allBoxes);
  }

  List<({double top, double bottom})> _computeTextPainterLineExtents(
    TextPainter textPainter,
  ) {
    final fullText = textPainter.text?.toPlainText(includePlaceholders: true) ?? '';
    if (fullText.isEmpty) {
      return const <({double top, double bottom})>[];
    }
    final allBoxes = textPainter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: fullText.length),
    );
    if (allBoxes.isEmpty) {
      return const <({double top, double bottom})>[];
    }
    return _resolveContiguousLinesFromBoxes(allBoxes);
  }

  List<({double top, double bottom})> _resolveContiguousLinesFromBoxes(
      List<TextBox> allBoxes) {
    final sorted = allBoxes.toList(growable: false)
      ..sort((a, b) => a.top.compareTo(b.top));

    final lines = <({double top, double bottom})>[];
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

    final contiguousLines = <({double top, double bottom})>[];
    for (var i = 0; i < lines.length; i++) {
      final current = lines[i];
      final previous = i > 0 ? lines[i - 1] : null;
      final next = i < lines.length - 1 ? lines[i + 1] : null;

      final resolvedTop = previous != null
          ? (previous.bottom + current.top) / 2.0
          : current.top;
      final resolvedBottom = next != null
          ? (current.bottom + next.top) / 2.0
          : current.bottom;

      contiguousLines.add((top: resolvedTop, bottom: resolvedBottom));
    }
    return contiguousLines;
  }

  List<TextBox> _normalizeBoxesToLineExtents(
    List<TextBox> boxes,
    List<({double top, double bottom})> lineExtents,
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

  List<TextBox> _mergeAdjacentTextSelectionBoxes(List<TextBox> boxes) {
    if (boxes.length < 2) {
      return boxes;
    }

    const lineTolerance = 2.0;
    const gapTolerance = double.infinity;

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
      final overlappingOrAdjacent = next.left <= current.right + gapTolerance;
      if (sameLine && overlappingOrAdjacent) {
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

  int resolveTextSpanTextOffset(
    InlineSpan span,
    int textLength, {
    required Offset localPosition,
    required Size size,
    required TextDirection textDirection,
    required EdgeInsets measurementPadding,
  }) {
    return resolveTextOffsetInBox(
      span,
      textLength,
      Offset(
        localPosition.dx - measurementPadding.left,
        localPosition.dy - measurementPadding.top,
      ),
      Size(
        math.max(size.width - measurementPadding.horizontal, 0),
        math.max(size.height - measurementPadding.vertical, 0),
      ),
      textDirection,
    );
  }
}
