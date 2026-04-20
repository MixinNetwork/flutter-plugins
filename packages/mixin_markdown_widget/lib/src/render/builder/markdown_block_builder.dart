import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'dart:math' as math;

import '../../clipboard/plain_text_serializer.dart';
import '../../core/document.dart';
import '../../selection/selection_controller.dart';
import '../../selection/structured_block_selection.dart';
import '../../widgets/markdown_theme.dart';
import '../../widgets/markdown_types.dart';
import '../code_syntax_highlighter.dart';
import '../markdown_block_widgets.dart';
import '../pretext_text_block.dart';
import '../selectable_block.dart';
import 'markdown_inline_builder.dart';
import '../selection/markdown_descriptor_extractor.dart';
import '../selection/markdown_selection_resolver.dart';
import '../local_image_provider_stub.dart'
    if (dart.library.io) '../local_image_provider_io.dart';

class MarkdownBlockBuilder {
  MarkdownBlockBuilder({
    required this.theme,
    required this.selectionController,
    required this.document,
    required this.isSelectable,
    required this.keysRegistry,
    required this.descriptorExtractor,
    required this.selectionResolver,
    required this.inlineBuilder,
    required this.codeSyntaxHighlighter,
    required this.plainTextSerializer,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.bulletBuilder,
    this.onTapLink,
    required this.onRequestContextMenu,
    required Map<String, CachedBlockRow> cachedBlockRows,
  }) : _cachedBlockRows = cachedBlockRows;

  final MarkdownThemeData theme;
  final MarkdownSelectionController? selectionController;
  final MarkdownDocument document;
  final bool isSelectable;
  final MarkdownBlockKeysRegistry keysRegistry;
  final MarkdownDescriptorExtractor descriptorExtractor;
  final MarkdownSelectionResolver selectionResolver;
  final MarkdownInlineBuilder inlineBuilder;
  final MarkdownCodeSyntaxHighlighter codeSyntaxHighlighter;
  final MarkdownPlainTextSerializer plainTextSerializer;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownCodeBlockBuilder? codeBlockBuilder;
  final MarkdownBulletBuilder? bulletBuilder;
  final MarkdownTapLinkCallback? onTapLink;
  final void Function(Offset) onRequestContextMenu;

  final Map<String, CachedBlockRow> _cachedBlockRows;

  Widget buildBlockListItem(
    BuildContext context, {
    required BlockNode block,
    required int blockIndex,
    required DocumentRange? selectionRange,
  }) {
    final cacheable = _canCacheBlockRow(block);
    final selectionSignature = _selectionSignatureForBlock(
      block: block,
      blockIndex: blockIndex,
      selectionRange: selectionRange,
    );

    if (cacheable) {
      final cached = _cachedBlockRows[block.id];
      if (cached != null &&
          identical(cached.block, block) &&
          cached.blockIndex == blockIndex &&
          cached.selectionSignature == selectionSignature) {
        return cached.widget;
      }
    }

    final widget = Padding(
      padding: EdgeInsets.only(
        bottom:
            blockIndex == document.blocks.length - 1 ? 0 : theme.blockSpacing,
      ),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: theme.maxContentWidth),
          child: _buildBlockView(
            context,
            block: block,
            blockIndex: blockIndex,
            selectionRange: selectionRange,
          ),
        ),
      ),
    );

    if (!cacheable) {
      _cachedBlockRows.remove(block.id);
      return widget;
    }

    _cachedBlockRows[block.id] = CachedBlockRow(
      block: block,
      blockIndex: blockIndex,
      selectionSignature: selectionSignature,
      widget: widget,
    );
    return widget;
  }

  Widget _buildBlockView(
    BuildContext context, {
    required BlockNode block,
    required int blockIndex,
    required DocumentRange? selectionRange,
  }) {
    if (selectionController != null &&
        imageBuilder == null &&
        block is ImageBlock) {
      final captionText = MarkdownDescriptorExtractor.imageCaptionText(block);
      if (captionText.isNotEmpty) {
        final key = keysRegistry.blockKeys.putIfAbsent(
          block.id,
          () => GlobalKey<SelectableMarkdownBlockState>(debugLabel: block.id),
        );
        final captionDescriptor =
            descriptorExtractor.buildImageCaptionDescriptor(block);
        final imageState = _buildImageVisual(context, block, hasCaption: true);
        return MarkdownImageBlockView(
          theme: theme,
          image: imageState.image,
          hasErrorNotifier: imageState.hasErrorNotifier,
          hasKnownSize: imageState.hasKnownSize,
          caption: SelectableMarkdownBlock(
            key: key,
            blockIndex: blockIndex,
            spec: _buildSelectableDescriptorTextSpec(
              descriptor: captionDescriptor,
            ),
            selectionColor: theme.selectionColor,
            selectionRange: selectionRange,
          ),
        );
      }
    }

    if (selectionController != null &&
        imageBuilder != null &&
        block is ImageBlock) {
      final key = keysRegistry.blockKeys.putIfAbsent(
        block.id,
        () => GlobalKey<SelectableMarkdownBlockState>(debugLabel: block.id),
      );
      return SelectableMarkdownBlock(
        key: key,
        blockIndex: blockIndex,
        spec: _buildCustomImageBuilderSpec(context, block),
        selectionColor: theme.selectionColor,
        selectionRange: selectionRange,
      );
    }

    final key = keysRegistry.blockKeys.putIfAbsent(
      block.id,
      () => GlobalKey<SelectableMarkdownBlockState>(debugLabel: block.id),
    );
    return SelectableMarkdownBlock(
      key: key,
      blockIndex: blockIndex,
      spec: _buildBlockSpec(context, block),
      selectionColor: theme.selectionColor,
      selectionRange: selectionRange,
    );
  }

  SelectableBlockSpec _buildBlockSpec(BuildContext context, BlockNode block) {
    if (!isSelectable || selectionController == null) {
      return SelectableBlockSpec(
        child: _buildNestedBlockContent(context, block),
        plainText: plainTextSerializer.serializeBlockText(block),
        hitTestBehavior: SelectableBlockHitTestBehavior.block,
      );
    }

    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        final style = theme.headingStyleForLevel(heading.level);
        final plainText =
            MarkdownInlineBuilder.flattenInlineText(heading.inlines);
        final runs = inlineBuilder.buildPretextRuns(style, heading.inlines);
        final directTextKey = _createDirectTextKeyIfNeeded(runs);
        return _buildPretextTextSpec(
          child: _wrapHeadingBlock(
            level: heading.level,
            child: MarkdownPretextTextBlock.rich(
              runs: runs,
              fallbackStyle: style,
              directTextKey: directTextKey,
              preferDirectRichText: directTextKey != null,
              textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(
                heading.inlines,
              ),
            ),
          ),
          plainText: plainText,
          runs: runs,
          fallbackStyle: style,
          directTextKey: directTextKey,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(heading.inlines),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        final plainText =
            MarkdownInlineBuilder.flattenInlineText(paragraph.inlines);
        final runs = inlineBuilder.buildPretextRuns(
          theme.bodyStyle,
          paragraph.inlines,
        );
        final directTextKey = _createDirectTextKeyIfNeeded(runs);
        return _buildPretextTextSpec(
          plainText: plainText,
          runs: runs,
          fallbackStyle: theme.bodyStyle,
          directTextKey: directTextKey,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(paragraph.inlines),
        );
      case MarkdownBlockKind.quote:
        final quoteBlock = block as QuoteBlock;
        final descriptor =
            descriptorExtractor.buildQuoteSelectableDescriptor(quoteBlock);
        return SelectableBlockSpec(
          child: MarkdownQuoteBlockView(
            theme: theme,
            child: _buildQuoteContent(
              context,
              quoteBlock,
              childKeys: keysRegistry.quoteChildKeysFor(quoteBlock),
            ),
          ),
          plainText: descriptor.plainText,
          selectionStructure: _matchingSelectionStructure(
            quoteBlock,
            descriptor.plainText,
          ),
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: descriptor.span,
          highlightBorderRadius: BorderRadius.circular(16),
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
          selectionColor: _quoteSelectionColor,
          selectionRectResolver: (context, _, range) =>
              selectionResolver.resolveQuoteSelectionRects(
            context,
            quoteBlock,
            range,
          ),
          textOffsetResolver: (context, _, localPosition) =>
              selectionResolver.resolveQuoteTextOffset(
            context,
            quoteBlock,
            localPosition,
          ),
          selectionUnitRangeResolver: (context, _, localPosition, position) =>
              localPosition == null
                  ? descriptorExtractor.resolveSelectionUnitRange(
                      position,
                      quoteBlock,
                    )
                  : selectionResolver.resolveQuoteSelectionUnitRange(
                        context,
                        quoteBlock,
                        localPosition,
                        position,
                      ) ??
                      descriptorExtractor.resolveSelectionUnitRange(
                        position,
                        quoteBlock,
                      ),
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        final listBlock = block as ListBlock;
        final descriptor =
            descriptorExtractor.buildListSelectableDescriptor(listBlock);
        final itemRowKeys = keysRegistry.listItemKeysFor(listBlock);
        final itemContentKeys = keysRegistry.listItemContentKeysFor(listBlock);
        return SelectableBlockSpec(
          child: MarkdownListBlockView(
            theme: theme,
            block: listBlock,
            itemBuilder: (index, item) =>
                _buildListItemContent(context, listBlock, index, item),
            itemRowKeyBuilder: (index) => itemRowKeys[index],
            itemContentKeyBuilder: (index) => itemContentKeys[index],
            bulletBuilder: bulletBuilder,
          ),
          plainText: descriptor.plainText,
          selectionStructure: _matchingSelectionStructure(
            listBlock,
            descriptor.plainText,
          ),
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: descriptor.span,
          selectionRectResolver: (context, _, range) =>
              selectionResolver.resolveListSelectionRects(
            context,
            listBlock,
            range,
          ),
          textOffsetResolver: (context, _, localPosition) =>
              selectionResolver.resolveListTextOffset(
            context,
            listBlock,
            localPosition,
          ),
          selectionUnitRangeResolver: (context, _, localPosition, position) =>
              localPosition == null
                  ? descriptorExtractor.resolveSelectionUnitRange(
                      position,
                      listBlock,
                    )
                  : selectionResolver.resolveListSelectionUnitRange(
                        context,
                        listBlock,
                        localPosition,
                        position,
                      ) ??
                      descriptorExtractor.resolveSelectionUnitRange(
                        position,
                        listBlock,
                      ),
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
        );
      case MarkdownBlockKind.definitionList:
        final definitionList = block as DefinitionListBlock;
        final definitionDescriptor = descriptorExtractor
            .buildDefinitionListSelectableDescriptor(definitionList);
        return _buildSelectableDescriptorTextSpec(
          descriptor: definitionDescriptor,
          selectionStructure: _matchingSelectionStructure(
            definitionList,
            definitionDescriptor.plainText,
          ),
        );
      case MarkdownBlockKind.footnoteList:
        final footnoteList = block as FootnoteListBlock;
        final orderedFootnotes =
            MarkdownDescriptorExtractor.footnoteListAsOrderedList(footnoteList);
        final footnoteDescriptor = descriptorExtractor
            .buildFootnoteListSelectableDescriptor(footnoteList);
        final itemRowKeys = keysRegistry.listItemKeysFor(orderedFootnotes);
        final itemContentKeys =
            keysRegistry.listItemContentKeysFor(orderedFootnotes);
        return SelectableBlockSpec(
          child: _buildFootnoteListContainer(
            child: MarkdownListBlockView(
              theme: theme,
              block: orderedFootnotes,
              itemBuilder: (index, item) =>
                  _buildListItemContent(context, orderedFootnotes, index, item),
              itemRowKeyBuilder: (index) => itemRowKeys[index],
              itemContentKeyBuilder: (index) => itemContentKeys[index],
              bulletBuilder: bulletBuilder,
            ),
          ),
          plainText: footnoteDescriptor.plainText,
          selectionStructure: _matchingSelectionStructure(
            orderedFootnotes,
            footnoteDescriptor.plainText,
          ),
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: footnoteDescriptor.span,
          selectionRectResolver: (context, _, range) =>
              selectionResolver.resolveListSelectionRects(
            context,
            orderedFootnotes,
            range,
          ),
          textOffsetResolver: (context, _, localPosition) =>
              selectionResolver.resolveListTextOffset(
            context,
            orderedFootnotes,
            localPosition,
          ),
          selectionUnitRangeResolver: (context, _, localPosition, position) =>
              localPosition == null
                  ? descriptorExtractor.resolveSelectionUnitRange(
                      position,
                      orderedFootnotes,
                    )
                  : selectionResolver.resolveListSelectionUnitRange(
                        context,
                        orderedFootnotes,
                        localPosition,
                        position,
                      ) ??
                      descriptorExtractor.resolveSelectionUnitRange(
                        position,
                        orderedFootnotes,
                      ),
          highlightBorderRadius: BorderRadius.circular(8),
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        final codeRuns = codeSyntaxHighlighter.buildPretextRuns(
          source: codeBlock.code,
          baseStyle: theme.codeBlockStyle,
          theme: theme,
          language: codeBlock.language,
        );
        final codeSpan = _buildCodeTextSpan(codeBlock);
        final directTextKey = _createDirectTextKeyIfNeeded(codeRuns);
        final scrollController = keysRegistry.codeBlockScrollControllers
            .putIfAbsent(codeBlock.id, ScrollController.new);
        return _buildPretextTextSpec(
          child: _buildDecoratedCodeBlock(
            codeBlock,
            codeSpan: codeSpan,
            directTextKey: directTextKey,
            scrollController: scrollController,
          ),
          plainText: codeBlock.code,
          runs: codeRuns,
          fallbackStyle: theme.codeBlockStyle,
          directTextKey: directTextKey,
          measurementPadding: EdgeInsets.fromLTRB(
            theme.codeBlockPadding.resolve(Directionality.of(context)).left,
            math.max(
              0,
              theme.codeBlockPadding.resolve(Directionality.of(context)).top,
            ),
            theme.codeBlockPadding.resolve(Directionality.of(context)).right +
                32,
            math.max(
              0,
              theme.codeBlockPadding.resolve(Directionality.of(context)).top,
            ),
          ),
          selectionClipPadding: EdgeInsets.fromLTRB(
            theme.codeBlockPadding.resolve(Directionality.of(context)).left,
            math.max(
              0,
              theme.codeBlockPadding.resolve(Directionality.of(context)).top,
            ),
            theme.codeBlockPadding.resolve(Directionality.of(context)).right +
                32,
            math.max(
              0,
              theme.codeBlockPadding.resolve(Directionality.of(context)).top,
            ),
          ),
          highlightBorderRadius: theme.codeBlockBorderRadius,
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
          repaintListenable: scrollController,
        );
      case MarkdownBlockKind.table:
        final tableBlock = block as TableBlock;
        final cellKeys = keysRegistry.tableCellKeysFor(tableBlock);
        final cellTextKeys = keysRegistry.tableCellTextKeysFor(tableBlock);
        final descriptor =
            descriptorExtractor.buildSelectableDescriptorForBlock(tableBlock);
        final scrollController = keysRegistry.tableScrollControllers
            .putIfAbsent(tableBlock.id, ScrollController.new);
        return SelectableBlockSpec(
          child: _buildTable(
            context,
            tableBlock,
            cellKeyBuilder: (rowIndex, columnIndex) =>
                cellKeys[rowIndex][columnIndex],
            cellTextKeyBuilder: (rowIndex, columnIndex) =>
                cellTextKeys[rowIndex][columnIndex],
            scrollController: scrollController,
          ),
          plainText: descriptor.plainText,
          selectionStructure: _matchingSelectionStructure(
            tableBlock,
            descriptor.plainText,
          ),
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: descriptor.span,
          highlightBorderRadius: theme.tableBorderRadius,
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
          repaintListenable: scrollController,
          selectionColor: theme.selectionColor,
          selectionRectResolver: (context, _, range) =>
              selectionResolver.resolveNestedBlockSelectionRects(
            context,
            rootRenderObject: context.findRenderObject() as RenderBox,
            block: tableBlock,
            descriptor: descriptor,
            range: range,
            renderObject: context.findRenderObject() as RenderBox, // Ignored
            origin: Offset.zero, // Ignored
            textDirection: Directionality.of(context),
          ),
          textOffsetResolver: (context, _, localPosition) =>
              selectionResolver.resolveNestedBlockTextOffset(
            context,
            rootRenderObject: context.findRenderObject() as RenderBox,
            block: tableBlock,
            descriptor: descriptor,
            renderObject: context.findRenderObject() as RenderBox, // Ignored
            globalPosition: (context.findRenderObject() as RenderBox)
                .localToGlobal(localPosition), // Ignored
            textDirection: Directionality.of(context),
          ),
          selectionUnitRangeResolver: (_, __, ___, position) =>
              descriptorExtractor.resolveSelectionUnitRange(
            position,
            tableBlock,
          ),
        );
      case MarkdownBlockKind.image:
        return SelectableBlockSpec(
          child: _buildImage(context, block as ImageBlock),
          plainText: plainTextSerializer.serializeBlockText(block),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
          highlightBorderRadius: theme.imageBorderRadius,
        );
      case MarkdownBlockKind.thematicBreak:
        return SelectableBlockSpec(
          child: Divider(
            color: theme.dividerColor,
            height: 1,
            thickness: 1,
          ),
          plainText: plainTextSerializer.serializeBlockText(block),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
        );
    }
  }

  SelectableBlockSpec _buildPretextTextSpec({
    Widget? child,
    required String plainText,
    required List<MarkdownPretextInlineRun> runs,
    required TextStyle fallbackStyle,
    TextAlign textAlign = TextAlign.start,
    GlobalKey? directTextKey,
    EdgeInsets measurementPadding = EdgeInsets.zero,
    BorderRadius? highlightBorderRadius,
    SelectableBlockSelectionPaintOrder? selectionPaintOrder,
    Listenable? repaintListenable,
    EdgeInsets? selectionClipPadding,
    StructuredBlockSelection? selectionStructure,
  }) {
    final hasInlineSurface = runs.any(
      (run) => run.decoration != null || run.renderSpan != null,
    );
    return SelectableBlockSpec(
      child: child ??
          MarkdownPretextTextBlock.rich(
            runs: runs,
            fallbackStyle: fallbackStyle,
            directTextKey: directTextKey,
            preferDirectRichText: directTextKey != null,
            textAlign: textAlign,
          ),
      plainText: plainText,
      hitTestBehavior: SelectableBlockHitTestBehavior.text,
      selectionStructure: selectionStructure,
      measurementPadding: measurementPadding,
      highlightBorderRadius: highlightBorderRadius,
      selectionPaintOrder: selectionPaintOrder ??
          (hasInlineSurface
              ? SelectableBlockSelectionPaintOrder.aboveChild
              : SelectableBlockSelectionPaintOrder.behindChild),
      repaintListenable: repaintListenable,
      selectionClipPadding: selectionClipPadding,
      selectionRectResolver: (context, constraints, range) {
        if (directTextKey != null) {
          final directRects = _resolveDirectRichTextSelectionRects(
            context,
            directTextKey,
            range,
            runs,
          );
          if (directRects != null) {
            return directRects;
          }
        }
        final textScaler =
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
        final layout = computeMarkdownPretextLayoutFromRuns(
          runs: runs,
          fallbackStyle: fallbackStyle,
          maxWidth: constraints.width,
          textScaleFactor: textScaler.scale(1.0),
          textAlign: textAlign,
          textDirection: Directionality.of(context),
        );
        return layout.selectionRectsForRange(
          range,
          textDirection: Directionality.of(context),
        );
      },
      textOffsetResolver: (context, size, localPosition) {
        if (directTextKey != null) {
          final directOffset = _resolveDirectRichTextTextOffset(
            context,
            directTextKey,
            localPosition,
            runs,
          );
          if (directOffset != null) {
            return directOffset;
          }
        }
        final textScaler =
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
        final layout = computeMarkdownPretextLayoutFromRuns(
          runs: runs,
          fallbackStyle: fallbackStyle,
          maxWidth: size.width,
          textScaleFactor: textScaler.scale(1.0),
          textAlign: textAlign,
          textDirection: Directionality.of(context),
        );
        return layout.textOffsetAt(
          localPosition,
          textDirection: Directionality.of(context),
        );
      },
      selectionUnitRangeResolver: (context, size, localPosition, position) {
        if (directTextKey != null) {
          final directRange = _resolveDirectRichTextLineRange(
            context,
            directTextKey,
            position,
            localPosition,
            runs,
          );
          if (directRange != null) {
            return directRange;
          }
        }
        final textScaler =
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
        final layout = computeMarkdownPretextLayoutFromRuns(
          runs: runs,
          fallbackStyle: fallbackStyle,
          maxWidth: size.width,
          textScaleFactor: textScaler.scale(1.0),
          textAlign: textAlign,
          textDirection: Directionality.of(context),
        );
        final lineRange = localPosition == null
            ? layout.lineRangeForTextOffset(position.textOffset)
            : layout.visualLineRangeForLocalPosition(localPosition) ??
                layout.lineRangeForTextOffset(position.textOffset);
        if (lineRange == null) {
          return null;
        }
        return DocumentRange(
          start: DocumentPosition(
            blockIndex: position.blockIndex,
            path: const PathInBlock(<int>[0]),
            textOffset: lineRange.start,
          ),
          end: DocumentPosition(
            blockIndex: position.blockIndex,
            path: const PathInBlock(<int>[0]),
            textOffset: lineRange.end,
          ),
        );
      },
    );
  }

  DocumentRange? _resolveDirectRichTextLineRange(
    BuildContext context,
    GlobalKey directTextKey,
    DocumentPosition position,
    Offset? localPosition,
    List<MarkdownPretextInlineRun> runs,
  ) {
    final blockRenderObject = context.findRenderObject();
    final renderParagraph = _resolveDirectRenderParagraph(
      directTextKey,
      runs: runs,
      fallbackRoot: blockRenderObject,
    );
    if (renderParagraph == null ||
        blockRenderObject is! RenderBox ||
        !blockRenderObject.hasSize) {
      return null;
    }

    final textPosition = localPosition == null
        ? TextPosition(
            offset: markdownPretextRenderOffsetForPlainOffset(
              runs,
              position.textOffset,
              preferEnd: false,
            ),
          )
        : renderParagraph.getPositionForOffset(
            renderParagraph.globalToLocal(
              blockRenderObject.localToGlobal(localPosition),
            ),
          );
    final lineBoundary = _resolveDirectRenderParagraphLineBoundary(
      renderParagraph,
      textPosition.offset,
    );
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
        blockIndex: position.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: plainStart,
      ),
      end: DocumentPosition(
        blockIndex: position.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: plainEnd,
      ),
    );
  }

  ({int start, int end})? _resolveDirectRenderParagraphLineBoundary(
    RenderParagraph renderParagraph,
    int renderOffset,
  ) {
    final fullText =
        renderParagraph.text.toPlainText(includePlaceholders: true);
    if (fullText.isEmpty) {
      return const (start: 0, end: 0);
    }
    final lineExtents = _computeParagraphLineExtents(renderParagraph);
    if (lineExtents.isEmpty) {
      return null;
    }

    var probe = renderOffset.clamp(0, fullText.length).toInt();
    if (probe == fullText.length && probe > 0) {
      probe -= 1;
    }

    List<TextBox> probeBoxes = _boxesForDirectRenderOffset(
      renderParagraph,
      fullText,
      probe,
    );
    while (probeBoxes.isEmpty && probe > 0) {
      probe -= 1;
      probeBoxes =
          _boxesForDirectRenderOffset(renderParagraph, fullText, probe);
    }
    while (probeBoxes.isEmpty && probe < fullText.length - 1) {
      probe += 1;
      probeBoxes =
          _boxesForDirectRenderOffset(renderParagraph, fullText, probe);
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
      final previousBoxes = _boxesForDirectRenderOffset(
        renderParagraph,
        fullText,
        start - 1,
      );
      if (previousBoxes.isEmpty ||
          !_boxesOverlapLineExtent(previousBoxes, lineExtent)) {
        break;
      }
      start -= 1;
    }

    var end = probe + 1;
    while (end < fullText.length) {
      final nextBoxes = _boxesForDirectRenderOffset(
        renderParagraph,
        fullText,
        end,
      );
      if (nextBoxes.isEmpty ||
          !_boxesOverlapLineExtent(nextBoxes, lineExtent)) {
        break;
      }
      end += 1;
    }

    return (start: start, end: end);
  }

  List<TextBox> _boxesForDirectRenderOffset(
    RenderParagraph renderParagraph,
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
    return renderParagraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
  }

  bool _boxesOverlapLineExtent(
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

  GlobalKey? _createDirectTextKeyIfNeeded(
    List<MarkdownPretextInlineRun> runs,
  ) {
    if (markdownPretextCanUseDirectRichTextGeometry(runs)) {
      return GlobalKey();
    }
    return null;
  }

  List<Rect>? _resolveDirectRichTextSelectionRects(
    BuildContext context,
    GlobalKey directTextKey,
    DocumentRange range,
    List<MarkdownPretextInlineRun> runs,
  ) {
    final blockRenderObject = context.findRenderObject();
    final renderParagraph = _resolveDirectRenderParagraph(
      directTextKey,
      runs: runs,
      fallbackRoot: blockRenderObject,
    );
    if (renderParagraph == null ||
        blockRenderObject is! RenderBox ||
        !blockRenderObject.hasSize) {
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
    final paragraphOrigin = blockRenderObject.globalToLocal(
      renderParagraph.localToGlobal(Offset.zero),
    );
    // The paragraph found via GlobalKey may not have completed layout
    // in the current frame (e.g. during scroll-triggered rebuilds).
    final List<TextBox> selectionBoxes;
    List<({double top, double bottom})> lineExtents;
    try {
      lineExtents = _computeParagraphLineExtents(renderParagraph);
      selectionBoxes = renderParagraph.getBoxesForSelection(renderSelection);
    } on AssertionError {
      return null;
    }
    final boxes = _mergeDirectTextSelectionBoxes(
      _normalizeBoxesToLineExtents(selectionBoxes, lineExtents),
    );
    return boxes
        .map(
          (box) => Rect.fromLTRB(
            box.left + paragraphOrigin.dx - 1.5,
            box.top + paragraphOrigin.dy,
            box.right + paragraphOrigin.dx + 1.5,
            box.bottom + paragraphOrigin.dy,
          ),
        )
        .toList(growable: false);
  }

  int? _resolveDirectRichTextTextOffset(
    BuildContext context,
    GlobalKey directTextKey,
    Offset localPosition,
    List<MarkdownPretextInlineRun> runs,
  ) {
    final blockRenderObject = context.findRenderObject();
    final renderParagraph = _resolveDirectRenderParagraph(
      directTextKey,
      runs: runs,
      fallbackRoot: blockRenderObject,
    );
    if (renderParagraph == null ||
        blockRenderObject is! RenderBox ||
        !blockRenderObject.hasSize) {
      return null;
    }

    final paragraphPosition = renderParagraph.globalToLocal(
      blockRenderObject.localToGlobal(localPosition),
    );
    final textPosition = renderParagraph.getPositionForOffset(
      paragraphPosition,
    );
    return markdownPretextPlainOffsetForRenderOffset(runs, textPosition.offset);
  }

  RenderParagraph? _resolveDirectRenderParagraph(
    GlobalKey directTextKey, {
    List<MarkdownPretextInlineRun>? runs,
    RenderObject? fallbackRoot,
  }) {
    final renderObject = directTextKey.currentContext?.findRenderObject();
    final expectedRenderText =
        runs == null ? null : markdownPretextRenderText(runs);
    if (renderObject is RenderParagraph &&
        renderObject.hasSize &&
        (expectedRenderText == null ||
            renderObject.text.toPlainText(includePlaceholders: true) ==
                expectedRenderText)) {
      return renderObject;
    }
    RenderParagraph? paragraph;

    void visit(RenderObject node) {
      if (paragraph != null) {
        return;
      }
      if (node is RenderParagraph &&
          node.hasSize &&
          (expectedRenderText == null ||
              node.text.toPlainText(includePlaceholders: true) ==
                  expectedRenderText)) {
        paragraph = node;
        return;
      }
      node.visitChildren(visit);
    }

    if (renderObject != null) {
      visit(renderObject);
    }
    if (paragraph == null &&
        fallbackRoot != null &&
        fallbackRoot != renderObject) {
      visit(fallbackRoot);
    }
    return paragraph;
  }

  Widget _buildNestedBlockContent(BuildContext context, BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        return _wrapHeadingBlock(
          level: heading.level,
          child: _buildTextBlock(
            style: theme.headingStyleForLevel(heading.level),
            inlines: heading.inlines,
          ),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        return _buildTextBlock(
          style: theme.bodyStyle,
          inlines: paragraph.inlines,
        );
      case MarkdownBlockKind.quote:
        return _buildQuote(context, block as QuoteBlock);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _buildList(context, block as ListBlock);
      case MarkdownBlockKind.definitionList:
        return _buildDefinitionList(context, block as DefinitionListBlock);
      case MarkdownBlockKind.footnoteList:
        return _buildFootnoteList(context, block as FootnoteListBlock);
      case MarkdownBlockKind.codeBlock:
        return _buildCodeBlock(context, block as CodeBlock);
      case MarkdownBlockKind.table:
        return _buildTable(context, block as TableBlock);
      case MarkdownBlockKind.image:
        return _buildImage(context, block as ImageBlock);
      case MarkdownBlockKind.thematicBreak:
        return Divider(
          color: theme.dividerColor,
          height: 1,
          thickness: 1,
        );
    }
  }

  Widget _buildQuote(BuildContext context, QuoteBlock block) {
    return MarkdownQuoteBlockView(
      theme: theme,
      child: _buildQuoteContent(
        context,
        block,
        childKeys: keysRegistry.quoteChildKeysFor(block),
      ),
    );
  }

  Widget _buildQuoteContent(
    BuildContext context,
    QuoteBlock block, {
    List<GlobalKey>? childKeys,
  }) {
    return DefaultTextStyle.merge(
      style: theme.quoteStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildNestedBlocks(
          context,
          block.children,
          blockKeyBuilder:
              childKeys == null ? null : (index) => childKeys[index],
        ),
      ),
    );
  }

  List<Widget> _buildNestedBlocks(
    BuildContext context,
    List<BlockNode> blocks, {
    Key? Function(int index)? blockKeyBuilder,
  }) {
    return <Widget>[
      for (var index = 0; index < blocks.length; index++)
        KeyedSubtree(
          key: blockKeyBuilder?.call(index),
          child: Padding(
            padding: EdgeInsets.only(
              bottom:
                  index == blocks.length - 1 ? 0 : theme.blockSpacing * 0.65,
            ),
            child: _buildNestedBlockContent(context, blocks[index]),
          ),
        ),
    ];
  }

  Widget _buildList(BuildContext context, ListBlock block) {
    final itemRowKeys = keysRegistry.listItemKeysFor(block);
    final itemContentKeys = keysRegistry.listItemContentKeysFor(block);
    return MarkdownListBlockView(
      theme: theme,
      block: block,
      itemBuilder: (index, item) =>
          _buildListItemContent(context, block, index, item),
      itemRowKeyBuilder: (index) => itemRowKeys[index],
      itemContentKeyBuilder: (index) => itemContentKeys[index],
      bulletBuilder: bulletBuilder,
    );
  }

  Widget _buildDefinitionList(BuildContext context, DefinitionListBlock block) {
    final descriptor =
        descriptorExtractor.buildDefinitionListSelectableDescriptor(block);
    return _buildDescriptorTextWidget(descriptor);
  }

  Widget _buildFootnoteList(BuildContext context, FootnoteListBlock block) {
    final orderedFootnotes =
        MarkdownDescriptorExtractor.footnoteListAsOrderedList(block);
    final itemRowKeys = keysRegistry.listItemKeysFor(orderedFootnotes);
    final itemContentKeys =
        keysRegistry.listItemContentKeysFor(orderedFootnotes);
    return _buildFootnoteListContainer(
      child: MarkdownListBlockView(
        theme: theme,
        block: orderedFootnotes,
        itemBuilder: (index, item) =>
            _buildListItemContent(context, orderedFootnotes, index, item),
        itemRowKeyBuilder: (index) => itemRowKeys[index],
        itemContentKeyBuilder: (index) => itemContentKeys[index],
        bulletBuilder: bulletBuilder,
      ),
    );
  }

  Widget _buildListItemContent(
    BuildContext context,
    ListBlock block,
    int itemIndex,
    ListItemNode item,
  ) {
    if (item.children.isEmpty) {
      return const SizedBox.shrink();
    }

    final childKeys = keysRegistry.listItemChildKeysFor(block, itemIndex);
    if (item.children.length == 1) {
      return KeyedSubtree(
        key: childKeys.first,
        child: _buildNestedBlockContent(context, item.children.first),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildNestedBlocks(
        context,
        item.children,
        blockKeyBuilder: (index) => childKeys[index],
      ),
    );
  }

  Widget _buildTextBlock({
    required TextStyle style,
    required List<InlineNode> inlines,
    TextAlign textAlign = TextAlign.start,
  }) {
    final runs = inlineBuilder.buildPretextRuns(style, inlines);
    return MarkdownPretextTextBlock.rich(
      runs: runs,
      fallbackStyle: style,
      textAlign: textAlign,
      preferDirectRichText: markdownPretextCanUseDirectRichTextGeometry(runs),
    );
  }

  Widget _wrapHeadingBlock({
    required int level,
    required Widget child,
  }) {
    if (level > 2) {
      return child;
    }

    final showDivider =
        level == 1 ? theme.showHeading1Divider : theme.showHeading2Divider;
    if (!showDivider) {
      return child;
    }

    final dividerSpacing = level == 1 ? 12.0 : 8.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        child,
        SizedBox(height: dividerSpacing),
        Divider(
          color: theme.dividerColor,
          height: 1,
          thickness: 1,
        ),
      ],
    );
  }

  Widget _buildCodeBlock(BuildContext context, CodeBlock block) {
    if (codeBlockBuilder != null) {
      return codeBlockBuilder!(context, block.code, block.language, theme);
    }
    final scrollController = keysRegistry.codeBlockScrollControllers
        .putIfAbsent(block.id, ScrollController.new);
    return _buildDecoratedCodeBlock(
      block,
      codeSpan: _buildCodeTextSpan(block),
      scrollController: scrollController,
    );
  }

  Widget _buildDecoratedCodeBlock(
    CodeBlock block, {
    required InlineSpan codeSpan,
    ScrollController? scrollController,
    GlobalKey? directTextKey,
  }) {
    return MarkdownCodeBlockView(
      theme: theme,
      codeSpan: codeSpan,
      directTextKey: directTextKey,
      scrollController: scrollController ??
          keysRegistry.codeBlockScrollControllers
              .putIfAbsent(block.id, ScrollController.new),
      onCopyCode: () {
        Clipboard.setData(ClipboardData(text: block.code));
      },
    );
  }

  InlineSpan _buildCodeTextSpan(CodeBlock block) {
    return codeSyntaxHighlighter.buildTextSpan(
      source: block.code,
      baseStyle: theme.codeBlockStyle,
      theme: theme,
      language: block.language,
    );
  }

  Widget _buildTable(
    BuildContext context,
    TableBlock block, {
    Key? Function(int rowIndex, int columnIndex)? cellKeyBuilder,
    GlobalKey? Function(int rowIndex, int columnIndex)? cellTextKeyBuilder,
    ScrollController? scrollController,
  }) {
    return MarkdownTableBlockView(
      theme: theme,
      block: block,
      textWidgetBuilder: _buildInlineTextWidget,
      cellKeyBuilder: cellKeyBuilder,
      cellTextKeyBuilder: cellTextKeyBuilder,
      scrollController: scrollController ??
          keysRegistry.tableScrollControllers
              .putIfAbsent(block.id, ScrollController.new),
    );
  }

  Widget _buildInlineTextWidget(
    BuildContext context,
    TextStyle style,
    List<InlineNode> inlines,
    TextAlign textAlign, {
    GlobalKey? directTextKey,
    bool alignInlineMathToBaseline = true,
  }) {
    return MarkdownPretextTextBlock.rich(
      runs: inlineBuilder.buildPretextRuns(
        style,
        inlines,
        alignInlineMathToBaseline: alignInlineMathToBaseline,
      ),
      fallbackStyle: style,
      textAlign: textAlign,
      intrinsicWidthSafe: true,
      directTextKey: directTextKey,
    );
  }

  Widget _buildImage(BuildContext context, ImageBlock block) {
    if (imageBuilder != null) {
      return _wrapLinkedImage(
        block,
        imageBuilder!(context, block, theme),
      );
    }
    final caption = MarkdownDescriptorExtractor.imageCaptionText(block);
    final captionDescriptor =
        descriptorExtractor.buildImageCaptionDescriptor(block);
    final imageState =
        _buildImageVisual(context, block, hasCaption: caption.isNotEmpty);
    return MarkdownImageBlockView(
      theme: theme,
      image: imageState.image,
      hasErrorNotifier: imageState.hasErrorNotifier,
      hasKnownSize: imageState.hasKnownSize,
      caption: caption.isNotEmpty
          ? _buildDescriptorTextWidget(captionDescriptor)
          : null,
    );
  }

  ({Widget image, ValueNotifier<bool> hasErrorNotifier, bool hasKnownSize})
      _buildImageVisual(BuildContext context, ImageBlock block,
          {bool hasCaption = false}) {
    final uri = Uri.tryParse(block.url);
    double? w;
    double? h;
    if (uri != null) {
      final wStr = uri.queryParameters['w'] ?? uri.queryParameters['width'];
      final hStr = uri.queryParameters['h'] ?? uri.queryParameters['height'];
      if (wStr != null) w = double.tryParse(wStr);
      if (hStr != null) h = double.tryParse(hStr);
    }
    final hasKnownSize = w != null && h != null;
    final hasErrorNotifier = keysRegistry.imageErrorNotifiers
        .putIfAbsent(block.id, () => ValueNotifier<bool>(false));

    if (imageBuilder != null) {
      return (
        image: _wrapLinkedImage(block, imageBuilder!(context, block, theme)),
        hasErrorNotifier: hasErrorNotifier,
        hasKnownSize: hasKnownSize,
      );
    }
    final isNetwork =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final localImageProvider = resolveMarkdownLocalImageProvider(block.url);

    Widget errorBuilder(BuildContext ctx, Object err, StackTrace? st) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!hasErrorNotifier.value) hasErrorNotifier.value = true;
      });
      if (hasKnownSize) {
        return Container(
          width: w,
          height: h,
          color: theme.imagePlaceholderBackgroundColor,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_outlined, color: theme.dividerColor),
        );
      } else {
        if (hasCaption) {
          return Icon(
            Icons.broken_image_outlined,
            size: 18,
            color: theme.bodyStyle.color?.withValues(alpha: 0.72),
          );
        }
        final altText = MarkdownDescriptorExtractor.imageCaptionText(block);
        final text = altText.isNotEmpty ? altText : 'Image';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.imagePlaceholderBackgroundColor,
            borderRadius: theme.imageBorderRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  size: 18,
                  color: theme.bodyStyle.color?.withValues(alpha: 0.72)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: theme.bodyStyle.copyWith(
                      color: theme.bodyStyle.color?.withValues(alpha: 0.72)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }
    }

    final image = isNetwork
        ? Image.network(
            block.url,
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: errorBuilder,
          )
        : localImageProvider != null
            ? Image(
                image: localImageProvider,
                width: w,
                height: h,
                fit: BoxFit.cover,
                errorBuilder: errorBuilder,
              )
            : Image.asset(
                block.url,
                width: w,
                height: h,
                fit: BoxFit.cover,
                errorBuilder: errorBuilder,
              );
    return (
      image: _wrapLinkedImage(
        block,
        ClipRRect(
          borderRadius: theme.imageBorderRadius,
          child: image,
        ),
      ),
      hasErrorNotifier: hasErrorNotifier,
      hasKnownSize: hasKnownSize,
    );
  }

  Widget _wrapLinkedImage(ImageBlock block, Widget child) {
    final destination = block.linkDestination;
    if (destination == null || destination.isEmpty || onTapLink == null) {
      return child;
    }
    final label = MarkdownDescriptorExtractor.imageCaptionText(block).isNotEmpty
        ? MarkdownDescriptorExtractor.imageCaptionText(block)
        : block.url;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          onTapLink!(destination, block.linkTitle, label);
        },
        child: child,
      ),
    );
  }

  SelectableBlockSpec _buildCustomImageBuilderSpec(
      BuildContext context, ImageBlock block) {
    final caption = MarkdownDescriptorExtractor.imageCaptionText(block);
    final blockPlainText = caption.isEmpty ? block.url : caption;
    final imageState = _buildImageVisual(context, block);
    return SelectableBlockSpec(
      child: MarkdownImageBlockView(
        theme: theme,
        image: imageState.image,
        hasErrorNotifier: imageState.hasErrorNotifier,
        hasKnownSize: imageState.hasKnownSize,
        caption: caption.isEmpty
            ? null
            : _buildDescriptorTextWidget(
                descriptorExtractor.buildImageCaptionDescriptor(block),
                intrinsicWidthSafe: true,
              ),
      ),
      plainText: blockPlainText,
      hitTestBehavior: SelectableBlockHitTestBehavior.block,
      textOffsetResolver: (_, size, localPosition) {
        final leadingThreshold = math.min(size.width * 0.25, 24.0);
        return localPosition.dx <= leadingThreshold ? 0 : blockPlainText.length;
      },
      highlightBorderRadius: theme.imageBorderRadius,
    );
  }

  Widget _buildDescriptorTextWidget(
    SelectableTextDescriptor descriptor, {
    bool intrinsicWidthSafe = false,
    GlobalKey? directTextKey,
  }) {
    final pretext = descriptor.pretext;
    if (pretext == null) {
      return Text.rich(
        descriptor.span,
        style: pretext?.fallbackStyle,
      );
    }
    return MarkdownPretextTextBlock.rich(
      runs: pretext.runs,
      fallbackStyle: pretext.fallbackStyle,
      directTextKey: directTextKey,
      textAlign: pretext.textAlign,
      intrinsicWidthSafe: intrinsicWidthSafe,
      preferDirectRichText:
          markdownPretextCanUseDirectRichTextGeometry(pretext.runs),
    );
  }

  List<TextBox> _mergeDirectTextSelectionBoxes(List<TextBox> boxes) {
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
      final closeEnough = next.left <= current.right + gapTolerance;
      if (sameLine && closeEnough) {
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

  /// Compute each visual line's vertical extent by grouping the full
  /// paragraph's boxes (all characters selected) by vertical overlap.
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

    // Eliminate vertical gaps between lines by expanding their top/bottom bounds
    // to meet halfway. TextPainter limits boxes to glyph metrics, which omits
    // the line-height multiplier spacing and leaves ugly horizontal gaps in the
    // selection background.
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

  SelectableBlockSpec _buildSelectableDescriptorTextSpec({
    required SelectableTextDescriptor descriptor,
    StructuredBlockSelection? selectionStructure,
  }) {
    final pretext = descriptor.pretext;
    if (pretext == null) {
      return SelectableBlockSpec(
        child: _buildDescriptorTextWidget(descriptor),
        plainText: descriptor.plainText,
        hitTestBehavior: SelectableBlockHitTestBehavior.text,
        textSpan: descriptor.span,
        selectionStructure: selectionStructure,
      );
    }
    final directTextKey = _createDirectTextKeyIfNeeded(pretext.runs);
    return _buildPretextTextSpec(
      child: _buildDescriptorTextWidget(
        descriptor,
        directTextKey: directTextKey,
      ),
      plainText: descriptor.plainText,
      runs: pretext.runs,
      fallbackStyle: pretext.fallbackStyle,
      directTextKey: directTextKey,
      textAlign: pretext.textAlign,
      selectionStructure: selectionStructure,
    );
  }

  Color get _quoteSelectionColor {
    final opacity = math.min(
      math.max(theme.selectionColor.a * 0.72, 0.14),
      0.2,
    );
    return theme.selectionColor.withValues(alpha: opacity);
  }

  StructuredBlockSelection? _matchingSelectionStructure(
    BlockNode block,
    String plainText,
  ) {
    final structure = StructuredBlockSelection.forBlock(block);
    if (structure.plainText != plainText) {
      return null;
    }
    return structure;
  }

  Widget _buildFootnoteListContainer({
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: child,
      ),
    );
  }

  String _selectionSignatureForBlock({
    required BlockNode block,
    required int blockIndex,
    required DocumentRange? selectionRange,
  }) {
    if (block is TableBlock) {
      return _isBlockCoveredByTextSelection(blockIndex, selectionRange)
          ? 'table:text'
          : 'table:none';
    }

    if (selectionRange == null ||
        blockIndex < selectionRange.start.blockIndex ||
        blockIndex > selectionRange.end.blockIndex) {
      return 'text:none';
    }
    final start = blockIndex == selectionRange.start.blockIndex
        ? selectionRange.start.textOffset
        : 0;
    final end = blockIndex == selectionRange.end.blockIndex
        ? selectionRange.end.textOffset
        : plainTextSerializer.serializeBlockText(block).length;
    return 'text:$start:$end';
  }

  bool _isBlockCoveredByTextSelection(
    int blockIndex,
    DocumentRange? selectionRange,
  ) {
    return selectionRange != null &&
        blockIndex >= selectionRange.start.blockIndex &&
        blockIndex <= selectionRange.end.blockIndex;
  }

  bool _canCacheBlockRow(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        return !_inlinesContainLinks((block as HeadingBlock).inlines);
      case MarkdownBlockKind.paragraph:
        return !_inlinesContainLinks((block as ParagraphBlock).inlines);
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.footnoteList:
        return false;
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.thematicBreak:
        return true;
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return false;
    }
  }

  bool _inlinesContainLinks(List<InlineNode> inlines) {
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.link:
          return true;
        case MarkdownInlineKind.math:
          break;
        case MarkdownInlineKind.emphasis:
          if (_inlinesContainLinks((inline as EmphasisInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.strong:
          if (_inlinesContainLinks((inline as StrongInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.strikethrough:
          if (_inlinesContainLinks((inline as StrikethroughInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.highlight:
          if (_inlinesContainLinks((inline as HighlightInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.subscript:
          if (_inlinesContainLinks((inline as SubscriptInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.superscript:
          if (_inlinesContainLinks((inline as SuperscriptInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.text:
        case MarkdownInlineKind.inlineCode:
        case MarkdownInlineKind.softBreak:
        case MarkdownInlineKind.hardBreak:
        case MarkdownInlineKind.image:
          break;
      }
    }
    return false;
  }
}

class CachedBlockRow {
  const CachedBlockRow({
    required this.block,
    required this.blockIndex,
    required this.selectionSignature,
    required this.widget,
  });

  final BlockNode block;
  final int blockIndex;
  final String selectionSignature;
  final Widget widget;
}
