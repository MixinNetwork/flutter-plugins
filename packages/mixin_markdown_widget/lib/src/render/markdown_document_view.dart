import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';
import '../selection/selection_controller.dart';
import '../widgets/markdown_theme.dart';
import '../widgets/markdown_types.dart';
import 'markdown_block_widgets.dart';
import 'code_syntax_highlighter.dart';
import 'selectable_block.dart';
import 'selectable_table_block.dart';

class MarkdownDocumentView extends StatefulWidget {
  const MarkdownDocumentView({
    super.key,
    required this.document,
    required this.theme,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.selectable = true,
    this.selectionController,
    this.onTapLink,
    this.onCopyPlainText,
    this.enableCopyFullDocumentShortcut = true,
    this.showCopyAllInContextMenu = true,
    this.imageBuilder,
  });

  final MarkdownDocument document;
  final MarkdownThemeData theme;
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final bool selectable;
  final MarkdownSelectionController? selectionController;
  final MarkdownTapLinkCallback? onTapLink;
  final VoidCallback? onCopyPlainText;
  final bool enableCopyFullDocumentShortcut;
  final bool showCopyAllInContextMenu;
  final MarkdownImageBuilder? imageBuilder;

  @override
  State<MarkdownDocumentView> createState() => _MarkdownDocumentViewState();
}

class _CopyFullDocumentPlainTextIntent extends Intent {
  const _CopyFullDocumentPlainTextIntent();
}

class _CopySelectionPlainTextIntent extends Intent {
  const _CopySelectionPlainTextIntent();
}

class _SelectAllMarkdownIntent extends Intent {
  const _SelectAllMarkdownIntent();
}

class _ClearMarkdownSelectionIntent extends Intent {
  const _ClearMarkdownSelectionIntent();
}

enum _SelectionMenuAction {
  copySelection,
  selectAll,
  copyAll,
  clearSelection,
}

class _MarkdownDocumentViewState extends State<MarkdownDocumentView> {
  static const double _codeToolbarHeight = 36;

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  final ScrollController _fallbackScrollController = ScrollController();
  final FocusNode _selectionFocusNode =
      FocusNode(debugLabel: 'mixin_markdown_widget.selection');
  final MarkdownPlainTextSerializer _plainTextSerializer =
      const MarkdownPlainTextSerializer();
  final MarkdownCodeSyntaxHighlighter _codeSyntaxHighlighter =
      const MarkdownCodeSyntaxHighlighter();
  final Map<String, GlobalKey<SelectableMarkdownBlockState>> _blockKeys =
      <String, GlobalKey<SelectableMarkdownBlockState>>{};
  final Map<String, List<GlobalKey>> _listItemKeysByBlock =
      <String, List<GlobalKey>>{};
  final Map<String, List<GlobalKey>> _listItemContentKeysByBlock =
      <String, List<GlobalKey>>{};
  final Map<String, GlobalKey<SelectableMarkdownTableBlockState>>
      _tableBlockKeys =
      <String, GlobalKey<SelectableMarkdownTableBlockState>>{};

  Duration? _lastPrimaryDownTimestamp;
  Offset? _lastPrimaryDownPosition;
  int _consecutiveTapCount = 0;
  DocumentPosition? _dragBasePosition;
  bool _isDraggingSelection = false;

  ScrollController get _effectiveScrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void didUpdateWidget(covariant MarkdownDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final validIds = widget.document.blocks.map((block) => block.id).toSet();
    _blockKeys.removeWhere((key, _) => !validIds.contains(key));
    _listItemKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    _listItemContentKeysByBlock.removeWhere(
      (key, _) => !validIds.contains(key),
    );
    _tableBlockKeys.removeWhere((key, _) => !validIds.contains(key));
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _fallbackScrollController.dispose();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final selectionRange = widget.selectionController?.normalizedRange;
    final scrollController = _effectiveScrollController;
    final scrollable = Scrollbar(
      controller: scrollController,
      child: ListView.builder(
        controller: scrollController,
        primary: false,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.theme.padding,
        itemCount: widget.document.blocks.length,
        itemBuilder: (context, index) {
          final block = widget.document.blocks[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == widget.document.blocks.length - 1
                  ? 0
                  : widget.theme.blockSpacing,
            ),
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: widget.theme.maxContentWidth),
                child: _buildBlockView(
                  block: block,
                  blockIndex: index,
                  selectionRange: selectionRange,
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!widget.selectable) {
      return scrollable;
    }

    if (widget.selectionController == null) {
      return _buildNativeSelectionContent(scrollable);
    }

    return _buildCustomSelectionContent(scrollable);
  }

  Widget _buildNativeSelectionContent(Widget scrollable) {
    Widget selectionContent = SelectionArea(
      focusNode: _selectionFocusNode,
      contextMenuBuilder:
          widget.showCopyAllInContextMenu && widget.onCopyPlainText != null
              ? _buildNativeContextMenu
              : null,
      child: scrollable,
    );

    if (widget.enableCopyFullDocumentShortcut &&
        widget.onCopyPlainText != null) {
      selectionContent = Actions(
        actions: <Type, Action<Intent>>{
          _CopyFullDocumentPlainTextIntent:
              CallbackAction<_CopyFullDocumentPlainTextIntent>(
            onInvoke: (intent) {
              widget.onCopyPlainText!.call();
              return null;
            },
          ),
        },
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(
              LogicalKeyboardKey.keyC,
              control: true,
              shift: true,
            ): _CopyFullDocumentPlainTextIntent(),
            SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
              shift: true,
            ): _CopyFullDocumentPlainTextIntent(),
          },
          child: selectionContent,
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_selectionFocusNode.hasFocus) {
          _selectionFocusNode.requestFocus();
        }
      },
      child: selectionContent,
    );
  }

  Widget _buildCustomSelectionContent(Widget scrollable) {
    final selectionController = widget.selectionController!;
    Widget content = Focus(
      focusNode: _selectionFocusNode,
      canRequestFocus: true,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: scrollable,
      ),
    );

    content = Actions(
      actions: <Type, Action<Intent>>{
        _CopySelectionPlainTextIntent:
            CallbackAction<_CopySelectionPlainTextIntent>(
          onInvoke: (intent) {
            if (selectionController.hasSelection) {
              selectionController.copySelectionToClipboard();
            }
            return null;
          },
        ),
        _SelectAllMarkdownIntent: CallbackAction<_SelectAllMarkdownIntent>(
          onInvoke: (intent) {
            selectionController.selectAll(widget.document);
            return null;
          },
        ),
        _ClearMarkdownSelectionIntent:
            CallbackAction<_ClearMarkdownSelectionIntent>(
          onInvoke: (intent) {
            selectionController.clear();
            return null;
          },
        ),
        _CopyFullDocumentPlainTextIntent:
            CallbackAction<_CopyFullDocumentPlainTextIntent>(
          onInvoke: (intent) {
            widget.onCopyPlainText?.call();
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
          ): _CopySelectionPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyC,
            meta: true,
          ): _CopySelectionPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyA,
            control: true,
          ): _SelectAllMarkdownIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyA,
            meta: true,
          ): _SelectAllMarkdownIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
            shift: true,
          ): _CopyFullDocumentPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.keyC,
            meta: true,
            shift: true,
          ): _CopyFullDocumentPlainTextIntent(),
          SingleActivator(
            LogicalKeyboardKey.escape,
          ): _ClearMarkdownSelectionIntent(),
        },
        child: content,
      ),
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_selectionFocusNode.hasFocus) {
          _selectionFocusNode.requestFocus();
        }
      },
      child: content,
    );
  }

  Widget _buildNativeContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final buttonItems = List<ContextMenuButtonItem>.of(
      selectableRegionState.contextMenuButtonItems,
    )..add(
        ContextMenuButtonItem(
          label: 'Copy all',
          onPressed: () {
            widget.onCopyPlainText?.call();
            selectableRegionState.hideToolbar();
          },
        ),
      );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  Future<void> _showCustomContextMenu(Offset globalPosition) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final selectionController = widget.selectionController;
    if (selectionController == null) {
      return;
    }
    final action = await showMenu<_SelectionMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: <PopupMenuEntry<_SelectionMenuAction>>[
        PopupMenuItem<_SelectionMenuAction>(
          value: _SelectionMenuAction.copySelection,
          enabled: selectionController.hasSelection,
          child: const Text('Copy'),
        ),
        const PopupMenuItem<_SelectionMenuAction>(
          value: _SelectionMenuAction.selectAll,
          child: Text('Select all'),
        ),
        PopupMenuItem<_SelectionMenuAction>(
          value: _SelectionMenuAction.copyAll,
          enabled: widget.onCopyPlainText != null,
          child: const Text('Copy all'),
        ),
        PopupMenuItem<_SelectionMenuAction>(
          value: _SelectionMenuAction.clearSelection,
          enabled: selectionController.hasSelection,
          child: const Text('Clear selection'),
        ),
      ],
    );

    switch (action) {
      case _SelectionMenuAction.copySelection:
        await selectionController.copySelectionToClipboard();
        break;
      case _SelectionMenuAction.selectAll:
        selectionController.selectAll(widget.document);
        break;
      case _SelectionMenuAction.copyAll:
        widget.onCopyPlainText?.call();
        break;
      case _SelectionMenuAction.clearSelection:
        selectionController.clear();
        break;
      case null:
        break;
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.selectionController == null || !widget.selectable) {
      return;
    }
    if (!_selectionFocusNode.hasFocus) {
      _selectionFocusNode.requestFocus();
    }

    if (_tableBlockStateContaining(event.position) != null) {
      return;
    }

    if ((event.buttons & kSecondaryMouseButton) != 0) {
      final selectionController = widget.selectionController!;
      if (!selectionController.hasSelection) {
        final position = _hitTestPosition(event.position, clamp: true);
        if (position != null) {
          _selectBlockAt(position.blockIndex);
        }
      }
      _showCustomContextMenu(event.position);
      return;
    }

    if ((event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }

    final position = _hitTestPosition(event.position, clamp: true);
    if (position == null) {
      widget.selectionController!.clear();
      return;
    }

    _updateTapCount(event);
    if (_consecutiveTapCount >= 3) {
      _selectBlockAt(position.blockIndex);
      _isDraggingSelection = false;
      _dragBasePosition = null;
      return;
    }
    if (_consecutiveTapCount == 2) {
      _selectWordAt(position);
      _isDraggingSelection = false;
      _dragBasePosition = null;
      return;
    }

    _dragBasePosition = position;
    _isDraggingSelection = true;
    widget.selectionController!.setSelection(
      DocumentSelection(base: position, extent: position),
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDraggingSelection || widget.selectionController == null) {
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0 ||
        _dragBasePosition == null) {
      return;
    }
    final position = _hitTestPosition(event.position, clamp: true);
    if (position == null) {
      return;
    }
    widget.selectionController!.setSelection(
      DocumentSelection(base: _dragBasePosition!, extent: position),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isDraggingSelection || widget.selectionController == null) {
      return;
    }
    _isDraggingSelection = false;
    final selection = widget.selectionController!.selection;
    if (selection != null && selection.base == selection.extent) {
      widget.selectionController!.clear();
    }
    _dragBasePosition = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _isDraggingSelection = false;
    _dragBasePosition = null;
  }

  void _updateTapCount(PointerDownEvent event) {
    if (_lastPrimaryDownTimestamp != null &&
        event.timeStamp - _lastPrimaryDownTimestamp! <= kDoubleTapTimeout &&
        _lastPrimaryDownPosition != null &&
        (event.position - _lastPrimaryDownPosition!).distance <=
            kDoubleTapSlop) {
      _consecutiveTapCount += 1;
    } else {
      _consecutiveTapCount = 1;
    }
    _lastPrimaryDownTimestamp = event.timeStamp;
    _lastPrimaryDownPosition = event.position;
  }

  void _selectWordAt(DocumentPosition position) {
    final selectionController = widget.selectionController;
    if (selectionController == null) {
      return;
    }
    final blockState = _blockStateForIndex(position.blockIndex);
    if (blockState == null) {
      selectionController.setSelection(
        DocumentSelection(base: position, extent: position),
      );
      return;
    }
    selectionController.setSelection(blockState.selectWord(position));
  }

  void _selectBlockAt(int blockIndex) {
    final selectionController = widget.selectionController;
    if (selectionController == null) {
      return;
    }
    final blockState = _blockStateForIndex(blockIndex);
    if (blockState == null) {
      return;
    }
    selectionController.setSelection(blockState.selectWholeBlock());
  }

  DocumentPosition? _hitTestPosition(
    Offset globalPosition, {
    required bool clamp,
  }) {
    for (final block in widget.document.blocks) {
      final blockState = _blockKeys[block.id]?.currentState;
      final hit = blockState?.hitTestGlobal(globalPosition);
      if (hit != null) {
        return hit;
      }
    }
    if (!clamp) {
      return null;
    }

    SelectableMarkdownBlockState? nearestState;
    double bestDistance = double.infinity;
    for (final block in widget.document.blocks) {
      final blockState = _blockKeys[block.id]?.currentState;
      final rect = blockState?.globalRect;
      if (blockState == null || rect == null) {
        continue;
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
        nearestState = blockState;
      }
    }
    return nearestState?.boundaryPositionForGlobal(globalPosition);
  }

  SelectableMarkdownBlockState? _blockStateForIndex(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= widget.document.blocks.length) {
      return null;
    }
    final block = widget.document.blocks[blockIndex];
    return _blockKeys[block.id]?.currentState;
  }

  SelectableMarkdownTableBlockState? _tableBlockStateContaining(
    Offset globalPosition,
  ) {
    for (final block in widget.document.blocks) {
      final state = _tableBlockKeys[block.id]?.currentState;
      if (state != null && state.containsGlobal(globalPosition)) {
        return state;
      }
    }
    return null;
  }

  Widget _buildBlockView({
    required BlockNode block,
    required int blockIndex,
    required DocumentRange? selectionRange,
  }) {
    final selectionController = widget.selectionController;
    if (selectionController != null && block is TableBlock) {
      final key = _tableBlockKeys.putIfAbsent(
        block.id,
        () => GlobalKey<SelectableMarkdownTableBlockState>(
          debugLabel: 'table-${block.id}',
        ),
      );
      return SelectableMarkdownTableBlock(
        key: key,
        blockIndex: blockIndex,
        block: block,
        theme: widget.theme,
        selectionColor: widget.theme.selectionColor,
        selectionController: selectionController,
        textSpanBuilder: _buildTextSpan,
        onRequestContextMenu: _showCustomContextMenu,
      );
    }

    if (selectionController != null &&
        widget.imageBuilder == null &&
        block is ImageBlock) {
      final captionText = _imageCaptionText(block);
      if (captionText.isNotEmpty) {
        final key = _blockKeys.putIfAbsent(
          block.id,
          () => GlobalKey<SelectableMarkdownBlockState>(debugLabel: block.id),
        );
        final captionDescriptor = _buildImageCaptionDescriptor(block);
        return MarkdownImageBlockView(
          image: _buildImageVisual(block),
          caption: SelectableMarkdownBlock(
            key: key,
            blockIndex: blockIndex,
            spec: SelectableBlockSpec(
              child: Text.rich(captionDescriptor.span),
              plainText: captionDescriptor.plainText,
              hitTestBehavior: SelectableBlockHitTestBehavior.text,
              textSpan: captionDescriptor.span,
            ),
            selectionColor: widget.theme.selectionColor,
            selectionRange: selectionRange,
          ),
        );
      }
    }

    final key = _blockKeys.putIfAbsent(
      block.id,
      () => GlobalKey<SelectableMarkdownBlockState>(debugLabel: block.id),
    );
    return SelectableMarkdownBlock(
      key: key,
      blockIndex: blockIndex,
      spec: _buildBlockSpec(block),
      selectionColor: widget.theme.selectionColor,
      selectionRange: selectionRange,
    );
  }

  SelectableBlockSpec _buildBlockSpec(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        final style = widget.theme.headingStyleForLevel(heading.level);
        final span = _buildTextSpan(style, heading.inlines);
        return SelectableBlockSpec(
          child: Text.rich(span),
          plainText: _flattenInlineText(heading.inlines),
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: span,
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        final span = _buildTextSpan(widget.theme.bodyStyle, paragraph.inlines);
        return SelectableBlockSpec(
          child: Text.rich(span),
          plainText: _flattenInlineText(paragraph.inlines),
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: span,
        );
      case MarkdownBlockKind.quote:
        final quoteBlock = block as QuoteBlock;
        if (widget.selectionController != null) {
          final descriptor = _buildQuoteSelectableDescriptor(quoteBlock);
          return SelectableBlockSpec(
            child: MarkdownQuoteBlockView(
              theme: widget.theme,
              child: _buildQuoteContent(quoteBlock),
            ),
            plainText: descriptor.plainText,
            hitTestBehavior: SelectableBlockHitTestBehavior.text,
            textSpan: descriptor.span,
            measurementPadding:
                widget.theme.quotePadding.resolve(Directionality.of(context)),
            highlightBorderRadius: BorderRadius.circular(16),
          );
        }
        return SelectableBlockSpec(
          child: _buildQuote(quoteBlock),
          plainText: _plainTextSerializer.serializeBlockText(quoteBlock),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
          highlightBorderRadius: BorderRadius.circular(16),
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        final listBlock = block as ListBlock;
        if (widget.selectionController != null) {
          final descriptor = _buildListSelectableDescriptor(listBlock);
          final itemRowKeys = _listItemKeysFor(listBlock);
          final itemContentKeys = _listItemContentKeysFor(listBlock);
          return SelectableBlockSpec(
            child: MarkdownListBlockView(
              theme: widget.theme,
              block: listBlock,
              itemBuilder: _buildListItemContent,
              itemRowKeyBuilder: (index) => itemRowKeys[index],
              itemContentKeyBuilder: (index) => itemContentKeys[index],
            ),
            plainText: descriptor.plainText,
            hitTestBehavior: SelectableBlockHitTestBehavior.text,
            textSpan: descriptor.span,
            selectionRectResolver: (context, range) =>
                _resolveListSelectionRects(
              context,
              listBlock,
              range,
            ),
            textOffsetResolver: (context, localPosition) =>
                _resolveListTextOffset(
              context,
              listBlock,
              localPosition,
            ),
          );
        }
        return SelectableBlockSpec(
          child: _buildList(listBlock),
          plainText: _plainTextSerializer.serializeBlockText(listBlock),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        final codeSpan = _buildCodeTextSpan(codeBlock);
        return SelectableBlockSpec(
          child: _buildDecoratedCodeBlock(codeBlock, codeSpan: codeSpan),
          plainText: codeBlock.code,
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: codeSpan,
          measurementPadding: widget.theme.codeBlockPadding
                  .resolve(Directionality.of(context)) +
              const EdgeInsets.only(top: _codeToolbarHeight),
          highlightBorderRadius: widget.theme.codeBlockBorderRadius,
        );
      case MarkdownBlockKind.table:
        return SelectableBlockSpec(
          child: _buildTable(block as TableBlock),
          plainText: _plainTextSerializer.serializeBlockText(block),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
          highlightBorderRadius: BorderRadius.circular(14),
        );
      case MarkdownBlockKind.image:
        return SelectableBlockSpec(
          child: _buildImage(block as ImageBlock),
          plainText: _plainTextSerializer.serializeBlockText(block),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
          highlightBorderRadius: widget.theme.imageBorderRadius,
        );
      case MarkdownBlockKind.thematicBreak:
        return SelectableBlockSpec(
          child: Divider(
            color: widget.theme.dividerColor,
            height: 1,
            thickness: 1,
          ),
          plainText: _plainTextSerializer.serializeBlockText(block),
          hitTestBehavior: SelectableBlockHitTestBehavior.block,
        );
    }
  }

  TextSpan _buildTextSpan(TextStyle style, List<InlineNode> inlines) {
    return TextSpan(style: style, children: _buildInlineSpans(style, inlines));
  }

  Widget _buildTextBlock({
    required TextStyle style,
    required List<InlineNode> inlines,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Text.rich(
      _buildTextSpan(style, inlines),
      textAlign: textAlign,
    );
  }

  Widget _buildQuote(QuoteBlock block) {
    return MarkdownQuoteBlockView(
      theme: widget.theme,
      child: _buildQuoteContent(block),
    );
  }

  Widget _buildQuoteContent(QuoteBlock block) {
    return DefaultTextStyle.merge(
      style: widget.theme.quoteStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildNestedBlocks(block.children),
      ),
    );
  }

  List<Widget> _buildNestedBlocks(List<BlockNode> blocks) {
    return <Widget>[
      for (var index = 0; index < blocks.length; index++)
        Padding(
          padding: EdgeInsets.only(
            bottom: index == blocks.length - 1
                ? 0
                : widget.theme.blockSpacing * 0.65,
          ),
          child: _buildNestedBlockContent(blocks[index]),
        ),
    ];
  }

  Widget _buildNestedBlockContent(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        return Text.rich(
          _buildTextSpan(
            widget.theme.headingStyleForLevel(heading.level),
            heading.inlines,
          ),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        return Text.rich(
            _buildTextSpan(widget.theme.bodyStyle, paragraph.inlines));
      case MarkdownBlockKind.quote:
        return _buildQuote(block as QuoteBlock);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _buildList(block as ListBlock);
      case MarkdownBlockKind.codeBlock:
        return _buildCodeBlock(block as CodeBlock);
      case MarkdownBlockKind.table:
        return _buildTable(block as TableBlock);
      case MarkdownBlockKind.image:
        return _buildImage(block as ImageBlock);
      case MarkdownBlockKind.thematicBreak:
        return Divider(
          color: widget.theme.dividerColor,
          height: 1,
          thickness: 1,
        );
    }
  }

  Widget _buildList(ListBlock block) {
    return MarkdownListBlockView(
      theme: widget.theme,
      block: block,
      itemBuilder: _buildListItemContent,
    );
  }

  Widget _buildListItemContent(ListItemNode item) {
    if (item.children.length == 1 && item.children.first is ParagraphBlock) {
      return _buildTextBlock(
        style: widget.theme.bodyStyle,
        inlines: (item.children.first as ParagraphBlock).inlines,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildNestedBlocks(item.children),
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
      theme: widget.theme,
      codeSpan: codeSpan,
      toolbarHeight: _codeToolbarHeight,
      language: language,
      onCopyCode: () {
        Clipboard.setData(ClipboardData(text: block.code));
      },
    );
  }

  InlineSpan _buildCodeTextSpan(CodeBlock block) {
    return _codeSyntaxHighlighter.buildTextSpan(
      source: block.code,
      baseStyle: widget.theme.codeBlockStyle,
      theme: widget.theme,
      language: block.language,
    );
  }

  Widget _buildTable(TableBlock block) {
    return MarkdownTableBlockView(
      theme: widget.theme,
      block: block,
      textSpanBuilder: _buildTextSpan,
    );
  }

  Widget _buildImage(ImageBlock block) {
    if (widget.imageBuilder != null) {
      return widget.imageBuilder!(context, block, widget.theme);
    }
    final caption = _imageCaptionText(block);
    return MarkdownImageBlockView(
      image: _buildImageVisual(block),
      caption: caption.isNotEmpty
          ? Text(
              caption,
              style: _imageCaptionStyle,
            )
          : null,
    );
  }

  Widget _buildImageVisual(ImageBlock block) {
    final uri = Uri.tryParse(block.url);
    final isNetwork =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final image = isNetwork
        ? Image.network(
            block.url,
            fit: BoxFit.cover,
            errorBuilder: _imageErrorBuilder,
          )
        : Image.asset(
            block.url,
            fit: BoxFit.cover,
            errorBuilder: _imageErrorBuilder,
          );
    return ClipRRect(
      borderRadius: widget.theme.imageBorderRadius,
      child: image,
    );
  }

  TextStyle get _imageCaptionStyle {
    return widget.theme.bodyStyle.copyWith(
      fontSize: 13,
      color: widget.theme.bodyStyle.color?.withOpacity(0.72),
    );
  }

  _SelectableTextDescriptor _buildListSelectableDescriptor(
    ListBlock block, {
    int indentLevel = 0,
  }) {
    final itemDescriptors = _buildIndexedListSelectionDescriptors(
      block,
      indentLevel: indentLevel,
    ).map((entry) => entry.descriptor).toList(growable: false);
    return _joinSelectableTextDescriptors(
      itemDescriptors,
      separator: '\n',
      separatorStyle: widget.theme.bodyStyle,
    );
  }

  List<GlobalKey> _listItemKeysFor(ListBlock block) {
    final keys =
        _listItemKeysByBlock.putIfAbsent(block.id, () => <GlobalKey>[]);
    while (keys.length < block.items.length) {
      keys.add(
        GlobalKey(debugLabel: 'list-${block.id}-${keys.length}'),
      );
    }
    if (keys.length > block.items.length) {
      keys.removeRange(block.items.length, keys.length);
    }
    return keys;
  }

  List<GlobalKey> _listItemContentKeysFor(ListBlock block) {
    final keys = _listItemContentKeysByBlock.putIfAbsent(
      block.id,
      () => <GlobalKey>[],
    );
    while (keys.length < block.items.length) {
      keys.add(
        GlobalKey(debugLabel: 'list-content-${block.id}-${keys.length}'),
      );
    }
    if (keys.length > block.items.length) {
      keys.removeRange(block.items.length, keys.length);
    }
    return keys;
  }

  int? _resolveListTextOffset(
    BuildContext context,
    ListBlock block,
    Offset localPosition,
  ) {
    final blockRenderObject = context.findRenderObject();
    if (blockRenderObject is! RenderBox || !blockRenderObject.hasSize) {
      return null;
    }

    final globalPosition = blockRenderObject.localToGlobal(localPosition);
    final indexedDescriptors = _buildIndexedListSelectionDescriptors(block);
    if (indexedDescriptors.isEmpty) {
      return null;
    }

    final contentKeys = _listItemContentKeysFor(block);
    final rowKeys = _listItemKeysFor(block);
    final textDirection = Directionality.of(context);

    for (final entry in indexedDescriptors) {
      final contentContext = contentKeys[entry.itemIndex].currentContext;
      final contentRenderObject = contentContext?.findRenderObject();
      if (contentRenderObject is RenderBox && contentRenderObject.hasSize) {
        final rect = contentRenderObject.localToGlobal(Offset.zero) &
            contentRenderObject.size;
        if (rect.contains(globalPosition)) {
          final localContentPosition =
              contentRenderObject.globalToLocal(globalPosition);
          return entry.startOffset +
              entry.prefixLength +
              _resolveTextOffsetInBox(
                entry.contentDescriptor.span,
                entry.contentDescriptor.plainText.length,
                localContentPosition,
                contentRenderObject.size,
                textDirection,
              );
        }
      }

      final rowContext = rowKeys[entry.itemIndex].currentContext;
      final rowRenderObject = rowContext?.findRenderObject();
      if (rowRenderObject is RenderBox && rowRenderObject.hasSize) {
        final rect =
            rowRenderObject.localToGlobal(Offset.zero) & rowRenderObject.size;
        if (rect.contains(globalPosition)) {
          final localRowPosition =
              rowRenderObject.globalToLocal(globalPosition);
          final markerWidth = math.min(28.0, rowRenderObject.size.width);
          if (localRowPosition.dx <= markerWidth) {
            return entry.startOffset;
          }
          return entry.startOffset + entry.prefixLength;
        }
      }
    }

    return null;
  }

  int _resolveTextOffsetInBox(
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

  List<Rect> _resolveListSelectionRects(
    BuildContext context,
    ListBlock block,
    DocumentRange range,
  ) {
    final blockRenderObject = context.findRenderObject();
    if (blockRenderObject is! RenderBox || !blockRenderObject.hasSize) {
      return const <Rect>[];
    }

    final indexedDescriptors = _buildIndexedListSelectionDescriptors(block);
    if (indexedDescriptors.isEmpty) {
      return const <Rect>[];
    }

    final rects = <Rect>[];
    final textDirection = Directionality.of(context);
    final rowKeys = _listItemKeysFor(block);
    final contentKeys = _listItemContentKeysFor(block);

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

      final rowContext = rowKeys[entry.itemIndex].currentContext;
      final rowRenderObject = rowContext?.findRenderObject();
      if (prefixSelectionStart < prefixSelectionEnd &&
          rowRenderObject is RenderBox &&
          rowRenderObject.hasSize) {
        final rowOrigin = blockRenderObject.globalToLocal(
          rowRenderObject.localToGlobal(Offset.zero),
        );
        rects.add(
          Rect.fromLTWH(
            rowOrigin.dx,
            rowOrigin.dy,
            math.min(28.0, rowRenderObject.size.width),
            rowRenderObject.size.height,
          ).inflate(1.5),
        );
      }

      if (contentSelectionStart >= contentSelectionEnd) {
        continue;
      }

      final contentContext = contentKeys[entry.itemIndex].currentContext;
      final contentRenderObject = contentContext?.findRenderObject();
      if (contentRenderObject is! RenderBox || !contentRenderObject.hasSize) {
        continue;
      }

      final itemOrigin = blockRenderObject.globalToLocal(
        contentRenderObject.localToGlobal(Offset.zero),
      );
      final textPainter = TextPainter(
        text: entry.contentDescriptor.span,
        textDirection: textDirection,
        maxLines: null,
      )..layout(maxWidth: contentRenderObject.size.width);

      final itemBoxes = textPainter.getBoxesForSelection(
        TextSelection(
          baseOffset: contentSelectionStart - itemStart - entry.prefixLength,
          extentOffset: contentSelectionEnd - itemStart - entry.prefixLength,
        ),
      );
      for (final box in itemBoxes) {
        rects.add(
          Rect.fromLTRB(
            box.left + itemOrigin.dx,
            box.top + itemOrigin.dy,
            box.right + itemOrigin.dx,
            box.bottom + itemOrigin.dy,
          ).inflate(1.5),
        );
      }
    }

    return rects;
  }

  List<_IndexedListSelectionDescriptor> _buildIndexedListSelectionDescriptors(
    ListBlock block, {
    int indentLevel = 0,
  }) {
    final entries = <_IndexedListSelectionDescriptor>[];
    var offset = 0;
    for (var index = 0; index < block.items.length; index++) {
      if (entries.isNotEmpty) {
        offset += 1;
      }
      final entry = _buildIndexedListSelectionDescriptor(
        block,
        index,
        startOffset: offset,
        indentLevel: indentLevel,
      );
      if (entry == null) {
        if (entries.isNotEmpty) {
          offset -= 1;
        }
        continue;
      }
      entries.add(entry);
      offset += entry.descriptor.plainText.length;
    }
    return entries;
  }

  _IndexedListSelectionDescriptor? _buildIndexedListSelectionDescriptor(
    ListBlock block,
    int index, {
    required int startOffset,
    int indentLevel = 0,
  }) {
    final marker = block.ordered ? '${block.startIndex + index}.' : '•';
    final prefix = '${'  ' * indentLevel}$marker ';
    final contentDescriptor = _buildListItemSelectableDescriptor(
      block.items[index],
      indentLevel: indentLevel + 1,
    );
    if (contentDescriptor.isEmpty) {
      return null;
    }
    final descriptor = _prefixSelectableTextDescriptor(
      contentDescriptor,
      firstPrefix: prefix,
      continuationPrefix: '${'  ' * indentLevel}${' ' * (marker.length + 1)}',
      style: widget.theme.bodyStyle,
    );
    return _IndexedListSelectionDescriptor(
      itemIndex: index,
      startOffset: startOffset,
      prefixLength: prefix.length,
      descriptor: descriptor,
      contentDescriptor: contentDescriptor,
    );
  }

  _SelectableTextDescriptor _buildListItemSelectableDescriptor(
    ListItemNode item, {
    required int indentLevel,
  }) {
    final childDescriptors = <_SelectableTextDescriptor>[];
    for (final child in item.children) {
      final descriptor = _buildSelectableDescriptorForBlock(
        child,
        indentLevel: indentLevel,
      );
      if (!descriptor.isEmpty) {
        childDescriptors.add(descriptor);
      }
    }
    return _joinSelectableTextDescriptors(
      childDescriptors,
      separator: '\n',
      separatorStyle: widget.theme.bodyStyle,
    );
  }

  _SelectableTextDescriptor _buildQuoteSelectableDescriptor(QuoteBlock block) {
    final childDescriptors = <_SelectableTextDescriptor>[];
    for (final child in block.children) {
      final descriptor = _buildSelectableDescriptorForBlock(child);
      if (!descriptor.isEmpty) {
        childDescriptors.add(descriptor);
      }
    }
    final joined = _joinSelectableTextDescriptors(
      childDescriptors,
      separator: '\n\n',
      separatorStyle: widget.theme.quoteStyle,
    );
    return joined;
  }

  _SelectableTextDescriptor _buildImageCaptionDescriptor(ImageBlock block) {
    final caption = _imageCaptionText(block);
    return _plainTextDescriptor(caption, _imageCaptionStyle);
  }

  _SelectableTextDescriptor _buildSelectableDescriptorForBlock(
    BlockNode block, {
    int indentLevel = 0,
  }) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        return _descriptorFromSpan(
          _buildTextSpan(
            widget.theme.headingStyleForLevel(heading.level),
            heading.inlines,
          ),
          _flattenInlineText(heading.inlines),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        return _descriptorFromSpan(
          _buildTextSpan(widget.theme.bodyStyle, paragraph.inlines),
          _flattenInlineText(paragraph.inlines),
        );
      case MarkdownBlockKind.quote:
        return _buildQuoteSelectableDescriptor(block as QuoteBlock);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _buildListSelectableDescriptor(
          block as ListBlock,
          indentLevel: indentLevel,
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        return _plainTextDescriptor(
            codeBlock.code, widget.theme.codeBlockStyle);
      case MarkdownBlockKind.table:
        return _plainTextDescriptor(
          _plainTextSerializer.serializeBlockText(block),
          widget.theme.bodyStyle,
        );
      case MarkdownBlockKind.image:
        final imageBlock = block as ImageBlock;
        final caption = _imageCaptionText(imageBlock);
        if (caption.isEmpty) {
          return _plainTextDescriptor('', widget.theme.bodyStyle);
        }
        return _buildImageCaptionDescriptor(imageBlock);
      case MarkdownBlockKind.thematicBreak:
        return _plainTextDescriptor('---', widget.theme.bodyStyle);
    }
  }

  _SelectableTextDescriptor _descriptorFromSpan(
      TextSpan span, String plainText) {
    return _SelectableTextDescriptor(
      plainText: plainText,
      span: span,
    );
  }

  _SelectableTextDescriptor _plainTextDescriptor(String text, TextStyle style) {
    return _SelectableTextDescriptor(
      plainText: text,
      span: TextSpan(style: style, text: text),
    );
  }

  _SelectableTextDescriptor _joinSelectableTextDescriptors(
    List<_SelectableTextDescriptor> descriptors, {
    required String separator,
    required TextStyle separatorStyle,
  }) {
    final nonEmpty =
        descriptors.where((descriptor) => !descriptor.isEmpty).toList();
    if (nonEmpty.isEmpty) {
      return _plainTextDescriptor('', separatorStyle);
    }
    final buffer = StringBuffer();
    final children = <InlineSpan>[];
    for (var index = 0; index < nonEmpty.length; index++) {
      if (index > 0) {
        buffer.write(separator);
        children.add(TextSpan(style: separatorStyle, text: separator));
      }
      buffer.write(nonEmpty[index].plainText);
      children.add(nonEmpty[index].span);
    }
    return _SelectableTextDescriptor(
      plainText: buffer.toString(),
      span: TextSpan(children: children),
    );
  }

  _SelectableTextDescriptor _prefixSelectableTextDescriptor(
    _SelectableTextDescriptor descriptor, {
    required String firstPrefix,
    required String continuationPrefix,
    required TextStyle style,
  }) {
    if (descriptor.isEmpty) {
      return _plainTextDescriptor('', style);
    }
    if (descriptor.plainText.contains('\n')) {
      final lines = descriptor.plainText.split('\n');
      final buffer = StringBuffer();
      for (var index = 0; index < lines.length; index++) {
        final prefix = index == 0 ? firstPrefix : continuationPrefix;
        if (index > 0) {
          buffer.write('\n');
        }
        if (lines[index].isEmpty) {
          buffer.write(prefix.trimRight());
        } else {
          buffer.write(prefix);
          buffer.write(lines[index]);
        }
      }
      return _plainTextDescriptor(buffer.toString(), style);
    }
    return _SelectableTextDescriptor(
      plainText: '$firstPrefix${descriptor.plainText}',
      span: TextSpan(
        children: <InlineSpan>[
          TextSpan(style: style, text: firstPrefix),
          descriptor.span,
        ],
      ),
    );
  }

  String _imageCaptionText(ImageBlock block) {
    return (block.alt ?? block.title ?? '').trim();
  }

  Widget _imageErrorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      color: widget.theme.codeBlockBackgroundColor,
      child: Text(
        'Unable to load image',
        style: widget.theme.bodyStyle,
      ),
    );
  }

  List<InlineSpan> _buildInlineSpans(
    TextStyle baseStyle,
    List<InlineNode> inlines,
  ) {
    return <InlineSpan>[
      for (final inline in inlines) ..._buildInlineSpan(baseStyle, inline),
    ];
  }

  List<InlineSpan> _buildInlineSpan(TextStyle baseStyle, InlineNode inline) {
    switch (inline.kind) {
      case MarkdownInlineKind.text:
        return <InlineSpan>[TextSpan(text: (inline as TextInline).text)];
      case MarkdownInlineKind.emphasis:
        final emphasis = inline as EmphasisInline;
        return <InlineSpan>[
          TextSpan(
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
            children: _buildInlineSpans(
              baseStyle.copyWith(fontStyle: FontStyle.italic),
              emphasis.children,
            ),
          ),
        ];
      case MarkdownInlineKind.strong:
        final strong = inline as StrongInline;
        return <InlineSpan>[
          TextSpan(
            style: baseStyle.copyWith(fontWeight: FontWeight.w700),
            children: _buildInlineSpans(
              baseStyle.copyWith(fontWeight: FontWeight.w700),
              strong.children,
            ),
          ),
        ];
      case MarkdownInlineKind.strikethrough:
        final strike = inline as StrikethroughInline;
        return <InlineSpan>[
          TextSpan(
            style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
            children: _buildInlineSpans(
              baseStyle.copyWith(decoration: TextDecoration.lineThrough),
              strike.children,
            ),
          ),
        ];
      case MarkdownInlineKind.link:
        final link = inline as LinkInline;
        final label = _flattenInlineText(link.children);
        final recognizer = widget.onTapLink == null
            ? null
            : _registerLink(() {
                widget.onTapLink!(link.destination, link.title, label);
              });
        final linkStyle = baseStyle.merge(widget.theme.linkStyle);
        return <InlineSpan>[
          TextSpan(
            style: linkStyle,
            mouseCursor: widget.onTapLink != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            recognizer: recognizer,
            children: _buildInlineSpans(linkStyle, link.children),
          ),
        ];
      case MarkdownInlineKind.inlineCode:
        final code = inline as InlineCode;
        return <InlineSpan>[
          TextSpan(
            text: code.text,
            style: baseStyle.merge(widget.theme.inlineCodeStyle),
          ),
        ];
      case MarkdownInlineKind.softBreak:
      case MarkdownInlineKind.hardBreak:
        return const <InlineSpan>[TextSpan(text: '\n')];
      case MarkdownInlineKind.image:
        final image = inline as InlineImage;
        final label = image.alt?.trim().isNotEmpty == true
            ? image.alt!.trim()
            : image.url;
        return <InlineSpan>[
          TextSpan(
            text: label,
            style: baseStyle.merge(widget.theme.linkStyle),
          ),
        ];
    }
  }

  TapGestureRecognizer _registerLink(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  String _flattenInlineText(List<InlineNode> inlines) {
    final buffer = StringBuffer();
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.text:
          buffer.write((inline as TextInline).text);
          break;
        case MarkdownInlineKind.emphasis:
          buffer.write(_flattenInlineText((inline as EmphasisInline).children));
          break;
        case MarkdownInlineKind.strong:
          buffer.write(_flattenInlineText((inline as StrongInline).children));
          break;
        case MarkdownInlineKind.strikethrough:
          buffer.write(
            _flattenInlineText((inline as StrikethroughInline).children),
          );
          break;
        case MarkdownInlineKind.link:
          buffer.write(_flattenInlineText((inline as LinkInline).children));
          break;
        case MarkdownInlineKind.inlineCode:
          buffer.write((inline as InlineCode).text);
          break;
        case MarkdownInlineKind.softBreak:
        case MarkdownInlineKind.hardBreak:
          buffer.write('\n');
          break;
        case MarkdownInlineKind.image:
          final image = inline as InlineImage;
          buffer.write(image.alt ?? image.url);
          break;
      }
    }
    return buffer.toString();
  }
}

@immutable
class _SelectableTextDescriptor {
  const _SelectableTextDescriptor({
    required this.plainText,
    required this.span,
  });

  final String plainText;
  final TextSpan span;

  bool get isEmpty => plainText.isEmpty;
}

@immutable
class _IndexedListSelectionDescriptor {
  const _IndexedListSelectionDescriptor({
    required this.itemIndex,
    required this.startOffset,
    required this.prefixLength,
    required this.descriptor,
    required this.contentDescriptor,
  });

  final int itemIndex;
  final int startOffset;
  final int prefixLength;
  final _SelectableTextDescriptor descriptor;
  final _SelectableTextDescriptor contentDescriptor;
}
