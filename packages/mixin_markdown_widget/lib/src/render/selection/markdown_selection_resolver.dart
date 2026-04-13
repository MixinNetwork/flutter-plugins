import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderObject, RenderParagraph;

import '../../core/document.dart';
import '../../widgets/markdown_theme.dart';
import '../code_syntax_highlighter.dart';
import '../markdown_block_widgets.dart';
import '../builder/markdown_inline_builder.dart';
import '../pretext_text_block.dart';
import 'markdown_descriptor_extractor.dart';

class MarkdownBlockKeysRegistry {
  final Map<String, GlobalKey<State<StatefulWidget>>> blockKeys = {};
  final Map<String, List<GlobalKey>> listItemKeysByBlock = {};
  final Map<String, List<GlobalKey>> listItemContentKeysByBlock = {};
  final Map<String, List<List<GlobalKey>>> listItemChildKeysByBlock = {};
  final Map<String, List<GlobalKey>> quoteChildKeysByBlock = {};
  final Map<String, List<List<GlobalKey>>> tableCellKeysByBlock = {};
  final Map<String, List<List<GlobalKey>>> tableCellTextKeysByBlock = {};
  final Map<String, GlobalKey<State<StatefulWidget>>> tableBlockKeys = {};
  final Map<String, ScrollController> codeBlockScrollControllers = {};
  final Map<String, ValueNotifier<bool>> imageErrorNotifiers = {};

  List<List<GlobalKey>> tableCellKeysFor(TableBlock block) {
    return _ensureTableKeys(block, tableCellKeysByBlock, 'table');
  }

  List<List<GlobalKey>> tableCellTextKeysFor(TableBlock block) {
    return _ensureTableKeys(block, tableCellTextKeysByBlock, 'table-text');
  }

  List<List<GlobalKey>> _ensureTableKeys(
    TableBlock block,
    Map<String, List<List<GlobalKey>>> registry,
    String prefix,
  ) {
    final keys = registry.putIfAbsent(block.id, () => <List<GlobalKey>>[]);
    while (keys.length < block.rows.length) {
      keys.add(<GlobalKey>[]);
    }
    if (keys.length > block.rows.length) {
      keys.removeRange(block.rows.length, keys.length);
    }
    for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++) {
      final rowKeys = keys[rowIndex];
      final row = block.rows[rowIndex];
      while (rowKeys.length < row.cells.length) {
        rowKeys.add(GlobalKey(
            debugLabel: '$prefix-${block.id}-$rowIndex-${rowKeys.length}'));
      }
      if (rowKeys.length > row.cells.length) {
        rowKeys.removeRange(row.cells.length, rowKeys.length);
      }
    }
    return keys;
  }

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
    tableCellKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    tableCellTextKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    tableBlockKeys.removeWhere((key, _) => !validIds.contains(key));
    final staleCodeBlockIds = codeBlockScrollControllers.keys
        .where((key) => !validIds.contains(key))
        .toList(growable: false);
    for (final blockId in staleCodeBlockIds) {
      codeBlockScrollControllers.remove(blockId)?.dispose();
    }
    final staleImageNotifierIds = imageErrorNotifiers.keys
        .where((key) => !validIds.contains(key))
        .toList(growable: false);
    for (final blockId in staleImageNotifierIds) {
      imageErrorNotifiers.remove(blockId)?.dispose();
    }
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

  DocumentRange? resolveListSelectionUnitRange(
    BuildContext context,
    ListBlock block,
    Offset localPosition,
    DocumentPosition position,
  ) {
    final rootRenderObject = context.findRenderObject();
    if (rootRenderObject is! RenderBox || !rootRenderObject.hasSize) {
      return null;
    }

    return _resolveListSelectionUnitRangeInRoot(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      globalPosition: rootRenderObject.localToGlobal(localPosition),
      blockIndex: position.blockIndex,
    );
  }

  DocumentRange? resolveQuoteSelectionUnitRange(
    BuildContext context,
    QuoteBlock block,
    Offset localPosition,
    DocumentPosition position,
  ) {
    final rootRenderObject = context.findRenderObject();
    if (rootRenderObject is! RenderBox || !rootRenderObject.hasSize) {
      return null;
    }

    return _resolveQuoteSelectionUnitRangeInRoot(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      globalPosition: rootRenderObject.localToGlobal(localPosition),
      blockIndex: position.blockIndex,
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
        final childKeys =
            keysRegistry.listItemChildKeysFor(block, entry.itemIndex);
        var childContainsPosition = false;
        for (final childEntry in childEntries) {
          final childContext = childKeys[childEntry.childIndex].currentContext;
          final childRenderObject = childContext?.findRenderObject();
          if (childRenderObject is! RenderBox || !childRenderObject.hasSize) {
            continue;
          }
          final childRect = childRenderObject.localToGlobal(Offset.zero) &
              childRenderObject.size;
          if (childRect.contains(globalPosition)) {
            childContainsPosition = true;
            break;
          }
        }
        childOffset = resolveIndexedBlockTextOffsetInRoot(
          context,
          rootRenderObject: rootRenderObject,
          entries: childEntries,
          childKeys: childKeys,
          globalPosition: globalPosition,
        );
        if (contentRect.contains(globalPosition)) {
          if (!childContainsPosition) {
            final projectedChildOffset = resolveIndexedBlockTextOffsetInRoot(
              context,
              rootRenderObject: rootRenderObject,
              entries: childEntries,
              childKeys: childKeys,
              globalPosition: Offset(
                contentRect.left + 1,
                globalPosition.dy.clamp(
                  contentRect.top + 0.5,
                  contentRect.bottom - 0.5,
                ),
              ),
            );
            if (projectedChildOffset != null) {
              return _mapListContentOffsetToDisplayedItemOffset(
                entry,
                projectedChildOffset,
              );
            }
          }
          return _mapListContentOffsetToDisplayedItemOffset(
            entry,
            childOffset ?? 0,
          );
        }
      }

      final rowContext = rowKeys[entry.itemIndex].currentContext;
      final rowRenderObject = rowContext?.findRenderObject();
      if (rowRenderObject is RenderBox && rowRenderObject.hasSize) {
        final rect =
            rowRenderObject.localToGlobal(Offset.zero) & rowRenderObject.size;
        final distance = _distanceToRect(globalPosition, rect);
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
              return _mapListContentOffsetToDisplayedItemOffset(
                entry,
                projectedChildOffset,
              );
            }
          }
          if (localRowPosition.dx <= markerExtent) {
            return entry.startOffset;
          }
          return _mapListContentOffsetToDisplayedItemOffset(
            entry,
            childOffset ?? 0,
          );
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

  DocumentRange? _resolveListSelectionUnitRangeInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required ListBlock block,
    required Offset globalPosition,
    required int blockIndex,
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
    final textDirection = Directionality.of(context);

    for (final entry in indexedDescriptors) {
      final itemStart = entry.startOffset;
      final itemEnd = itemStart + entry.descriptor.plainText.length;
      final rowContext = rowKeys[entry.itemIndex].currentContext;
      final rowRenderObject = rowContext?.findRenderObject();
      if (rowRenderObject is RenderBox && rowRenderObject.hasSize) {
        final rowRect =
            rowRenderObject.localToGlobal(Offset.zero) & rowRenderObject.size;
        if (rowRect.contains(globalPosition)) {
          final localRowPosition =
              rowRenderObject.globalToLocal(globalPosition);
          final markerExtent = _resolveListMarkerExtent(
            block: block,
            itemIndex: entry.itemIndex,
            rowRenderObject: rowRenderObject,
            contentRenderObject: null,
          );
          if (localRowPosition.dx <= markerExtent) {
            return DocumentRange(
              start: DocumentPosition(
                blockIndex: blockIndex,
                path: const PathInBlock(<int>[0]),
                textOffset: itemStart,
              ),
              end: DocumentPosition(
                blockIndex: blockIndex,
                path: const PathInBlock(<int>[0]),
                textOffset: itemEnd,
              ),
            );
          }
        }
      }

      final contentContext = contentKeys[entry.itemIndex].currentContext;
      final contentRenderObject = contentContext?.findRenderObject();
      if (contentRenderObject is! RenderBox || !contentRenderObject.hasSize) {
        continue;
      }
      final contentRect = contentRenderObject.localToGlobal(Offset.zero) &
          contentRenderObject.size;
      if (!contentRect.contains(globalPosition)) {
        continue;
      }

      final childEntries = extractor.buildIndexedBlockDescriptors(
        block.items[entry.itemIndex].children,
        indentLevel: entry.contentIndentLevel,
        separator: '\n',
      );
      final childKeys =
          keysRegistry.listItemChildKeysFor(block, entry.itemIndex);
      final childHit = _resolveIndexedBlockHitInRoot(
            context,
            rootRenderObject: rootRenderObject,
            entries: childEntries,
            childKeys: childKeys,
            globalPosition: globalPosition,
          ) ??
          _resolveIndexedBlockHitInRoot(
            context,
            rootRenderObject: rootRenderObject,
            entries: childEntries,
            childKeys: childKeys,
            globalPosition: Offset(
              contentRect.left + 1,
              globalPosition.dy.clamp(
                contentRect.top + 0.5,
                contentRect.bottom - 0.5,
              ),
            ),
          );
      if (childHit == null) {
        continue;
      }

      final childUnit = _resolveNestedBlockSelectionUnitRangeInRoot(
        context,
        rootRenderObject: rootRenderObject,
        hit: childHit,
        globalPosition: globalPosition,
        textDirection: textDirection,
      );
      if (childUnit == null) {
        return null;
      }

      return _mapListChildRangeToItemRange(
        blockIndex: blockIndex,
        itemEntry: entry,
        childEntry: childHit.entry,
        childRange: childUnit,
      );
    }

    return null;
  }

  DocumentRange? _resolveQuoteSelectionUnitRangeInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required QuoteBlock block,
    required Offset globalPosition,
    required int blockIndex,
  }) {
    final entries = extractor.buildIndexedBlockDescriptors(
      block.children,
      separator: '\n\n',
    );
    if (entries.isEmpty) {
      return null;
    }

    final childHit = _resolveIndexedBlockHitInRoot(
      context,
      rootRenderObject: rootRenderObject,
      entries: entries,
      childKeys: keysRegistry.quoteChildKeysFor(block),
      globalPosition: globalPosition,
    );
    if (childHit == null) {
      return null;
    }

    final childUnit = _resolveNestedBlockSelectionUnitRangeInRoot(
      context,
      rootRenderObject: rootRenderObject,
      hit: childHit,
      globalPosition: globalPosition,
      textDirection: Directionality.of(context),
    );
    if (childUnit == null) {
      return null;
    }

    return _mapIndexedChildRangeToParentRange(
      blockIndex: blockIndex,
      childEntry: childHit.entry,
      childRange: childUnit,
    );
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

  DocumentRange? _resolveNestedBlockSelectionUnitRangeInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required _ResolvedIndexedBlockHit hit,
    required Offset globalPosition,
    required TextDirection textDirection,
  }) {
    switch (hit.entry.block.kind) {
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.definitionList:
        return _resolveDescriptorLineRange(
          context,
          descriptor: hit.entry.descriptor,
          renderObject: hit.renderObject,
          globalPosition: globalPosition,
          textDirection: textDirection,
        );
      case MarkdownBlockKind.codeBlock:
        return _resolveCodeBlockLineRange(
          context,
          block: hit.entry.block as CodeBlock,
          descriptor: hit.entry.descriptor,
          renderObject: hit.renderObject,
          globalPosition: globalPosition,
          textDirection: textDirection,
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _resolveListSelectionUnitRangeInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: hit.entry.block as ListBlock,
          globalPosition: globalPosition,
          blockIndex: 0,
          indentLevel: hit.entry.indentLevel,
        );
      case MarkdownBlockKind.footnoteList:
        return _resolveListSelectionUnitRangeInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: MarkdownDescriptorExtractor.footnoteListAsOrderedList(
            hit.entry.block as FootnoteListBlock,
          ),
          globalPosition: globalPosition,
          blockIndex: 0,
          indentLevel: hit.entry.indentLevel,
        );
      case MarkdownBlockKind.quote:
        return _resolveQuoteSelectionUnitRangeInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: hit.entry.block as QuoteBlock,
          globalPosition: globalPosition,
          blockIndex: 0,
        );
      case MarkdownBlockKind.table:
        return _resolveTableSelectionUnitRangeInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: hit.entry.block as TableBlock,
          globalPosition: globalPosition,
          blockIndex: 0,
        );
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        if (hit.entry.descriptor.plainText.isEmpty) {
          return null;
        }
        return DocumentRange(
          start: const DocumentPosition(
            blockIndex: 0,
            path: PathInBlock(<int>[0]),
            textOffset: 0,
          ),
          end: DocumentPosition(
            blockIndex: 0,
            path: const PathInBlock(<int>[0]),
            textOffset: hit.entry.descriptor.plainText.length,
          ),
        );
    }
  }

  DocumentRange? _resolveDescriptorLineRange(
    BuildContext context, {
    required SelectableTextDescriptor descriptor,
    required RenderBox renderObject,
    required Offset globalPosition,
    required TextDirection textDirection,
  }) {
    final localPosition = renderObject.globalToLocal(globalPosition);
    final textOffset = _descriptorUsesDirectRichTextMetrics(descriptor)
        ? _resolveDirectRenderParagraphTextOffset(
              renderObject,
              globalPosition: globalPosition,
              runs: descriptor.pretext!.runs,
            ) ??
            0
        : resolveDescriptorTextOffset(
            context,
            descriptor: descriptor,
            localPosition: localPosition,
            size: renderObject.size,
            textDirection: textDirection,
          );

    final pretext = descriptor.pretext;
    if (pretext != null && _descriptorUsesDirectRichTextMetrics(descriptor)) {
      final directRange = _resolveDirectRenderParagraphLineRange(
        renderObject,
        globalPosition: globalPosition,
        runs: pretext.runs,
      );
      if (directRange != null) {
        return directRange;
      }
    }
    if (pretext != null) {
      final layout = computeDescriptorPretextLayout(
        context,
        descriptor: descriptor,
        maxWidth: renderObject.size.width,
        textDirection: textDirection,
      );
      final lineRange = layout.visualLineRangeForLocalPosition(localPosition) ??
          layout.lineRangeForTextOffset(textOffset);
      if (lineRange == null) {
        return null;
      }
      return DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: lineRange.start,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: lineRange.end,
        ),
      );
    }

    final textPainter = TextPainter(
      text: descriptor.span,
      textDirection: textDirection,
      maxLines: null,
    )..layout(maxWidth: renderObject.size.width);
    final clampedOffset = textOffset.clamp(0, descriptor.plainText.length);
    final boundary = textPainter.getLineBoundary(
      TextPosition(offset: clampedOffset),
    );
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: boundary.start,
      ),
      end: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: boundary.end,
      ),
    );
  }

  DocumentRange? _resolveCodeBlockLineRange(
    BuildContext context, {
    required CodeBlock block,
    required SelectableTextDescriptor descriptor,
    required RenderBox renderObject,
    required Offset globalPosition,
    required TextDirection textDirection,
  }) {
    final localPosition = renderObject.globalToLocal(globalPosition);
    final codeRuns = descriptor.pretext?.runs ??
        codeSyntaxHighlighter.buildPretextRuns(
          source: block.code,
          baseStyle: theme.codeBlockStyle,
          theme: theme,
          language: block.language,
        );
    final measurementPadding =
        theme.codeBlockPadding.resolve(Directionality.of(context)) +
            const EdgeInsets.only(top: 36);
    final textOffset = markdownPretextCanUseDirectRichTextGeometry(codeRuns)
        ? _resolveDirectRenderParagraphTextOffset(
              renderObject,
              globalPosition: globalPosition,
              runs: codeRuns,
            ) ??
            0
        : resolveTextSpanTextOffset(
            codeSyntaxHighlighter.buildTextSpan(
              source: block.code,
              baseStyle: theme.codeBlockStyle,
              theme: theme,
              language: block.language,
            ),
            descriptor.plainText.length,
            localPosition: localPosition,
            size: renderObject.size,
            textDirection: textDirection,
            measurementPadding: measurementPadding,
          );

    final lineRange = markdownPretextCanUseDirectRichTextGeometry(codeRuns)
        ? _resolveDirectRenderParagraphLineRange(
            renderObject,
            globalPosition: globalPosition,
            runs: codeRuns,
          )
        : null;
    if (lineRange != null) {
      return lineRange;
    }

    final logicalLineRange = _resolveLogicalLineRange(
      descriptor.plainText,
      textOffset,
    );
    if (logicalLineRange == null) {
      return null;
    }
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: logicalLineRange.start,
      ),
      end: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: logicalLineRange.end,
      ),
    );
  }

  DocumentRange _mapListChildRangeToItemRange({
    required int blockIndex,
    required IndexedListSelectionDescriptor itemEntry,
    required IndexedBlockDescriptor childEntry,
    required DocumentRange childRange,
  }) {
    final itemStart = itemEntry.startOffset;
    final mappedStart = _mapListContentOffsetToDisplayedItemOffset(
      itemEntry,
      childEntry.startOffset + childRange.start.textOffset,
    );
    final mappedEnd = _mapListContentOffsetToDisplayedItemOffset(
      itemEntry,
      childEntry.startOffset + childRange.end.textOffset,
    );
    final includeMarker = childEntry.childIndex == 0 &&
        _isLeadListTextBlock(childEntry.block) &&
        childRange.start.textOffset == 0;
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: includeMarker ? itemStart : mappedStart,
      ),
      end: DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: mappedEnd,
      ),
    );
  }

  DocumentRange _mapIndexedChildRangeToParentRange({
    required int blockIndex,
    required IndexedBlockDescriptor childEntry,
    required DocumentRange childRange,
  }) {
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: childEntry.startOffset + childRange.start.textOffset,
      ),
      end: DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: childEntry.startOffset + childRange.end.textOffset,
      ),
    );
  }

  DocumentRange? _resolveTableSelectionUnitRangeInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required TableBlock block,
    required Offset globalPosition,
    required int blockIndex,
  }) {
    final textOffset = _resolveTableTextOffsetInRoot(
      context,
      rootRenderObject: rootRenderObject,
      block: block,
      globalPosition: globalPosition,
    );
    if (textOffset == null) {
      return null;
    }

    return extractor.resolveTableCellSelectionRange(
      DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: textOffset,
      ),
      block,
    );
  }

  ({int start, int end})? _resolveLogicalLineRange(
    String plainText,
    int textOffset,
  ) {
    if (plainText.isEmpty) {
      return null;
    }
    var clampedOffset = textOffset.clamp(0, plainText.length).toInt();
    if (clampedOffset == plainText.length && clampedOffset > 0) {
      clampedOffset -= 1;
    }
    if (clampedOffset > 0 &&
        clampedOffset < plainText.length &&
        plainText.codeUnitAt(clampedOffset) == 0x0A) {
      clampedOffset -= 1;
    }

    var start = clampedOffset;
    while (start > 0 && plainText.codeUnitAt(start - 1) != 0x0A) {
      start -= 1;
    }
    var end = clampedOffset;
    while (end < plainText.length && plainText.codeUnitAt(end) != 0x0A) {
      end += 1;
    }
    return (start: start, end: end);
  }

  int _mapDisplayedItemOffsetToContentOffset(
    IndexedListSelectionDescriptor itemEntry,
    int displayedOffset,
  ) {
    final raw =
        displayedOffset - itemEntry.startOffset - itemEntry.prefixLength;
    if (raw <= 0 || itemEntry.prefixLength == 0) {
      return math.max(0, raw);
    }
    final plainText = itemEntry.contentDescriptor.plainText;
    // Walk through content lines, subtracting the continuation prefix
    // for each line boundary crossed.
    var contentOffset = 0;
    var remaining = raw;
    for (var i = 0; i < plainText.length && remaining > 0; i++) {
      if (plainText.codeUnitAt(i) == 0x0A) {
        // Need 1 char for the newline itself plus prefixLength for the
        // continuation prefix that was inserted in the displayed text.
        final needed = 1 + itemEntry.prefixLength;
        if (remaining < needed) {
          contentOffset += remaining;
          remaining = 0;
          break;
        }
        remaining -= needed;
        contentOffset += 1;
      } else {
        remaining -= 1;
        contentOffset += 1;
      }
    }
    contentOffset += remaining;
    return contentOffset.clamp(0, plainText.length).toInt();
  }

  int _mapListContentOffsetToDisplayedItemOffset(
    IndexedListSelectionDescriptor itemEntry,
    int contentOffset,
  ) {
    final plainText = itemEntry.contentDescriptor.plainText;
    final clampedOffset = contentOffset.clamp(0, plainText.length).toInt();
    final lineIndex = _lineIndexForOffset(plainText, clampedOffset);
    return itemEntry.startOffset +
        itemEntry.prefixLength +
        clampedOffset +
        itemEntry.prefixLength * lineIndex;
  }

  int _lineIndexForOffset(String plainText, int offset) {
    var lineIndex = 0;
    for (var index = 0; index < offset; index++) {
      if (plainText.codeUnitAt(index) == 0x0A) {
        lineIndex += 1;
      }
    }
    return lineIndex;
  }

  bool _isLeadListTextBlock(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.heading:
        return true;
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.footnoteList:
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        return false;
    }
  }

  _ResolvedIndexedBlockHit? _resolveIndexedBlockHitInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required List<IndexedBlockDescriptor> entries,
    required List<GlobalKey> childKeys,
    required Offset globalPosition,
  }) {
    final textDirection = Directionality.of(context);
    for (final entry in entries) {
      final childContext = childKeys[entry.childIndex].currentContext;
      final childRenderObject = childContext?.findRenderObject();
      if (childRenderObject is! RenderBox || !childRenderObject.hasSize) {
        continue;
      }
      final rect =
          childRenderObject.localToGlobal(Offset.zero) & childRenderObject.size;
      if (!rect.contains(globalPosition)) {
        continue;
      }
      final childOffset = resolveNestedBlockTextOffset(
        context,
        rootRenderObject: rootRenderObject,
        block: entry.block,
        descriptor: entry.descriptor,
        renderObject: childRenderObject,
        globalPosition: globalPosition,
        textDirection: textDirection,
        indentLevel: entry.indentLevel,
      );
      return _ResolvedIndexedBlockHit(
        entry: entry,
        renderObject: childRenderObject,
        textOffset: childOffset,
      );
    }
    return null;
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

  DocumentRange? _resolveDirectRenderParagraphLineRange(
    RenderObject renderObject, {
    required Offset globalPosition,
    required List<MarkdownPretextInlineRun> runs,
  }) {
    final paragraph = _findDirectRenderParagraphForRuns(renderObject, runs);
    if (paragraph == null || !paragraph.hasSize) {
      return null;
    }

    final textPosition = paragraph.getPositionForOffset(
      paragraph.globalToLocal(globalPosition),
    );
    final lineBoundary = _resolveDirectParagraphRenderLineBoundary(
        paragraph, textPosition.offset);
    if (lineBoundary == null) {
      return null;
    }

    final plainText = runs.map((run) => run.text).join();
    var plainStart = markdownPretextPlainOffsetForRenderOffset(
      runs,
      lineBoundary.start,
    );
    var plainEnd = markdownPretextPlainOffsetForRenderOffset(
      runs,
      lineBoundary.end,
    );
    if (plainStart < plainText.length &&
        plainText.codeUnitAt(plainStart) == 0x0A) {
      plainStart += 1;
    }
    if (plainEnd > plainStart &&
        plainEnd <= plainText.length &&
        plainText.codeUnitAt(plainEnd - 1) == 0x0A) {
      plainEnd -= 1;
    }
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: plainStart,
      ),
      end: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: plainEnd,
      ),
    );
  }

  ({int start, int end})? _resolveDirectParagraphRenderLineBoundary(
    RenderParagraph paragraph,
    int renderOffset,
  ) {
    final fullText = paragraph.text.toPlainText(includePlaceholders: true);
    if (fullText.isEmpty) {
      return const (start: 0, end: 0);
    }
    final lineExtents = _computeParagraphLineExtents(paragraph);
    if (lineExtents.isEmpty) {
      return null;
    }

    var probe = renderOffset.clamp(0, fullText.length).toInt();
    if (probe == fullText.length && probe > 0) {
      probe -= 1;
    }

    List<TextBox> probeBoxes =
        _boxesForDirectParagraphOffset(paragraph, fullText, probe);
    while (probeBoxes.isEmpty && probe > 0) {
      probe -= 1;
      probeBoxes = _boxesForDirectParagraphOffset(paragraph, fullText, probe);
    }
    while (probeBoxes.isEmpty && probe < fullText.length - 1) {
      probe += 1;
      probeBoxes = _boxesForDirectParagraphOffset(paragraph, fullText, probe);
    }
    if (probeBoxes.isEmpty) {
      return null;
    }

    final lineExtent = lineExtents.firstWhere(
      (extent) => _boxesOverlapParagraphLineExtent(probeBoxes, extent),
      orElse: () => lineExtents.last,
    );

    var start = probe;
    while (start > 0) {
      final previousBoxes =
          _boxesForDirectParagraphOffset(paragraph, fullText, start - 1);
      if (previousBoxes.isEmpty ||
          !_boxesOverlapParagraphLineExtent(previousBoxes, lineExtent)) {
        break;
      }
      start -= 1;
    }

    var end = probe + 1;
    while (end < fullText.length) {
      final nextBoxes =
          _boxesForDirectParagraphOffset(paragraph, fullText, end);
      if (nextBoxes.isEmpty ||
          !_boxesOverlapParagraphLineExtent(nextBoxes, lineExtent)) {
        break;
      }
      end += 1;
    }
    return (start: start, end: end);
  }

  List<TextBox> _boxesForDirectParagraphOffset(
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

  bool _boxesOverlapParagraphLineExtent(
    List<TextBox> boxes,
    ({double top, double bottom}) lineExtent,
  ) {
    for (final box in boxes) {
      final overlapTop = math.max(box.top, lineExtent.top);
      final overlapBottom = math.min(box.bottom, lineExtent.bottom);
      if (overlapBottom - overlapTop > 0.5) {
        return true;
      }
    }
    return false;
  }

  List<Rect> _resolveTableSelectionRectsInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required TableBlock block,
    required DocumentRange range,
  }) {
    final cellKeys = keysRegistry.tableCellKeysFor(block);
    final cellTextKeys = keysRegistry.tableCellTextKeysFor(block);
    final rects = <Rect>[];
    var currentOffset = 0;
    final textDirection = Directionality.of(context);
    final padding = theme.tableCellPadding.resolve(textDirection);

    for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++) {
      final row = block.rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.cells.length; columnIndex++) {
        final cell = row.cells[columnIndex];
        final cellText = MarkdownInlineBuilder.flattenInlineText(cell.inlines);
        final cellLength = cellText.length;
        final cellStart = currentOffset;
        final cellEnd = cellStart + cellLength;

        if (range.start.textOffset <= cellEnd &&
            range.end.textOffset >= cellStart) {
          final textKey = cellTextKeys[rowIndex][columnIndex];
          final paragraph =
              _findDirectRenderParagraphForKey(rootRenderObject, textKey);

          if (paragraph != null && paragraph.hasSize) {
            final localStart = math.max(0, range.start.textOffset - cellStart);
            final localEnd =
                math.min(cellLength, range.end.textOffset - cellStart);

            final alignment = columnIndex < block.alignments.length
                ? block.alignments[columnIndex]
                : MarkdownTableColumnAlignment.none;
            final cellDescriptor = extractor.descriptorFromInlines(
              theme.bodyStyle,
              cell.inlines,
              textAlign: _textAlignForTableColumn(alignment),
            );

            final pretext = cellDescriptor.pretext;
            if (pretext != null) {
              final renderSelection = TextSelection(
                baseOffset: markdownPretextRenderOffsetForPlainOffset(
                  pretext.runs,
                  localStart,
                  preferEnd: false,
                ),
                extentOffset: markdownPretextRenderOffsetForPlainOffset(
                  pretext.runs,
                  localEnd,
                  preferEnd: true,
                ),
              );
              final lineExtents = _computeParagraphLineExtents(paragraph);
              final boxes = _mergeAdjacentTextSelectionBoxes(
                _normalizeBoxesToLineExtents(
                  paragraph.getBoxesForSelection(renderSelection),
                  lineExtents,
                ),
              );
              rects.addAll(boxes.map((box) => Rect.fromLTRB(
                    box.left +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dx -
                        1.5,
                    box.top +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dy,
                    box.right +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dx +
                        1.5,
                    box.bottom +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dy,
                  )));
            } else {
              final boxes = paragraph.getBoxesForSelection(TextSelection(
                baseOffset: localStart,
                extentOffset: localEnd,
              ));
              rects.addAll(boxes.map((box) => Rect.fromLTRB(
                    box.left +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dx -
                        1.5,
                    box.top +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dy,
                    box.right +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dx +
                        1.5,
                    box.bottom +
                        paragraph
                            .localToGlobal(Offset.zero,
                                ancestor: rootRenderObject)
                            .dy,
                  )));
            }
          } else {
            // Fallback
            final cellContext = cellKeys[rowIndex][columnIndex].currentContext;
            final cellRenderObject = cellContext?.findRenderObject();
            if (cellRenderObject is RenderBox && cellRenderObject.hasSize) {
              final cellOrigin = cellRenderObject.localToGlobal(Offset.zero,
                  ancestor: rootRenderObject);
              final localStart =
                  math.max(0, range.start.textOffset - cellStart);
              final localEnd =
                  math.min(cellLength, range.end.textOffset - cellStart);

              final alignment = columnIndex < block.alignments.length
                  ? block.alignments[columnIndex]
                  : MarkdownTableColumnAlignment.none;
              final textAlign = _textAlignForTableColumn(alignment);

              final cellDescriptor = extractor.descriptorFromInlines(
                theme.bodyStyle,
                cell.inlines,
                textAlign: textAlign,
              );

              final cellRects = resolveDescriptorSelectionRects(
                context,
                descriptor: cellDescriptor,
                range: DocumentRange(
                  start: DocumentPosition(
                      blockIndex: 0,
                      path: const PathInBlock(<int>[0]),
                      textOffset: localStart),
                  end: DocumentPosition(
                      blockIndex: 0,
                      path: const PathInBlock(<int>[0]),
                      textOffset: localEnd),
                ),
                size: Size(
                  math.max(0, cellRenderObject.size.width - padding.horizontal),
                  math.max(0, cellRenderObject.size.height - padding.vertical),
                ),
                textDirection: textDirection,
                origin: cellOrigin + padding.topLeft,
              );
              rects.addAll(cellRects);
            }
          }
        }
        currentOffset = cellEnd + 1;
      }
    }
    return rects;
  }

  int? _resolveTableTextOffsetInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required TableBlock block,
    required Offset globalPosition,
  }) {
    final cellKeys = keysRegistry.tableCellKeysFor(block);
    final cellTextKeys = keysRegistry.tableCellTextKeysFor(block);
    var currentOffset = 0;
    final textDirection = Directionality.of(context);
    final padding = theme.tableCellPadding.resolve(textDirection);

    int? bestOffset;
    double bestDistance = double.infinity;

    for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++) {
      final row = block.rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.cells.length; columnIndex++) {
        final cell = row.cells[columnIndex];
        final cellText = MarkdownInlineBuilder.flattenInlineText(cell.inlines);
        final cellLength = cellText.length;

        final textKey = cellTextKeys[rowIndex][columnIndex];
        final paragraph =
            _findDirectRenderParagraphForKey(rootRenderObject, textKey);

        if (paragraph != null && paragraph.hasSize) {
          final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
          final distance = _distanceToRect(globalPosition, rect);

          if (distance < bestDistance) {
            bestDistance = distance;
            final localPos = paragraph.globalToLocal(globalPosition);
            final textPosition = paragraph.getPositionForOffset(localPos);

            final alignment = columnIndex < block.alignments.length
                ? block.alignments[columnIndex]
                : MarkdownTableColumnAlignment.none;
            final cellDescriptor = extractor.descriptorFromInlines(
              theme.bodyStyle,
              cell.inlines,
              textAlign: _textAlignForTableColumn(alignment),
            );

            final pretext = cellDescriptor.pretext;
            if (pretext != null) {
              bestOffset = currentOffset +
                  markdownPretextPlainOffsetForRenderOffset(
                      pretext.runs, textPosition.offset);
            } else {
              bestOffset = currentOffset + textPosition.offset;
            }
          }
        } else {
          final cellContext = cellKeys[rowIndex][columnIndex].currentContext;
          final cellRenderObject = cellContext?.findRenderObject();
          if (cellRenderObject is RenderBox && cellRenderObject.hasSize) {
            final bounds = cellRenderObject.localToGlobal(Offset.zero) &
                cellRenderObject.size;
            final distance = _distanceToRect(globalPosition, bounds);

            if (distance < bestDistance) {
              bestDistance = distance;
              final localPosition =
                  cellRenderObject.globalToLocal(globalPosition);

              final alignment = columnIndex < block.alignments.length
                  ? block.alignments[columnIndex]
                  : MarkdownTableColumnAlignment.none;
              final textAlign = _textAlignForTableColumn(alignment);

              final cellDescriptor = extractor.descriptorFromInlines(
                theme.bodyStyle,
                cell.inlines,
                textAlign: textAlign,
              );
              final offsetInCell = resolveDescriptorTextOffset(
                context,
                descriptor: cellDescriptor,
                localPosition: localPosition - padding.topLeft,
                size: Size(
                  math.max(0, cellRenderObject.size.width - padding.horizontal),
                  math.max(0, cellRenderObject.size.height - padding.vertical),
                ),
                textDirection: textDirection,
              );
              bestOffset = currentOffset + offsetInCell;
            }
          }
        }
        currentOffset += cellLength + 1;
      }
    }
    return bestOffset;
  }

  double _distanceToRect(Offset p, Rect rect) {
    final dx = p.dx < rect.left
        ? rect.left - p.dx
        : p.dx > rect.right
            ? p.dx - rect.right
            : 0.0;
    final dy = p.dy < rect.top
        ? rect.top - p.dy
        : p.dy > rect.bottom
            ? p.dy - rect.bottom
            : 0.0;
    return dx * dx + dy * dy;
  }

  RenderParagraph? _findDirectRenderParagraphForKey(
      RenderObject root, GlobalKey key) {
    final context = key.currentContext;
    if (context == null) {
      return null;
    }
    final ro = context.findRenderObject();
    if (ro is RenderParagraph) {
      return ro;
    }

    RenderParagraph? result;
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        result = node;
        return;
      }
      if (result != null) {
        return;
      }
      node.visitChildren(visit);
    }

    if (ro != null) {
      visit(ro);
    }
    return result;
  }

  TextAlign _textAlignForTableColumn(MarkdownTableColumnAlignment alignment) {
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
            textOffset: _mapDisplayedItemOffsetToContentOffset(
              entry,
              contentSelectionStart,
            ),
          ),
          end: DocumentPosition(
            blockIndex: 0,
            path: const PathInBlock(<int>[0]),
            textOffset: _mapDisplayedItemOffsetToContentOffset(
              entry,
              contentSelectionEnd,
            ),
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
      final distance = _distanceToRect(globalPosition, rect);
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
      case MarkdownBlockKind.table:
        return _resolveTableSelectionRectsInRoot(
          context,
          rootRenderObject: rootRenderObject,
          block: block as TableBlock,
          range: range,
        );
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
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        final rect = origin & renderObject.size;
        return <Rect>[
          Rect.fromLTRB(
              rect.left - 1.5, rect.top, rect.right + 1.5, rect.bottom),
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
      case MarkdownBlockKind.table:
        return _resolveTableTextOffsetInRoot(
              context,
              rootRenderObject: rootRenderObject,
              block: block as TableBlock,
              globalPosition: globalPosition,
            ) ??
            0;
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
    final fullText =
        textPainter.text?.toPlainText(includePlaceholders: true) ?? '';
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
      final resolvedBottom =
          next != null ? (current.bottom + next.top) / 2.0 : current.bottom;

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

class ResolvedIndexedBlockEntry {
  const ResolvedIndexedBlockEntry({
    required this.entry,
    required this.renderObject,
    required this.rect,
  });

  final IndexedBlockDescriptor entry;
  final RenderBox renderObject;
  final Rect rect;
}

class _ResolvedIndexedBlockHit {
  const _ResolvedIndexedBlockHit({
    required this.entry,
    required this.renderObject,
    required this.textOffset,
  });

  final IndexedBlockDescriptor entry;
  final RenderBox renderObject;
  final int textOffset;
}
