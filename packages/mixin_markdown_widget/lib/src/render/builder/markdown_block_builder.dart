import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import '../../clipboard/plain_text_serializer.dart';
import '../../core/document.dart';
import '../../debug.dart';
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
import '../selection/markdown_selectable_leaf.dart';
import '../selection/markdown_selection_geometry.dart';
import '../selection/markdown_block_keys_registry.dart';
import '../local_image_provider_stub.dart'
    if (dart.library.io) '../local_image_provider_io.dart';

class MarkdownBlockBuilder {
  static const double _slowBlockBuildLogThresholdMs = 2;

  MarkdownBlockBuilder({
    required this.theme,
    required this.selectionController,
    required this.document,
    required this.isSelectable,
    required this.keysRegistry,
    required this.descriptorExtractor,
    required this.inlineBuilder,
    required this.codeSyntaxHighlighter,
    required this.plainTextSerializer,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.bulletBuilder,
    this.onTapLink,
    required this.onRequestContextMenu,
    required Map<String, CachedBlockRow> cachedBlockRows,
    required this.tableLayoutPlanCache,
    required this.codeHighlightCache,
  }) : _cachedBlockRows = cachedBlockRows;

  final MarkdownThemeData theme;
  final MarkdownSelectionController? selectionController;
  final MarkdownDocument document;
  final bool isSelectable;
  final MarkdownBlockKeysRegistry keysRegistry;
  final MarkdownDescriptorExtractor descriptorExtractor;
  final MarkdownInlineBuilder inlineBuilder;
  final MarkdownCodeSyntaxHighlighter codeSyntaxHighlighter;
  final MarkdownPlainTextSerializer plainTextSerializer;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownCodeBlockBuilder? codeBlockBuilder;
  final MarkdownBulletBuilder? bulletBuilder;
  final MarkdownTapLinkCallback? onTapLink;
  final void Function(Offset) onRequestContextMenu;
  final MarkdownTableLayoutPlanCache tableLayoutPlanCache;
  final MarkdownCodeHighlightCache codeHighlightCache;

  final Map<String, CachedBlockRow> _cachedBlockRows;

  Widget buildBlockListItem(
    BuildContext context, {
    required BlockNode block,
    required int blockIndex,
    int? selectionBlockIndex,
    required DocumentRange? selectionRange,
  }) {
    final buildStopwatch = Stopwatch()..start();
    final cacheable = _canCacheBlockRow(block);
    final themeSignature = theme.hashCode;
    final effectiveSelectionBlockIndex = selectionBlockIndex ?? blockIndex;
    final selectionSignature = _selectionSignatureForBlock(
      block: block,
      blockIndex: effectiveSelectionBlockIndex,
      selectionRange: selectionRange,
    );

    if (cacheable) {
      final cached = _cachedBlockRows[block.id];
      if (cached != null &&
          identical(cached.block, block) &&
          cached.blockIndex == effectiveSelectionBlockIndex &&
          cached.themeSignature == themeSignature &&
          cached.selectionSignature == selectionSignature) {
        return cached.widget;
      }
    }

    final widget = Padding(
      padding: EdgeInsets.only(
        bottom: _spacingAfterTopLevelBlock(blockIndex),
      ),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: theme.maxContentWidth),
          child: _buildBlockView(
            context,
            block: block,
            blockIndex: effectiveSelectionBlockIndex,
            selectionRange: selectionRange,
          ),
        ),
      ),
    );

    if (!cacheable) {
      _logSlowBlockBuild(
        stopwatch: buildStopwatch,
        block: block,
        blockIndex: blockIndex,
        cacheable: cacheable,
        fromCache: false,
      );
      _cachedBlockRows.remove(block.id);
      return widget;
    }

    _logSlowBlockBuild(
      stopwatch: buildStopwatch,
      block: block,
      blockIndex: effectiveSelectionBlockIndex,
      cacheable: cacheable,
      fromCache: false,
    );
    _cachedBlockRows[block.id] = CachedBlockRow(
      block: block,
      blockIndex: effectiveSelectionBlockIndex,
      themeSignature: themeSignature,
      selectionSignature: selectionSignature,
      widget: widget,
    );
    return widget;
  }

  void _logSlowBlockBuild({
    required Stopwatch stopwatch,
    required BlockNode block,
    required int blockIndex,
    required bool cacheable,
    required bool fromCache,
  }) {
    stopwatch.stop();
    if (!mixinMarkdownDebugLogging) {
      return;
    }
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    if (elapsedMs < _slowBlockBuildLogThresholdMs) {
      return;
    }
    debugPrint(
      '[mixin_markdown_widget] block.build '
      'index=$blockIndex '
      'kind=${block.kind.name} '
      'cacheable=$cacheable '
      'fromCache=$fromCache '
      'elapsed=${elapsedMs.toStringAsFixed(3)}ms',
    );
  }

  double _spacingAfterTopLevelBlock(int blockIndex) {
    if (blockIndex >= document.blocks.length - 1) {
      return 0;
    }
    return _blockSpacingBetween(
      document.blocks[blockIndex],
      document.blocks[blockIndex + 1],
      nested: false,
    );
  }

  double _blockSpacingBetween(
    BlockNode current,
    BlockNode? next, {
    required bool nested,
  }) {
    if (next == null) {
      return 0;
    }

    final base = nested ? theme.blockSpacing * 0.72 : theme.blockSpacing;
    final currentHeading = current is HeadingBlock ? current : null;
    final nextHeading = next is HeadingBlock ? next : null;

    if (_isStandaloneLineBreakBlock(current) ||
        _isStandaloneLineBreakBlock(next)) {
      return 0;
    }
    if (nested && _isListTransitionWithinListItem(current, next)) {
      return theme.listItemSpacing;
    }
    if (currentHeading != null) {
      return _headingTrailingSpacing(currentHeading.level, base);
    }
    if (nextHeading != null) {
      return _headingLeadingSpacing(nextHeading.level, base);
    }
    if (_isThematicBreakLike(current) || _isThematicBreakLike(next)) {
      return base * (nested ? 0.95 : 1.1);
    }
    if (_isDecoratedBlock(current) || _isDecoratedBlock(next)) {
      return base * 0.85;
    }
    if (_isListLikeBlock(current) || _isListLikeBlock(next)) {
      return base * 0.9;
    }
    return base;
  }

  double _headingLeadingSpacing(int level, double base) {
    switch (level) {
      case 1:
        return base * 1.45;
      case 2:
        return base * 1.25;
      case 3:
        return base * 1.1;
      default:
        return base;
    }
  }

  double _headingTrailingSpacing(int level, double base) {
    switch (level) {
      case 1:
        return base * 0.85;
      case 2:
        return base * 0.8;
      case 3:
        return base * 0.75;
      default:
        return base * 0.7;
    }
  }

  bool _isDecoratedBlock(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.details:
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
        return true;
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.footnoteList:
      case MarkdownBlockKind.thematicBreak:
        return false;
    }
  }

  bool _isListLikeBlock(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.footnoteList:
        return true;
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.details:
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        return false;
    }
  }

  bool _isThematicBreakLike(BlockNode block) =>
      block.kind == MarkdownBlockKind.thematicBreak;

  bool _isStandaloneLineBreakBlock(BlockNode block) {
    if (block is! ParagraphBlock || block.inlines.length != 1) {
      return false;
    }
    return block.inlines.single.kind == MarkdownInlineKind.hardBreak;
  }

  bool _isListTransitionWithinListItem(BlockNode current, BlockNode next) {
    return (current.kind == MarkdownBlockKind.paragraph &&
            _isListLikeBlock(next)) ||
        (_isListLikeBlock(current) && _isListLikeBlock(next));
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
        final geometry = MarkdownTextLeafGeometry(
          runs: inlineBuilder.buildPretextRuns(style, heading.inlines),
          fallbackStyle: style,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(heading.inlines),
        );
        return _buildTextLeafSpec(
          child: _wrapHeadingBlock(
            level: heading.level,
            child: _textLeaf(_topLevelLeafPath, geometry),
          ),
          plainText: plainText,
          geometry: geometry,
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        final plainText =
            MarkdownInlineBuilder.flattenInlineText(paragraph.inlines);
        if (_isStandaloneLineBreakBlock(paragraph)) {
          return SelectableBlockSpec(
            child: _buildStandaloneLineBreak(context),
            plainText: plainText,
            hitTestBehavior: SelectableBlockHitTestBehavior.block,
          );
        }
        final geometry = MarkdownTextLeafGeometry(
          runs: inlineBuilder.buildPretextRuns(
            theme.bodyStyle,
            paragraph.inlines,
          ),
          fallbackStyle: theme.bodyStyle,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(paragraph.inlines),
        );
        return _buildTextLeafSpec(
          child: _textLeaf(_topLevelLeafPath, geometry),
          plainText: plainText,
          geometry: geometry,
        );
      case MarkdownBlockKind.quote:
        final quoteBlock = block as QuoteBlock;
        final descriptor =
            descriptorExtractor.buildSelectableDescriptorForBlock(quoteBlock);
        return _buildContainerSpec(
          block: quoteBlock,
          child: MarkdownQuoteBlockView(
            theme: theme,
            child: _buildQuoteContent(
              context,
              quoteBlock,
              path: const <int>[],
            ),
          ),
          textSpan: descriptor.span,
          highlightBorderRadius: theme.quoteBorderRadius,
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
          selectionColor: _quoteSelectionColor,
          repaintListenable:
              _nestedScrollableRepaintListenableForBlocks(quoteBlock.children),
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        final listBlock = block as ListBlock;
        final descriptor =
            descriptorExtractor.buildSelectableDescriptorForBlock(listBlock);
        return _buildContainerSpec(
          block: listBlock,
          child: MarkdownListBlockView(
            theme: theme,
            block: listBlock,
            itemBuilder: (index, item) => _buildListItemContent(
              context,
              listBlock,
              index,
              item,
              path: const <int>[],
            ),
            itemSlotBuilder: _listItemSlotBuilder(const <int>[]),
            bulletBuilder: bulletBuilder,
          ),
          textSpan: descriptor.span,
          repaintListenable:
              _nestedScrollableRepaintListenableForListBlock(listBlock),
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
        return _buildContainerSpec(
          block: footnoteList,
          child: _buildFootnoteListContainer(
            child: MarkdownListBlockView(
              theme: theme,
              block: orderedFootnotes,
              itemBuilder: (index, item) => _buildListItemContent(
                context,
                orderedFootnotes,
                index,
                item,
                path: const <int>[],
              ),
              itemSlotBuilder: _listItemSlotBuilder(const <int>[]),
              bulletBuilder: bulletBuilder,
            ),
          ),
          textSpan: footnoteDescriptor.span,
          repaintListenable:
              _nestedScrollableRepaintListenableForListBlock(orderedFootnotes),
          highlightBorderRadius: BorderRadius.circular(8),
        );
      case MarkdownBlockKind.details:
        final detailsBlock = block as DetailsBlock;
        final descriptor =
            descriptorExtractor.buildDetailsSelectableDescriptor(detailsBlock);
        return _buildContainerSpec(
          block: detailsBlock,
          child: _buildDetails(
            context,
            detailsBlock,
            path: const <int>[],
          ),
          textSpan: descriptor.span,
          highlightBorderRadius: theme.quoteBorderRadius,
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
          repaintListenable: _nestedScrollableRepaintListenableForBlocks(
            detailsBlock.children,
          ),
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        final codeHighlightPresentation = codeHighlightCache.resolve(
          blockId: codeBlock.id,
          source: codeBlock.code,
          baseStyle: theme.codeBlockStyle,
          theme: theme,
          language: codeBlock.language,
        );
        final scrollController = keysRegistry.codeBlockScrollControllers
            .putIfAbsent(codeBlock.id, ScrollController.new);
        final viewportKey = keysRegistry.codeBlockViewportKeys.putIfAbsent(
          codeBlock.id,
          () => GlobalKey(debugLabel: 'code-viewport-${codeBlock.id}'),
        );
        final geometry = MarkdownTextLeafGeometry(
          runs: codeHighlightPresentation.runs,
          fallbackStyle: theme.codeBlockStyle,
          direct: true,
          viewportKey: viewportKey,
        );
        return _buildTextLeafSpec(
          child: MarkdownSelectableLeaf(
            path: _topLevelLeafPath,
            geometry: geometry,
            child: _buildDecoratedCodeBlock(
              codeBlock,
              codeSpan: codeHighlightPresentation.span,
              scrollController: scrollController,
              viewportKey: viewportKey,
            ),
          ),
          plainText: codeBlock.code,
          geometry: geometry,
          clipToLeaf: true,
          measurementPadding: EdgeInsets.fromLTRB(
            theme.codeBlockPadding.resolve(Directionality.of(context)).left,
            math.max(
              0,
              theme.codeBlockPadding.resolve(Directionality.of(context)).top,
            ),
            math.max(
                  8,
                  theme.codeBlockPadding
                          .resolve(Directionality.of(context))
                          .right -
                      4,
                ) +
                24,
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
            math.max(
                  8,
                  theme.codeBlockPadding
                          .resolve(Directionality.of(context))
                          .right -
                      4,
                ) +
                24,
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
        final descriptor =
            descriptorExtractor.buildSelectableDescriptorForBlock(tableBlock);
        final scrollController = keysRegistry.tableScrollControllers
            .putIfAbsent(tableBlock.id, ScrollController.new);
        final viewportKey = keysRegistry.tableViewportKeys.putIfAbsent(
          tableBlock.id,
          () => GlobalKey(debugLabel: 'table-viewport-${tableBlock.id}'),
        );
        return _buildContainerSpec(
          block: tableBlock,
          child: _buildTable(
            context,
            tableBlock,
            scrollController: scrollController,
            viewportKey: viewportKey,
          ),
          textSpan: descriptor.span,
          highlightBorderRadius: theme.tableBorderRadius,
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
          repaintListenable: scrollController,
          selectionColor: theme.selectionColor,
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

  static const PathInBlock _topLevelLeafPath = PathInBlock(<int>[0]);

  /// The spec of a container block: a quote, details, list, footnote list,
  /// or table. Its text and offsets are those of the block's
  /// [StructuredBlockSelection], and its geometry is read from the leaves and
  /// slots rendered in [child].
  SelectableBlockSpec _buildContainerSpec({
    required BlockNode block,
    required Widget child,
    required InlineSpan textSpan,
    BorderRadius? highlightBorderRadius,
    SelectableBlockSelectionPaintOrder selectionPaintOrder =
        SelectableBlockSelectionPaintOrder.behindChild,
    Color? selectionColor,
    Listenable? repaintListenable,
  }) {
    final structure = StructuredBlockSelection.forBlock(block);
    return SelectableBlockSpec(
      child: child,
      plainText: structure.plainText,
      selectionStructure: structure.isEmpty ? null : structure,
      hitTestBehavior: SelectableBlockHitTestBehavior.text,
      textSpan: textSpan,
      highlightBorderRadius: highlightBorderRadius,
      selectionPaintOrder: selectionPaintOrder,
      selectionColor: selectionColor,
      repaintListenable: repaintListenable,
      selectionRectResolver: (context, _, range) =>
          MarkdownContainerSelectionGeometry.rects(context, block, range),
      textOffsetResolver: (context, _, localPosition) =>
          MarkdownContainerSelectionGeometry.offsetAt(
        context,
        block,
        localPosition,
      ),
      selectionUnitRangeResolver: (context, _, localPosition, position) =>
          MarkdownContainerSelectionGeometry.unitAt(
        context,
        block,
        localPosition,
        position,
      ),
    );
  }

  /// A selectable text leaf rendering the runs of [geometry].
  Widget _textLeaf(PathInBlock path, MarkdownTextLeafGeometry geometry) {
    return MarkdownSelectableLeaf(
      path: path,
      geometry: geometry,
      child: MarkdownPretextTextBlock.rich(
        runs: geometry.runs,
        fallbackStyle: geometry.fallbackStyle,
        textAlign: geometry.textAlign,
        preferDirectRichText: geometry.direct,
      ),
    );
  }

  /// The spec of a block that is a single text leaf at [_topLevelLeafPath],
  /// whose local offsets are the block's display offsets. Before the leaf is
  /// laid out, geometry falls back to the pretext layout at the block width.
  SelectableBlockSpec _buildTextLeafSpec({
    required Widget child,
    required String plainText,
    required MarkdownTextLeafGeometry geometry,
    EdgeInsets measurementPadding = EdgeInsets.zero,
    BorderRadius? highlightBorderRadius,
    SelectableBlockSelectionPaintOrder? selectionPaintOrder,
    Listenable? repaintListenable,
    EdgeInsets? selectionClipPadding,
    StructuredBlockSelection? selectionStructure,
    bool clipToLeaf = false,
  }) {
    final hasInlineSurface = geometry.runs.any(
      (run) => run.decoration != null || run.renderSpan != null,
    );
    ({MarkdownSelectableLeafState leaf, Offset origin})? leafOf(
      BuildContext context,
    ) {
      final leaf = SelectableMarkdownBlockState.leafRegistryOf(context)
          ?.leaf(_topLevelLeafPath);
      final blockBox = context.findRenderObject();
      if (leaf == null || blockBox is! RenderBox || !blockBox.hasSize) {
        return null;
      }
      final origin = leaf.originIn(blockBox);
      return origin == null ? null : (leaf: leaf, origin: origin);
    }

    return SelectableBlockSpec(
      child: child,
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
      selectionClipRectResolver: clipToLeaf
          ? (context, _) {
              final resolved = leafOf(context);
              return resolved?.leaf.clipRect?.shift(resolved.origin);
            }
          : null,
      selectionRectResolver: (context, size, range) {
        final start = range.start.textOffset;
        final end = range.end.textOffset;
        final resolved = leafOf(context);
        if (resolved == null) {
          return geometry.layoutRects(context, size.width, start, end);
        }
        return resolved.leaf
            .rectsFor(start, end)
            .map((rect) => rect.shift(resolved.origin))
            .toList(growable: false);
      },
      textOffsetResolver: (context, size, localPosition) {
        final resolved = leafOf(context);
        if (resolved == null) {
          return geometry.layoutOffsetAt(context, size.width, localPosition);
        }
        return resolved.leaf.offsetAt(localPosition - resolved.origin);
      },
      selectionUnitRangeResolver: (context, size, localPosition, position) {
        final resolved = leafOf(context);
        final lineRange = resolved == null
            ? geometry.layoutLineRangeAt(
                context,
                size.width,
                position.textOffset,
                localPosition: localPosition,
              )
            : resolved.leaf.lineRangeAt(
                position.textOffset,
                localPosition: localPosition == null
                    ? null
                    : localPosition - resolved.origin,
              );
        if (lineRange == null) {
          return null;
        }
        return DocumentRange(
          start: DocumentPosition(
            blockIndex: position.blockIndex,
            path: _topLevelLeafPath,
            textOffset: lineRange.start,
          ),
          end: DocumentPosition(
            blockIndex: position.blockIndex,
            path: _topLevelLeafPath,
            textOffset: lineRange.end,
          ),
        );
      },
    );
  }

  TextStyle _styleForContext(TextStyle style, TextStyle? textStyleContext) {
    if (textStyleContext == null) {
      return style;
    }
    final bodyFontSize = theme.bodyStyle.fontSize;
    final contextFontSize = textStyleContext.fontSize;
    final styleFontSize = style.fontSize;
    final scaledFontSize =
        bodyFontSize == null || contextFontSize == null || styleFontSize == null
            ? styleFontSize ?? contextFontSize
            : styleFontSize * contextFontSize / bodyFontSize;
    return style.copyWith(
      color: textStyleContext.color,
      fontSize: scaledFontSize,
      fontStyle: textStyleContext.fontStyle,
    );
  }

  TextStyle? _linkStyleForContext(TextStyle? textStyleContext) {
    if (textStyleContext == null) {
      return null;
    }
    final linkColor = theme.linkStyle.color;
    return _styleForContext(theme.linkStyle, textStyleContext).copyWith(
      color: linkColor,
      decoration: theme.linkStyle.decoration,
      decorationColor: theme.linkStyle.decorationColor ?? linkColor,
    );
  }

  /// The leaf path of a block at [path]: a top-level block's own leaf is
  /// at `[0]`.
  PathInBlock _leafPath(List<int> path) {
    return PathInBlock(path.isEmpty ? const <int>[0] : path);
  }

  /// Builds a block nested at [path] in its top-level block, tagging its
  /// leaves and slots with the paths of the block's selection structure.
  Widget _buildNestedBlockContent(
    BuildContext context,
    BlockNode block, {
    TextStyle? paragraphStyle,
    List<int> path = const <int>[],
  }) {
    final effectiveParagraphStyle = paragraphStyle ?? theme.bodyStyle;
    final effectiveInlineCodeStyle = _styleForContext(
      theme.inlineCodeStyle,
      paragraphStyle,
    );
    final effectiveLinkStyle = _linkStyleForContext(paragraphStyle);
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        final style = _styleForContext(
          theme.headingStyleForLevel(heading.level),
          paragraphStyle,
        );
        return _wrapHeadingBlock(
          level: heading.level,
          child: _buildTextBlock(
            style: style,
            inlines: heading.inlines,
            inlineCodeStyle: effectiveInlineCodeStyle,
            linkStyle: effectiveLinkStyle,
            path: _leafPath(path),
          ),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        if (_isStandaloneLineBreakBlock(paragraph)) {
          return _buildStandaloneLineBreak(
            context,
            style: effectiveParagraphStyle,
          );
        }
        return _buildTextBlock(
          style: effectiveParagraphStyle,
          inlines: paragraph.inlines,
          inlineCodeStyle: effectiveInlineCodeStyle,
          linkStyle: effectiveLinkStyle,
          path: _leafPath(path),
        );
      case MarkdownBlockKind.quote:
        return _buildQuote(context, block as QuoteBlock, path: path);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _buildList(
          context,
          block as ListBlock,
          paragraphStyle: paragraphStyle,
          path: path,
        );
      case MarkdownBlockKind.definitionList:
        return _buildDefinitionList(
          context,
          block as DefinitionListBlock,
          path: path,
        );
      case MarkdownBlockKind.footnoteList:
        return _buildFootnoteList(
          context,
          block as FootnoteListBlock,
          path: path,
        );
      case MarkdownBlockKind.details:
        return _buildDetails(
          context,
          block as DetailsBlock,
          paragraphStyle: paragraphStyle,
          path: path,
        );
      case MarkdownBlockKind.codeBlock:
        return _buildCodeBlock(context, block as CodeBlock, path: path);
      case MarkdownBlockKind.table:
        return _buildTable(
          context,
          block as TableBlock,
          textStyleContext: paragraphStyle,
          path: path,
        );
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

  Widget _buildQuote(
    BuildContext context,
    QuoteBlock block, {
    required List<int> path,
  }) {
    return MarkdownQuoteBlockView(
      theme: theme,
      child: _buildQuoteContent(
        context,
        block,
        path: path,
      ),
    );
  }

  Widget _buildQuoteContent(
    BuildContext context,
    QuoteBlock block, {
    required List<int> path,
  }) {
    return DefaultTextStyle.merge(
      style: theme.quoteStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildNestedBlocks(
          context,
          block.children,
          paragraphStyle: theme.quoteStyle,
          pathFor: (index) => <int>[...path, index],
        ),
      ),
    );
  }

  List<Widget> _buildNestedBlocks(
    BuildContext context,
    List<BlockNode> blocks, {
    TextStyle? paragraphStyle,
    required List<int> Function(int index) pathFor,
  }) {
    return <Widget>[
      for (var index = 0; index < blocks.length; index++)
        _nestedChildSlot(
          blocks[index],
          pathFor(index),
          Padding(
            padding: EdgeInsets.only(
              bottom: index == blocks.length - 1
                  ? 0
                  : _blockSpacingBetween(
                      blocks[index],
                      blocks[index + 1],
                      nested: true,
                    ),
            ),
            child: _buildNestedBlockContent(
              context,
              blocks[index],
              paragraphStyle: paragraphStyle,
              path: pathFor(index),
            ),
          ),
        ),
    ];
  }

  /// The slot of a child block of a quote, details, or list item. A child
  /// drawn as a box, such as an image, is a placeholder leaf spanning the
  /// whole slot.
  Widget _nestedChildSlot(BlockNode block, List<int> path, Widget child) {
    final textLength = _isPlaceholderLeafBlock(block)
        ? StructuredBlockSelection.forBlock(block).plainText.length
        : null;
    return MarkdownSelectionSlot(
      path: PathInBlock(path),
      role: MarkdownSelectionSlotRole.child,
      child: textLength == null
          ? child
          : MarkdownSelectableLeaf(
              path: PathInBlock(path),
              geometry: MarkdownPlaceholderLeafGeometry(textLength: textLength),
              child: child,
            ),
    );
  }

  bool _isPlaceholderLeafBlock(BlockNode block) {
    return block.kind == MarkdownBlockKind.image ||
        block.kind == MarkdownBlockKind.thematicBreak ||
        _isStandaloneLineBreakBlock(block) ||
        (block.kind == MarkdownBlockKind.codeBlock && codeBlockBuilder != null);
  }

  Widget _buildList(
    BuildContext context,
    ListBlock block, {
    TextStyle? paragraphStyle,
    required List<int> path,
  }) {
    return MarkdownListBlockView(
      theme: theme,
      block: block,
      itemBuilder: (index, item) => _buildListItemContent(
        context,
        block,
        index,
        item,
        paragraphStyle: paragraphStyle,
        path: path,
      ),
      itemSlotBuilder: _listItemSlotBuilder(path),
      markerStyle: _styleForContext(theme.bodyStyle, paragraphStyle),
      bulletBuilder: bulletBuilder,
    );
  }

  /// Wraps the row and the content of each list item in the slots the list
  /// selection geometry reads.
  MarkdownListItemSlotBuilder _listItemSlotBuilder(List<int> path) {
    return (index, role, child) => MarkdownSelectionSlot(
          path: PathInBlock(<int>[...path, index]),
          role: role,
          child: child,
        );
  }

  Widget _buildDefinitionList(
    BuildContext context,
    DefinitionListBlock block, {
    required List<int> path,
  }) {
    final descriptor =
        descriptorExtractor.buildDefinitionListSelectableDescriptor(block);
    return _buildDescriptorTextWidget(descriptor, leafPath: _leafPath(path));
  }

  Widget _buildFootnoteList(
    BuildContext context,
    FootnoteListBlock block, {
    required List<int> path,
  }) {
    final orderedFootnotes =
        MarkdownDescriptorExtractor.footnoteListAsOrderedList(block);
    return _buildFootnoteListContainer(
      child: MarkdownListBlockView(
        theme: theme,
        block: orderedFootnotes,
        itemBuilder: (index, item) => _buildListItemContent(
          context,
          orderedFootnotes,
          index,
          item,
          path: path,
        ),
        itemSlotBuilder: _listItemSlotBuilder(path),
        bulletBuilder: bulletBuilder,
      ),
    );
  }

  Widget _buildDetails(
    BuildContext context,
    DetailsBlock block, {
    TextStyle? paragraphStyle,
    required List<int> path,
  }) {
    final summaryStyle = (paragraphStyle ?? theme.bodyStyle).copyWith(
      fontWeight: FontWeight.w600,
    );
    final summaryPath = PathInBlock(<int>[...path, 0]);
    return MarkdownDetailsBlockView(
      theme: theme,
      initiallyExpanded: block.initiallyExpanded,
      summary: MarkdownSelectionSlot(
        path: summaryPath,
        role: MarkdownSelectionSlotRole.child,
        child: _buildTextBlock(
          style: summaryStyle,
          inlines: block.summary,
          inlineCodeStyle:
              _styleForContext(theme.inlineCodeStyle, paragraphStyle),
          linkStyle: _linkStyleForContext(paragraphStyle),
          path: summaryPath,
        ),
      ),
      content: block.children.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildNestedBlocks(
                context,
                block.children,
                paragraphStyle: paragraphStyle,
                pathFor: (index) => <int>[...path, index + 1],
              ),
            ),
    );
  }

  /// The content of list item [itemIndex] of the list at [path].
  Widget _buildListItemContent(
    BuildContext context,
    ListBlock block,
    int itemIndex,
    ListItemNode item, {
    TextStyle? paragraphStyle,
    required List<int> path,
  }) {
    if (item.children.isEmpty) {
      return const SizedBox.shrink();
    }

    List<int> childPath(int index) => <int>[...path, itemIndex, index + 1];
    if (item.children.length == 1) {
      return _nestedChildSlot(
        item.children.first,
        childPath(0),
        _buildNestedBlockContent(
          context,
          item.children.first,
          paragraphStyle: paragraphStyle,
          path: childPath(0),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildNestedBlocks(
        context,
        item.children,
        paragraphStyle: paragraphStyle,
        pathFor: childPath,
      ),
    );
  }

  Widget _buildTextBlock({
    required TextStyle style,
    required List<InlineNode> inlines,
    TextAlign textAlign = TextAlign.start,
    TextStyle? inlineCodeStyle,
    TextStyle? linkStyle,
    required PathInBlock path,
  }) {
    return _textLeaf(
      path,
      MarkdownTextLeafGeometry(
        runs: inlineBuilder.buildPretextRuns(
          style,
          inlines,
          inlineCodeStyle: inlineCodeStyle,
          linkStyle: linkStyle,
        ),
        fallbackStyle: style,
        textAlign: textAlign,
      ),
    );
  }

  Widget _buildStandaloneLineBreak(
    BuildContext context, {
    TextStyle? style,
  }) {
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    return SizedBox(
      height: _preferredLineHeight(
        style ?? theme.bodyStyle,
        textScaler.scale(1.0),
      ),
    );
  }

  double _preferredLineHeight(TextStyle style, double textScaleFactor) {
    final textPainter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScaleFactor),
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    return textPainter.preferredLineHeight;
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

  Widget _buildCodeBlock(
    BuildContext context,
    CodeBlock block, {
    List<int> path = const <int>[],
  }) {
    if (codeBlockBuilder != null) {
      return codeBlockBuilder!(context, block.code, block.language, theme);
    }
    final codeHighlightPresentation = codeHighlightCache.resolve(
      blockId: block.id,
      source: block.code,
      baseStyle: theme.codeBlockStyle,
      theme: theme,
      language: block.language,
    );
    final scrollController = keysRegistry.codeBlockScrollControllers
        .putIfAbsent(block.id, ScrollController.new);
    final viewportKey = keysRegistry.codeBlockViewportKeys.putIfAbsent(
      block.id,
      () => GlobalKey(debugLabel: 'code-viewport-${block.id}'),
    );
    return MarkdownSelectableLeaf(
      path: _leafPath(path),
      geometry: MarkdownTextLeafGeometry(
        runs: codeHighlightPresentation.runs,
        fallbackStyle: theme.codeBlockStyle,
        direct: true,
        viewportKey: viewportKey,
      ),
      child: _buildDecoratedCodeBlock(
        block,
        codeSpan: codeHighlightPresentation.span,
        scrollController: scrollController,
        viewportKey: viewportKey,
      ),
    );
  }

  Widget _buildDecoratedCodeBlock(
    CodeBlock block, {
    required InlineSpan codeSpan,
    ScrollController? scrollController,
    GlobalKey? viewportKey,
  }) {
    return MarkdownCodeBlockView(
      theme: theme,
      codeSpan: codeSpan,
      viewportKey: viewportKey,
      scrollController: scrollController ??
          keysRegistry.codeBlockScrollControllers
              .putIfAbsent(block.id, ScrollController.new),
      onCopyCode: () {
        Clipboard.setData(ClipboardData(text: block.code));
      },
    );
  }

  Listenable? _nestedScrollableRepaintListenableForListBlock(ListBlock block) {
    return _nestedScrollableRepaintListenableForBlocks(
      block.items.expand((item) => item.children),
    );
  }

  Listenable? _nestedScrollableRepaintListenableForBlocks(
    Iterable<BlockNode> blocks,
  ) {
    final listenables = <Listenable>{};

    void collect(BlockNode block) {
      switch (block.kind) {
        case MarkdownBlockKind.codeBlock:
          listenables.add(
            keysRegistry.codeBlockScrollControllers
                .putIfAbsent(block.id, ScrollController.new),
          );
          return;
        case MarkdownBlockKind.table:
          listenables.add(
            keysRegistry.tableScrollControllers
                .putIfAbsent(block.id, ScrollController.new),
          );
          return;
        case MarkdownBlockKind.quote:
          for (final child in (block as QuoteBlock).children) {
            collect(child);
          }
          return;
        case MarkdownBlockKind.details:
          final detailsBlock = block as DetailsBlock;
          for (final child in detailsBlock.children) {
            collect(child);
          }
          return;
        case MarkdownBlockKind.orderedList:
        case MarkdownBlockKind.unorderedList:
          final listBlock = block as ListBlock;
          for (final item in listBlock.items) {
            for (final child in item.children) {
              collect(child);
            }
          }
          return;
        case MarkdownBlockKind.footnoteList:
          collect(
            MarkdownDescriptorExtractor.footnoteListAsOrderedList(
              block as FootnoteListBlock,
            ),
          );
          return;
        case MarkdownBlockKind.heading:
        case MarkdownBlockKind.paragraph:
        case MarkdownBlockKind.definitionList:
        case MarkdownBlockKind.image:
        case MarkdownBlockKind.thematicBreak:
          return;
      }
    }

    for (final block in blocks) {
      collect(block);
    }

    if (listenables.isEmpty) {
      return null;
    }
    if (listenables.length == 1) {
      return listenables.first;
    }
    return Listenable.merge(listenables.toList(growable: false));
  }

  Widget _buildTable(
    BuildContext context,
    TableBlock block, {
    TextStyle? textStyleContext,
    ScrollController? scrollController,
    GlobalKey? viewportKey,
    List<int> path = const <int>[],
  }) {
    final resolvedViewportKey = viewportKey ??
        keysRegistry.tableViewportKeys.putIfAbsent(
          block.id,
          () => GlobalKey(debugLabel: 'table-viewport-${block.id}'),
        );
    return MarkdownTableBlockView(
      theme: theme,
      block: block,
      layoutPlan: tableLayoutPlanCache.planFor(block),
      textWidgetBuilder: (
        context,
        style,
        inlines,
        textAlign, {
        required int rowIndex,
        required int columnIndex,
        bool alignInlineMathToBaseline = true,
        TextStyle? inlineCodeStyle,
        TextStyle? linkStyle,
      }) {
        final runs = inlineBuilder.buildPretextRuns(
          style,
          inlines,
          alignInlineMathToBaseline: alignInlineMathToBaseline,
          inlineCodeStyle: inlineCodeStyle,
          linkStyle: linkStyle,
        );
        return MarkdownSelectableLeaf(
          path: PathInBlock(<int>[...path, rowIndex, columnIndex]),
          geometry: MarkdownTextLeafGeometry(
            runs: runs,
            fallbackStyle: style,
            textAlign: textAlign,
            direct: true,
            viewportKey: resolvedViewportKey,
          ),
          child: MarkdownPretextTextBlock.rich(
            runs: runs,
            fallbackStyle: style,
            textAlign: textAlign,
            intrinsicWidthSafe: true,
          ),
        );
      },
      bodyStyle: _styleForContext(theme.bodyStyle, textStyleContext),
      tableHeaderStyle: _styleForContext(
        theme.tableHeaderStyle,
        textStyleContext,
      ),
      inlineCodeStyle: _styleForContext(
        theme.inlineCodeStyle,
        textStyleContext,
      ),
      linkStyle: _linkStyleForContext(textStyleContext),
      viewportKey: resolvedViewportKey,
      scrollController: scrollController ??
          keysRegistry.tableScrollControllers
              .putIfAbsent(block.id, ScrollController.new),
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
    PathInBlock? leafPath,
  }) {
    final pretext = descriptor.pretext;
    if (pretext == null) {
      return Text.rich(
        descriptor.span,
        style: pretext?.fallbackStyle,
      );
    }
    if (leafPath != null) {
      return _textLeaf(
        leafPath,
        MarkdownTextLeafGeometry(
          runs: pretext.runs,
          fallbackStyle: pretext.fallbackStyle,
          textAlign: pretext.textAlign,
        ),
      );
    }
    return MarkdownPretextTextBlock.rich(
      runs: pretext.runs,
      fallbackStyle: pretext.fallbackStyle,
      textAlign: pretext.textAlign,
      intrinsicWidthSafe: intrinsicWidthSafe,
      preferDirectRichText:
          markdownPretextCanUseDirectRichTextGeometry(pretext.runs),
    );
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
    final geometry = MarkdownTextLeafGeometry(
      runs: pretext.runs,
      fallbackStyle: pretext.fallbackStyle,
      textAlign: pretext.textAlign,
    );
    return _buildTextLeafSpec(
      child: _textLeaf(_topLevelLeafPath, geometry),
      plainText: descriptor.plainText,
      geometry: geometry,
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
    final highlightSignature = block is CodeBlock
        ? ':${codeHighlightCache.cacheSignatureFor(block.id)}'
        : '';
    if (selectionRange == null ||
        blockIndex < selectionRange.start.blockIndex ||
        blockIndex > selectionRange.end.blockIndex) {
      return 'text:none$highlightSignature';
    }
    final start = blockIndex == selectionRange.start.blockIndex
        ? selectionRange.start.textOffset
        : 0;
    final end = blockIndex == selectionRange.end.blockIndex
        ? selectionRange.end.textOffset
        : plainTextSerializer.serializeBlockText(block).length;
    return 'text:$start:$end$highlightSignature';
  }

  bool _canCacheBlockRow(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        return !_inlinesContainLinks((block as HeadingBlock).inlines);
      case MarkdownBlockKind.paragraph:
        return !_inlinesContainLinks((block as ParagraphBlock).inlines);
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.thematicBreak:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.footnoteList:
      case MarkdownBlockKind.details:
        return true;
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return true;
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
    required this.themeSignature,
    required this.selectionSignature,
    required this.widget,
  });

  final BlockNode block;
  final int blockIndex;
  final int themeSignature;
  final String selectionSignature;
  final Widget widget;
}
