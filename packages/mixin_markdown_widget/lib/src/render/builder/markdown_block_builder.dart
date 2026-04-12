import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import '../../clipboard/plain_text_serializer.dart';
import '../../core/document.dart';
import '../../selection/selection_controller.dart';
import '../../widgets/markdown_theme.dart';
import '../../widgets/markdown_types.dart';
import '../code_syntax_highlighter.dart';
import '../markdown_block_widgets.dart';
import '../pretext_text_block.dart';
import '../selectable_block.dart';
import '../selectable_table_block.dart';
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
  final MarkdownTapLinkCallback? onTapLink;
  final void Function(Offset) onRequestContextMenu;

  final Map<String, CachedBlockRow> _cachedBlockRows;

  Widget buildBlockListItem(
    BuildContext context, {
    required BlockNode block,
    required int blockIndex,
    required DocumentRange? selectionRange,
    required TableCellSelection? tableSelection,
  }) {
    final cacheable = _canCacheBlockRow(block);
    final selectionSignature = _selectionSignatureForBlock(
      block: block,
      blockIndex: blockIndex,
      selectionRange: selectionRange,
      tableSelection: tableSelection,
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
        bottom: blockIndex == document.blocks.length - 1
            ? 0
            : theme.blockSpacing,
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
    if (selectionController != null && block is TableBlock) {
      final key = keysRegistry.tableBlockKeys.putIfAbsent(
        block.id,
        () => GlobalKey<SelectableMarkdownTableBlockState>(
            debugLabel: 'table-${block.id}'),
      );
      return SelectableMarkdownTableBlock(
        key: key,
        blockIndex: blockIndex,
        block: block,
        theme: theme,
        selectionColor: theme.selectionColor,
        selectionController: selectionController!,
        textWidgetBuilder: _buildInlineTextWidget,
        onRequestContextMenu: onRequestContextMenu,
        documentSelected: _isBlockCoveredByTextSelection(
          blockIndex,
          selectionRange,
        ),
      );
    }

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
        return MarkdownImageBlockView(
          image: _buildImageVisual(context, block),
          caption: SelectableMarkdownBlock(
            key: key,
            blockIndex: blockIndex,
            spec: SelectableBlockSpec(
              child: Text.rich(captionDescriptor.span),
              plainText: captionDescriptor.plainText,
              hitTestBehavior: SelectableBlockHitTestBehavior.text,
              textSpan: captionDescriptor.span,
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
        if (MarkdownInlineBuilder.inlinesContainMath(heading.inlines)) {
          return SelectableBlockSpec(
            child: _buildTextBlock(
              style: style,
              inlines: heading.inlines,
              textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(
                  heading.inlines),
            ),
            plainText: MarkdownInlineBuilder.flattenInlineText(heading.inlines),
            hitTestBehavior: SelectableBlockHitTestBehavior.block,
          );
        }
        final plainText =
            MarkdownInlineBuilder.flattenInlineText(heading.inlines);
        return _buildPretextTextSpec(
          plainText: plainText,
          runs: inlineBuilder.buildPretextRuns(style, heading.inlines),
          fallbackStyle: style,
          textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(heading.inlines),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        if (MarkdownInlineBuilder.inlinesContainMath(paragraph.inlines)) {
          return SelectableBlockSpec(
            child: _buildTextBlock(
              style: theme.bodyStyle,
              inlines: paragraph.inlines,
              textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(
                  paragraph.inlines),
            ),
            plainText:
                MarkdownInlineBuilder.flattenInlineText(paragraph.inlines),
            hitTestBehavior: SelectableBlockHitTestBehavior.block,
          );
        }
        final plainText =
            MarkdownInlineBuilder.flattenInlineText(paragraph.inlines);
        return _buildPretextTextSpec(
          plainText: plainText,
          runs: inlineBuilder.buildPretextRuns(
              theme.bodyStyle, paragraph.inlines),
          fallbackStyle: theme.bodyStyle,
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
          ),
          plainText: descriptor.plainText,
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
        );
      case MarkdownBlockKind.definitionList:
        final definitionList = block as DefinitionListBlock;
        final definitionDescriptor = descriptorExtractor
            .buildDefinitionListSelectableDescriptor(definitionList);
        return SelectableBlockSpec(
          child: Text.rich(
            definitionDescriptor.span,
            style: theme.bodyStyle,
          ),
          plainText: definitionDescriptor.plainText,
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: definitionDescriptor.span,
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
            ),
          ),
          plainText: footnoteDescriptor.plainText,
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
          highlightBorderRadius: BorderRadius.circular(8),
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        final codeSpan = _buildCodeTextSpan(codeBlock);
        return SelectableBlockSpec(
          child: _buildDecoratedCodeBlock(codeBlock, codeSpan: codeSpan),
          plainText: codeBlock.code,
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: codeSpan,
          measurementPadding: theme.codeBlockPadding
                  .resolve(Directionality.of(context)) +
              const EdgeInsets.only(top: 36.0), // _codeToolbarHeight
          highlightBorderRadius: theme.codeBlockBorderRadius,
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
        );
      case MarkdownBlockKind.table:
        return SelectableBlockSpec(
          child: _buildTable(context, block as TableBlock),
          plainText: plainTextSerializer.serializeBlockText(block),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
          highlightBorderRadius: BorderRadius.circular(14),
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
    required String plainText,
    required List<MarkdownPretextInlineRun> runs,
    required TextStyle fallbackStyle,
    TextAlign textAlign = TextAlign.start,
  }) {
    return SelectableBlockSpec(
      child: MarkdownPretextTextBlock.rich(
        runs: runs,
        fallbackStyle: fallbackStyle,
        textAlign: textAlign,
      ),
      plainText: plainText,
      hitTestBehavior: SelectableBlockHitTestBehavior.text,
      selectionRectResolver: (context, constraints, range) {
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
    );
  }

  Widget _buildNestedBlockContent(BuildContext context, BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        return _buildTextBlock(
          style: theme.headingStyleForLevel(heading.level),
          inlines: heading.inlines,
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
        return _buildCodeBlock(block as CodeBlock);
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
              bottom: index == blocks.length - 1
                  ? 0
                  : theme.blockSpacing * 0.65,
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
    );
  }

  Widget _buildDefinitionList(BuildContext context, DefinitionListBlock block) {
    final descriptor =
        descriptorExtractor.buildDefinitionListSelectableDescriptor(block);
    return Text.rich(
      descriptor.span,
      style: theme.bodyStyle,
    );
  }

  Widget _buildFootnoteList(BuildContext context, FootnoteListBlock block) {
    final orderedFootnotes = MarkdownDescriptorExtractor.footnoteListAsOrderedList(block);
    final itemRowKeys = keysRegistry.listItemKeysFor(orderedFootnotes);
    final itemContentKeys = keysRegistry.listItemContentKeysFor(orderedFootnotes);
    return _buildFootnoteListContainer(
      child: MarkdownListBlockView(
        theme: theme,
        block: orderedFootnotes,
        itemBuilder: (index, item) =>
            _buildListItemContent(context, orderedFootnotes, index, item),
        itemRowKeyBuilder: (index) => itemRowKeys[index],
        itemContentKeyBuilder: (index) => itemContentKeys[index],
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
    if (MarkdownInlineBuilder.inlinesContainMath(inlines)) {
      return Text.rich(
        TextSpan(style: style, children: inlineBuilder.buildInlineSpans(style, inlines)),
        textAlign: textAlign,
      );
    }
    return MarkdownPretextTextBlock.rich(
      runs: inlineBuilder.buildPretextRuns(style, inlines),
      fallbackStyle: style,
      textAlign: textAlign,
    );
  }

  Widget _buildCodeBlock(CodeBlock block) {
    return _buildDecoratedCodeBlock(
      block,
      codeSpan: _buildCodeTextSpan(block),
    );
  }

  Widget _buildDecoratedCodeBlock(
    CodeBlock block, {
    required InlineSpan codeSpan,
  }) {
    final language = block.language?.trim();
    return MarkdownCodeBlockView(
      theme: theme,
      codeSpan: codeSpan,
      toolbarHeight: 36, // _codeToolbarHeight
      language: language,
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

  Widget _buildTable(BuildContext context, TableBlock block) {
    return MarkdownTableBlockView(
      theme: theme,
      block: block,
      textWidgetBuilder: _buildInlineTextWidget,
    );
  }

  Widget _buildInlineTextWidget(
    BuildContext context,
    TextStyle style,
    List<InlineNode> inlines,
    TextAlign textAlign,
  ) {
    if (MarkdownInlineBuilder.inlinesContainMath(inlines)) {
      return Text.rich(
        TextSpan(style: style, children: inlineBuilder.buildInlineSpans(style, inlines)),
        textAlign: textAlign,
      );
    }
    return MarkdownPretextTextBlock.rich(
      runs: inlineBuilder.buildPretextRuns(style, inlines),
      fallbackStyle: style,
      textAlign: textAlign,
      intrinsicWidthSafe: true,
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
    return MarkdownImageBlockView(
      image: _buildImageVisual(context, block),
      caption: caption.isNotEmpty
          ? Text(
              caption,
              style: descriptorExtractor.imageCaptionStyle,
            )
          : null,
    );
  }

  Widget _buildImageVisual(BuildContext context, ImageBlock block) {
    if (imageBuilder != null) {
      return _wrapLinkedImage(
        block,
        imageBuilder!(context, block, theme),
      );
    }
    final uri = Uri.tryParse(block.url);
    final isNetwork =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final localImageProvider = resolveMarkdownLocalImageProvider(block.url);
    final image = isNetwork
        ? Image.network(
            block.url,
            fit: BoxFit.cover,
            errorBuilder: _imageErrorBuilder,
          )
        : localImageProvider != null
            ? Image(
                image: localImageProvider,
                fit: BoxFit.cover,
                errorBuilder: _imageErrorBuilder,
              )
            : Image.asset(
                block.url,
                fit: BoxFit.cover,
                errorBuilder: _imageErrorBuilder,
              );
    return _wrapLinkedImage(
      block,
      ClipRRect(
        borderRadius: theme.imageBorderRadius,
        child: image,
      ),
    );
  }

  Widget _wrapLinkedImage(ImageBlock block, Widget child) {
    final destination = block.linkDestination;
    if (destination == null ||
        destination.isEmpty ||
        onTapLink == null) {
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

  Widget _imageErrorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      color: theme.codeBlockBackgroundColor,
      child: Text(
        'Unable to load image',
        style: theme.bodyStyle,
      ),
    );
  }

  SelectableBlockSpec _buildCustomImageBuilderSpec(
      BuildContext context, ImageBlock block) {
    final caption = MarkdownDescriptorExtractor.imageCaptionText(block);
    return SelectableBlockSpec(
      child: MarkdownImageBlockView(
        image: _buildImageVisual(context, block),
        caption: caption.isEmpty
            ? null
            : Text(
                caption,
                style: descriptorExtractor.imageCaptionStyle,
              ),
      ),
      plainText: plainTextSerializer.serializeBlockText(block),
      hitTestBehavior: SelectableBlockHitTestBehavior.block,
      highlightBorderRadius: theme.imageBorderRadius,
    );
  }

  Color get _quoteSelectionColor {
    final opacity = math.min(
      math.max(theme.selectionColor.opacity * 0.72, 0.14),
      0.2,
    );
    return theme.selectionColor.withOpacity(opacity);
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
    required TableCellSelection? tableSelection,
  }) {
    if (block is TableBlock) {
      if (tableSelection != null && tableSelection.blockIndex == blockIndex) {
        final tableRange = tableSelection.normalizedRange;
        return 'table:${tableRange.start.rowIndex}:${tableRange.start.columnIndex}:${tableRange.end.rowIndex}:${tableRange.end.columnIndex}';
      }
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
