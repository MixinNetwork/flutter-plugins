import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';
import '../selection/selection_controller.dart';
import '../widgets/markdown_theme.dart';
import '../widgets/markdown_types.dart';
import 'markdown_block_widgets.dart';
import 'code_syntax_highlighter.dart';
import 'local_image_provider_stub.dart'
    if (dart.library.io) 'local_image_provider_io.dart';
import 'pretext_text_block.dart';
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
  static const double _autoScrollActivationZone = 56;
  static const double _autoScrollMaxSpeed = 960;
  static const Duration _autoScrollTickInterval = Duration(milliseconds: 16);

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  final Map<String, _CachedBlockRow> _cachedBlockRows =
      <String, _CachedBlockRow>{};
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
  final Map<String, List<List<GlobalKey>>> _listItemChildKeysByBlock =
      <String, List<List<GlobalKey>>>{};
  final Map<String, List<GlobalKey>> _quoteChildKeysByBlock =
      <String, List<GlobalKey>>{};
  final Map<String, GlobalKey<SelectableMarkdownTableBlockState>>
      _tableBlockKeys =
      <String, GlobalKey<SelectableMarkdownTableBlockState>>{};
  final GlobalKey _scrollableKey = GlobalKey(debugLabel: 'markdown-scrollable');

  Duration? _lastPrimaryDownTimestamp;
  Offset? _lastPrimaryDownPosition;
  int _consecutiveTapCount = 0;
  DocumentPosition? _dragBasePosition;
  Offset? _dragStartPointerPosition;
  Offset? _lastDragPointerPosition;
  bool _isDraggingSelection = false;
  bool _clearSelectionOnPointerUp = false;
  Timer? _autoScrollTimer;

  ScrollController get _effectiveScrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void didUpdateWidget(covariant MarkdownDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final validIds = _collectBlockIds(widget.document.blocks);
    _cachedBlockRows.removeWhere((key, _) => !validIds.contains(key));
    _blockKeys.removeWhere((key, _) => !validIds.contains(key));
    _listItemKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    _listItemContentKeysByBlock.removeWhere(
      (key, _) => !validIds.contains(key),
    );
    _listItemChildKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    _quoteChildKeysByBlock.removeWhere((key, _) => !validIds.contains(key));
    _tableBlockKeys.removeWhere((key, _) => !validIds.contains(key));

    if (oldWidget.theme != widget.theme ||
        oldWidget.onTapLink != widget.onTapLink ||
        oldWidget.imageBuilder != widget.imageBuilder ||
        oldWidget.selectable != widget.selectable) {
      _cachedBlockRows.clear();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _stopAutoScroll();
    _fallbackScrollController.dispose();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final selectionRange = widget.selectionController?.normalizedRange;
    final tableSelection = widget.selectionController?.tableCellSelection;
    final scrollController = _effectiveScrollController;
    final scrollable = Scrollbar(
      controller: scrollController,
      child: ListView.builder(
        key: _scrollableKey,
        controller: scrollController,
        primary: false,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.theme.padding,
        itemCount: widget.document.blocks.length,
        itemBuilder: (context, index) {
          final block = widget.document.blocks[index];
          return _buildBlockListItem(
            block: block,
            blockIndex: index,
            selectionRange: selectionRange,
            tableSelection: tableSelection,
          );
        },
      ),
    );
    if (!widget.selectable) {
      return scrollable;
    }

    if (widget.selectionController == null) {
      return scrollable;
    }

    return _buildCustomSelectionContent(scrollable);
  }

  Widget _buildCustomSelectionContent(Widget scrollable) {
    final selectionController = widget.selectionController!;
    Widget content = TapRegion(
      onTapOutside: (_) {
        selectionController.clear();
        _selectionFocusNode.unfocus();
      },
      child: Focus(
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

    final exactPosition = _hitTestPosition(event.position, clamp: false);
    final position =
        exactPosition ?? _hitTestPosition(event.position, clamp: true);
    if (position == null) {
      widget.selectionController!.clear();
      _clearSelectionOnPointerUp = false;
      return;
    }

    _updateTapCount(event);
    if (exactPosition != null && _consecutiveTapCount >= 3) {
      _selectBlockAt(position.blockIndex);
      _isDraggingSelection = false;
      _dragBasePosition = null;
      _dragStartPointerPosition = null;
      _clearSelectionOnPointerUp = false;
      return;
    }
    if (exactPosition != null && _consecutiveTapCount == 2) {
      _selectWordAt(position);
      _isDraggingSelection = false;
      _dragBasePosition = null;
      _dragStartPointerPosition = null;
      _clearSelectionOnPointerUp = false;
      return;
    }

    _dragBasePosition = position;
    _dragStartPointerPosition = event.position;
    _lastDragPointerPosition = event.position;
    _isDraggingSelection = true;
    _clearSelectionOnPointerUp = widget.selectionController!.hasSelection;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDraggingSelection || widget.selectionController == null) {
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0 ||
        _dragBasePosition == null) {
      return;
    }
    final dragStartPointerPosition = _dragStartPointerPosition;
    if (dragStartPointerPosition != null &&
        (event.position - dragStartPointerPosition).distance < kTouchSlop) {
      _lastDragPointerPosition = event.position;
      return;
    }
    _lastDragPointerPosition = event.position;
    _updateDragSelectionAt(event.position);
    _updateAutoScroll();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isDraggingSelection || widget.selectionController == null) {
      return;
    }
    final shouldClearSelection = _clearSelectionOnPointerUp &&
        _dragStartPointerPosition != null &&
        (event.position - _dragStartPointerPosition!).distance < kTouchSlop;
    _isDraggingSelection = false;
    _dragBasePosition = null;
    _dragStartPointerPosition = null;
    _lastDragPointerPosition = null;
    _clearSelectionOnPointerUp = false;
    _stopAutoScroll();
    if (shouldClearSelection) {
      widget.selectionController!.clear();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _isDraggingSelection = false;
    _dragBasePosition = null;
    _dragStartPointerPosition = null;
    _lastDragPointerPosition = null;
    _clearSelectionOnPointerUp = false;
    _stopAutoScroll();
  }

  void _updateDragSelectionAt(Offset globalPosition) {
    if (widget.selectionController == null || _dragBasePosition == null) {
      return;
    }
    final position = _tableBoundaryPositionForDrag(
          globalPosition,
          anchor: _dragBasePosition!,
        ) ??
        _hitTestPosition(globalPosition, clamp: true);
    if (position == null) {
      return;
    }
    widget.selectionController!.setSelection(
      DocumentSelection(base: _dragBasePosition!, extent: position),
    );
  }

  void _updateAutoScroll() {
    if (_autoScrollVelocity() == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??= Timer.periodic(
      _autoScrollTickInterval,
      (_) => _handleAutoScrollTick(),
    );
  }

  void _handleAutoScrollTick() {
    if (!_isDraggingSelection) {
      _stopAutoScroll();
      return;
    }
    final scrollController = _effectiveScrollController;
    if (!scrollController.hasClients) {
      _stopAutoScroll();
      return;
    }
    final velocity = _autoScrollVelocity();
    if (velocity == 0) {
      _stopAutoScroll();
      return;
    }

    final position = scrollController.position;
    final nextOffset = (position.pixels +
            velocity * _autoScrollTickInterval.inMilliseconds / 1000)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((nextOffset - position.pixels).abs() < 0.5) {
      _stopAutoScroll();
      return;
    }
    scrollController.jumpTo(nextOffset);
    final globalPosition = _lastDragPointerPosition;
    if (globalPosition != null) {
      _updateDragSelectionAt(globalPosition);
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  double _autoScrollVelocity() {
    final globalPosition = _lastDragPointerPosition;
    final viewportRect = _scrollViewportRect;
    final scrollController = _effectiveScrollController;
    if (globalPosition == null ||
        viewportRect == null ||
        !scrollController.hasClients) {
      return 0;
    }
    final position = scrollController.position;
    if (position.maxScrollExtent <= position.minScrollExtent) {
      return 0;
    }

    if (globalPosition.dy < viewportRect.top + _autoScrollActivationZone &&
        position.pixels > position.minScrollExtent) {
      final proximity = 1 -
          ((globalPosition.dy - viewportRect.top) / _autoScrollActivationZone)
              .clamp(0.0, 1.0);
      return -_autoScrollSpeedForProximity(proximity);
    }
    if (globalPosition.dy > viewportRect.bottom - _autoScrollActivationZone &&
        position.pixels < position.maxScrollExtent) {
      final proximity = ((globalPosition.dy -
                  (viewportRect.bottom - _autoScrollActivationZone)) /
              _autoScrollActivationZone)
          .clamp(0.0, 1.0);
      return _autoScrollSpeedForProximity(proximity);
    }
    return 0;
  }

  double _autoScrollSpeedForProximity(double proximity) {
    if (proximity <= 0) {
      return 0;
    }
    return math.max(80, proximity * proximity * _autoScrollMaxSpeed);
  }

  Rect? get _scrollViewportRect {
    final renderObject = _scrollableKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
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

  DocumentPosition? _tableBoundaryPositionForDrag(
    Offset globalPosition, {
    required DocumentPosition anchor,
  }) {
    for (var blockIndex = 0;
        blockIndex < widget.document.blocks.length;
        blockIndex++) {
      final block = widget.document.blocks[blockIndex];
      if (block is! TableBlock) {
        continue;
      }
      final state = _tableBlockKeys[block.id]?.currentState;
      if (state == null || !state.containsGlobal(globalPosition)) {
        continue;
      }
      final cell = state.cellPositionAtGlobal(globalPosition);
      final preferEnd = anchor.blockIndex <= blockIndex;
      return DocumentPosition(
        blockIndex: blockIndex,
        path: cell == null
            ? const PathInBlock(<int>[0])
            : PathInBlock(<int>[cell.rowIndex, cell.columnIndex]),
        textOffset: cell == null
            ? preferEnd
                ? _plainTextSerializer.serializeBlockText(block).length
                : 0
            : _tableTextOffsetForCell(
                block,
                cell,
                preferEnd: preferEnd,
              ),
      );
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
        textWidgetBuilder: _buildInlineTextWidget,
        onRequestContextMenu: _showCustomContextMenu,
        documentSelected: _isBlockCoveredByTextSelection(
          blockIndex,
          selectionRange,
        ),
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

    if (selectionController != null &&
        widget.imageBuilder != null &&
        block is ImageBlock) {
      final key = _blockKeys.putIfAbsent(
        block.id,
        () => GlobalKey<SelectableMarkdownBlockState>(debugLabel: block.id),
      );
      return SelectableMarkdownBlock(
        key: key,
        blockIndex: blockIndex,
        spec: _buildCustomImageBuilderSpec(block),
        selectionColor: widget.theme.selectionColor,
        selectionRange: selectionRange,
      );
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
        if (_inlinesContainMath(heading.inlines)) {
          return SelectableBlockSpec(
            child: _buildTextBlock(
              style: style,
              inlines: heading.inlines,
              textAlign: _resolvedInlineTextAlign(heading.inlines),
            ),
            plainText: _flattenInlineText(heading.inlines),
            hitTestBehavior: SelectableBlockHitTestBehavior.block,
          );
        }
        final plainText = _flattenInlineText(heading.inlines);
        return _buildPretextTextSpec(
          plainText: plainText,
          runs: _buildPretextRuns(style, heading.inlines),
          fallbackStyle: style,
          textAlign: _resolvedInlineTextAlign(heading.inlines),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        if (_inlinesContainMath(paragraph.inlines)) {
          return SelectableBlockSpec(
            child: _buildTextBlock(
              style: widget.theme.bodyStyle,
              inlines: paragraph.inlines,
              textAlign: _resolvedInlineTextAlign(paragraph.inlines),
            ),
            plainText: _flattenInlineText(paragraph.inlines),
            hitTestBehavior: SelectableBlockHitTestBehavior.block,
          );
        }
        final plainText = _flattenInlineText(paragraph.inlines);
        return _buildPretextTextSpec(
          plainText: plainText,
          runs: _buildPretextRuns(widget.theme.bodyStyle, paragraph.inlines),
          fallbackStyle: widget.theme.bodyStyle,
          textAlign: _resolvedInlineTextAlign(paragraph.inlines),
        );
      case MarkdownBlockKind.quote:
        final quoteBlock = block as QuoteBlock;
        if (widget.selectionController != null) {
          final descriptor = _buildQuoteSelectableDescriptor(quoteBlock);
          return SelectableBlockSpec(
            child: MarkdownQuoteBlockView(
              theme: widget.theme,
              child: _buildQuoteContent(
                quoteBlock,
                childKeys: _quoteChildKeysFor(quoteBlock),
              ),
            ),
            plainText: descriptor.plainText,
            hitTestBehavior: SelectableBlockHitTestBehavior.text,
            textSpan: descriptor.span,
            highlightBorderRadius: BorderRadius.circular(16),
            selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
            selectionColor: _quoteSelectionColor,
            selectionRectResolver: (context, _, range) =>
                _resolveQuoteSelectionRects(
              context,
              quoteBlock,
              range,
            ),
            textOffsetResolver: (context, _, localPosition) =>
                _resolveQuoteTextOffset(
              context,
              quoteBlock,
              localPosition,
            ),
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
              itemBuilder: (index, item) =>
                  _buildListItemContent(listBlock, index, item),
              itemRowKeyBuilder: (index) => itemRowKeys[index],
              itemContentKeyBuilder: (index) => itemContentKeys[index],
            ),
            plainText: descriptor.plainText,
            hitTestBehavior: SelectableBlockHitTestBehavior.text,
            textSpan: descriptor.span,
            selectionRectResolver: (context, _, range) =>
                _resolveListSelectionRects(
              context,
              listBlock,
              range,
            ),
            textOffsetResolver: (context, _, localPosition) =>
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
      case MarkdownBlockKind.definitionList:
        final definitionList = block as DefinitionListBlock;
        final definitionDescriptor =
            _buildDefinitionListSelectableDescriptor(definitionList);
        return SelectableBlockSpec(
          child: Text.rich(
            definitionDescriptor.span,
            style: widget.theme.bodyStyle,
          ),
          plainText: definitionDescriptor.plainText,
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: definitionDescriptor.span,
        );
      case MarkdownBlockKind.footnoteList:
        final footnoteList = block as FootnoteListBlock;
        final orderedFootnotes = _footnoteListAsOrderedList(footnoteList);
        final footnoteDescriptor =
            _buildFootnoteListSelectableDescriptor(footnoteList);
        final itemRowKeys = _listItemKeysFor(orderedFootnotes);
        final itemContentKeys = _listItemContentKeysFor(orderedFootnotes);
        return SelectableBlockSpec(
          child: _buildFootnoteListContainer(
            child: MarkdownListBlockView(
              theme: widget.theme,
              block: orderedFootnotes,
              itemBuilder: (index, item) =>
                  _buildListItemContent(orderedFootnotes, index, item),
              itemRowKeyBuilder: (index) => itemRowKeys[index],
              itemContentKeyBuilder: (index) => itemContentKeys[index],
            ),
          ),
          plainText: footnoteDescriptor.plainText,
          hitTestBehavior: SelectableBlockHitTestBehavior.text,
          textSpan: footnoteDescriptor.span,
          selectionRectResolver: (context, _, range) =>
              _resolveListSelectionRects(
            context,
            orderedFootnotes,
            range,
          ),
          textOffsetResolver: (context, _, localPosition) =>
              _resolveListTextOffset(
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
          measurementPadding: widget.theme.codeBlockPadding
                  .resolve(Directionality.of(context)) +
              const EdgeInsets.only(top: _codeToolbarHeight),
          highlightBorderRadius: widget.theme.codeBlockBorderRadius,
          selectionPaintOrder: SelectableBlockSelectionPaintOrder.aboveChild,
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

  Widget _buildBlockListItem({
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
        bottom: blockIndex == this.widget.document.blocks.length - 1
            ? 0
            : this.widget.theme.blockSpacing,
      ),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: this.widget.theme.maxContentWidth),
          child: _buildBlockView(
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

    _cachedBlockRows[block.id] = _CachedBlockRow(
      block: block,
      blockIndex: blockIndex,
      selectionSignature: selectionSignature,
      widget: widget,
    );
    return widget;
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
        final layout = _computePretextLayoutForContext(
          context,
          runs: runs,
          fallbackStyle: fallbackStyle,
          maxWidth: constraints.width,
          textAlign: textAlign,
        );
        return layout.selectionRectsForRange(
          range,
          textDirection: Directionality.of(context),
        );
      },
      textOffsetResolver: (context, size, localPosition) {
        final layout = _computePretextLayoutForContext(
          context,
          runs: runs,
          fallbackStyle: fallbackStyle,
          maxWidth: size.width,
          textAlign: textAlign,
        );
        return layout.textOffsetAt(
          localPosition,
          textDirection: Directionality.of(context),
        );
      },
    );
  }

  MarkdownPretextLayoutResult _computePretextLayoutForContext(
    BuildContext context, {
    required List<MarkdownPretextInlineRun> runs,
    required TextStyle fallbackStyle,
    required double maxWidth,
    TextAlign textAlign = TextAlign.start,
  }) {
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    return computeMarkdownPretextLayoutFromRuns(
      runs: runs,
      fallbackStyle: fallbackStyle,
      maxWidth: maxWidth,
      textScaleFactor: textScaler.scale(1.0),
      textAlign: textAlign,
      textDirection: Directionality.of(context),
    );
  }

  List<MarkdownPretextInlineRun> _buildPretextRuns(
    TextStyle baseStyle,
    List<InlineNode> inlines,
  ) {
    return <MarkdownPretextInlineRun>[
      for (final inline in inlines) ..._buildPretextRun(baseStyle, inline),
    ];
  }

  List<MarkdownPretextInlineRun> _buildPretextRun(
    TextStyle baseStyle,
    InlineNode inline,
  ) {
    switch (inline.kind) {
      case MarkdownInlineKind.text:
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: (inline as TextInline).text,
            style: baseStyle,
          ),
        ];
      case MarkdownInlineKind.emphasis:
        final emphasis = inline as EmphasisInline;
        final style = baseStyle.copyWith(fontStyle: FontStyle.italic);
        return _buildPretextRuns(style, emphasis.children);
      case MarkdownInlineKind.strong:
        final strong = inline as StrongInline;
        final style = baseStyle.copyWith(fontWeight: FontWeight.w700);
        return _buildPretextRuns(style, strong.children);
      case MarkdownInlineKind.strikethrough:
        final strike = inline as StrikethroughInline;
        final style =
            baseStyle.copyWith(decoration: TextDecoration.lineThrough);
        return _buildPretextRuns(style, strike.children);
      case MarkdownInlineKind.highlight:
        final highlight = inline as HighlightInline;
        return _buildPretextRuns(
            _highlightStyle(baseStyle), highlight.children);
      case MarkdownInlineKind.subscript:
        final subscript = inline as SubscriptInline;
        return _buildPretextRuns(
            _subscriptStyle(baseStyle), subscript.children);
      case MarkdownInlineKind.superscript:
        final superscript = inline as SuperscriptInline;
        return _buildPretextRuns(
          _superscriptStyle(baseStyle),
          superscript.children,
        );
      case MarkdownInlineKind.link:
        final link = inline as LinkInline;
        final label = _flattenInlineText(link.children);
        final recognizer = widget.onTapLink == null
            ? null
            : _registerLink(() {
                widget.onTapLink!(link.destination, link.title, label);
              });
        final linkStyle = baseStyle.merge(widget.theme.linkStyle);
        return _buildPretextRuns(linkStyle, link.children)
            .map(
              (run) => MarkdownPretextInlineRun(
                text: run.text,
                style: run.style,
                mouseCursor: widget.onTapLink != null
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                recognizer: recognizer,
              ),
            )
            .toList(growable: false);
      case MarkdownInlineKind.math:
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: (inline as MathInline).tex,
            style: baseStyle.merge(widget.theme.inlineCodeStyle),
          ),
        ];
      case MarkdownInlineKind.inlineCode:
        final code = inline as InlineCode;
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: code.text,
            style: baseStyle.merge(widget.theme.inlineCodeStyle),
          ),
        ];
      case MarkdownInlineKind.softBreak:
      case MarkdownInlineKind.hardBreak:
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: '\n',
            style: baseStyle,
          ),
        ];
      case MarkdownInlineKind.image:
        final image = inline as InlineImage;
        final label = image.alt?.trim().isNotEmpty == true
            ? image.alt!.trim()
            : image.url;
        return <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: label,
            style: baseStyle.merge(widget.theme.linkStyle),
          ),
        ];
    }
  }

  SelectableBlockSpec _buildCustomImageBuilderSpec(ImageBlock block) {
    final caption = _imageCaptionText(block);
    return SelectableBlockSpec(
      child: MarkdownImageBlockView(
        image: _buildImageVisual(block),
        caption: caption.isEmpty
            ? null
            : Text(
                caption,
                style: _imageCaptionStyle,
              ),
      ),
      plainText: _plainTextSerializer.serializeBlockText(block),
      hitTestBehavior: SelectableBlockHitTestBehavior.block,
      highlightBorderRadius: widget.theme.imageBorderRadius,
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
        : _plainTextSerializer.serializeBlockText(block).length;
    return 'text:$start:$end';
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

  TextSpan _buildTextSpan(TextStyle style, List<InlineNode> inlines) {
    return TextSpan(style: style, children: _buildInlineSpans(style, inlines));
  }

  Widget _buildTextBlock({
    required TextStyle style,
    required List<InlineNode> inlines,
    TextAlign textAlign = TextAlign.start,
  }) {
    if (_inlinesContainMath(inlines)) {
      return Text.rich(
        _buildTextSpan(style, inlines),
        textAlign: textAlign,
      );
    }
    return MarkdownPretextTextBlock.rich(
      runs: _buildPretextRuns(style, inlines),
      fallbackStyle: style,
      textAlign: textAlign,
    );
  }

  Widget _buildQuote(QuoteBlock block) {
    return MarkdownQuoteBlockView(
      theme: widget.theme,
      child: _buildQuoteContent(
        block,
        childKeys: _quoteChildKeysFor(block),
      ),
    );
  }

  Widget _buildQuoteContent(
    QuoteBlock block, {
    List<GlobalKey>? childKeys,
  }) {
    return DefaultTextStyle.merge(
      style: widget.theme.quoteStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildNestedBlocks(
          block.children,
          blockKeyBuilder:
              childKeys == null ? null : (index) => childKeys[index],
        ),
      ),
    );
  }

  List<Widget> _buildNestedBlocks(
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
                  : widget.theme.blockSpacing * 0.65,
            ),
            child: _buildNestedBlockContent(blocks[index]),
          ),
        ),
    ];
  }

  Widget _buildNestedBlockContent(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        return _buildTextBlock(
          style: widget.theme.headingStyleForLevel(heading.level),
          inlines: heading.inlines,
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        return _buildTextBlock(
          style: widget.theme.bodyStyle,
          inlines: paragraph.inlines,
        );
      case MarkdownBlockKind.quote:
        return _buildQuote(block as QuoteBlock);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _buildList(block as ListBlock);
      case MarkdownBlockKind.definitionList:
        return _buildDefinitionList(block as DefinitionListBlock);
      case MarkdownBlockKind.footnoteList:
        return _buildFootnoteList(block as FootnoteListBlock);
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
    final itemRowKeys = _listItemKeysFor(block);
    final itemContentKeys = _listItemContentKeysFor(block);
    return MarkdownListBlockView(
      theme: widget.theme,
      block: block,
      itemBuilder: (index, item) => _buildListItemContent(block, index, item),
      itemRowKeyBuilder: (index) => itemRowKeys[index],
      itemContentKeyBuilder: (index) => itemContentKeys[index],
    );
  }

  Widget _buildDefinitionList(DefinitionListBlock block) {
    final descriptor = _buildDefinitionListSelectableDescriptor(block);
    return Text.rich(
      descriptor.span,
      style: widget.theme.bodyStyle,
    );
  }

  Widget _buildFootnoteList(FootnoteListBlock block) {
    final orderedFootnotes = _footnoteListAsOrderedList(block);
    final itemRowKeys = _listItemKeysFor(orderedFootnotes);
    final itemContentKeys = _listItemContentKeysFor(orderedFootnotes);
    return _buildFootnoteListContainer(
      child: MarkdownListBlockView(
        theme: widget.theme,
        block: orderedFootnotes,
        itemBuilder: (index, item) =>
            _buildListItemContent(orderedFootnotes, index, item),
        itemRowKeyBuilder: (index) => itemRowKeys[index],
        itemContentKeyBuilder: (index) => itemContentKeys[index],
      ),
    );
  }

  Widget _buildListItemContent(
    ListBlock block,
    int itemIndex,
    ListItemNode item,
  ) {
    if (item.children.isEmpty) {
      return const SizedBox.shrink();
    }

    final childKeys = _listItemChildKeysFor(block, itemIndex);
    if (item.children.length == 1) {
      return KeyedSubtree(
        key: childKeys.first,
        child: _buildNestedBlockContent(item.children.first),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildNestedBlocks(
        item.children,
        blockKeyBuilder: (index) => childKeys[index],
      ),
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
      textWidgetBuilder: _buildInlineTextWidget,
    );
  }

  Widget _buildInlineTextWidget(
    BuildContext context,
    TextStyle style,
    List<InlineNode> inlines,
    TextAlign textAlign,
  ) {
    if (_inlinesContainMath(inlines)) {
      return Text.rich(
        _buildTextSpan(style, inlines),
        textAlign: textAlign,
      );
    }
    return MarkdownPretextTextBlock.rich(
      runs: _buildPretextRuns(style, inlines),
      fallbackStyle: style,
      textAlign: textAlign,
      intrinsicWidthSafe: true,
    );
  }

  Widget _buildImage(ImageBlock block) {
    if (widget.imageBuilder != null) {
      return _wrapLinkedImage(
        block,
        widget.imageBuilder!(context, block, widget.theme),
      );
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
    if (widget.imageBuilder != null) {
      return _wrapLinkedImage(
        block,
        widget.imageBuilder!(context, block, widget.theme),
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
        borderRadius: widget.theme.imageBorderRadius,
        child: image,
      ),
    );
  }

  Widget _wrapLinkedImage(ImageBlock block, Widget child) {
    final destination = block.linkDestination;
    if (destination == null ||
        destination.isEmpty ||
        widget.onTapLink == null) {
      return child;
    }
    final label = _imageCaptionText(block).isNotEmpty
        ? _imageCaptionText(block)
        : block.url;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onTapLink!(destination, block.linkTitle, label);
        },
        child: child,
      ),
    );
  }

  TextStyle get _imageCaptionStyle {
    return widget.theme.bodyStyle.copyWith(
      fontSize: 13,
      color: widget.theme.bodyStyle.color?.withOpacity(0.72),
    );
  }

  TextStyle get _definitionTermStyle {
    return widget.theme.bodyStyle.copyWith(fontWeight: FontWeight.w700);
  }

  Color get _quoteSelectionColor {
    final opacity = math.min(
      math.max(widget.theme.selectionColor.opacity * 0.72, 0.14),
      0.2,
    );
    return widget.theme.selectionColor.withOpacity(opacity);
  }

  TextStyle _highlightStyle(TextStyle baseStyle) {
    final accent = widget.theme.linkStyle.color ?? widget.theme.dividerColor;
    return baseStyle.copyWith(
      backgroundColor: accent.withOpacity(0.18),
    );
  }

  TextStyle _subscriptStyle(TextStyle baseStyle) {
    final baseFontSize =
        baseStyle.fontSize ?? widget.theme.bodyStyle.fontSize ?? 16;
    return baseStyle.copyWith(
      fontSize: baseFontSize * 0.82,
      fontFeatures: const <FontFeature>[FontFeature.subscripts()],
    );
  }

  TextStyle _superscriptStyle(TextStyle baseStyle) {
    final baseFontSize =
        baseStyle.fontSize ?? widget.theme.bodyStyle.fontSize ?? 16;
    return baseStyle.copyWith(
      fontSize: baseFontSize * 0.82,
      fontFeatures: const <FontFeature>[FontFeature.superscripts()],
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

  _SelectableTextDescriptor _buildDefinitionListSelectableDescriptor(
    DefinitionListBlock block,
  ) {
    final itemDescriptors = <_SelectableTextDescriptor>[];
    for (final item in block.items) {
      final termDescriptor =
          _descriptorFromInlines(_definitionTermStyle, item.term);
      final definitionDescriptors = <_SelectableTextDescriptor>[];
      for (final definition in item.definitions) {
        final childDescriptors = <_SelectableTextDescriptor>[];
        for (final child in definition) {
          final descriptor = _buildSelectableDescriptorForBlock(
            child,
            indentLevel: 1,
          );
          if (!descriptor.isEmpty) {
            childDescriptors.add(descriptor);
          }
        }
        final definitionDescriptor = _joinSelectableTextDescriptors(
          childDescriptors,
          separator: '\n\n',
          separatorStyle: widget.theme.bodyStyle,
        );
        if (!definitionDescriptor.isEmpty) {
          definitionDescriptors.add(
            _prefixSelectableTextDescriptor(
              definitionDescriptor,
              firstPrefix: ': ',
              continuationPrefix: '  ',
              style: widget.theme.bodyStyle,
            ),
          );
        }
      }
      final itemDescriptor = _joinSelectableTextDescriptors(
        <_SelectableTextDescriptor>[termDescriptor, ...definitionDescriptors],
        separator: '\n',
        separatorStyle: widget.theme.bodyStyle,
      );
      if (!itemDescriptor.isEmpty) {
        itemDescriptors.add(itemDescriptor);
      }
    }
    return _joinSelectableTextDescriptors(
      itemDescriptors,
      separator: '\n',
      separatorStyle: widget.theme.bodyStyle,
    );
  }

  _SelectableTextDescriptor _buildFootnoteListSelectableDescriptor(
    FootnoteListBlock block,
  ) {
    return _buildListSelectableDescriptor(_footnoteListAsOrderedList(block));
  }

  String _listItemPrefixText(
    ListBlock block,
    int index, {
    required int indentLevel,
  }) {
    final item = block.items[index];
    final marker = block.ordered ? '${block.startIndex + index}.' : '-';
    final checkbox = switch (item.taskState) {
      MarkdownTaskListItemState.checked => ' [x]',
      MarkdownTaskListItemState.unchecked => ' [ ]',
      null => '',
    };
    return '${'  ' * indentLevel}$marker$checkbox ';
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

  List<GlobalKey> _listItemChildKeysFor(ListBlock block, int itemIndex) {
    final keySets = _listItemChildKeysByBlock.putIfAbsent(
      block.id,
      () => <List<GlobalKey>>[],
    );
    while (keySets.length < block.items.length) {
      keySets.add(<GlobalKey>[]);
    }
    if (keySets.length > block.items.length) {
      keySets.removeRange(block.items.length, keySets.length);
    }

    final keys = keySets[itemIndex];
    final childCount = block.items[itemIndex].children.length;
    while (keys.length < childCount) {
      keys.add(
        GlobalKey(
          debugLabel: 'list-child-${block.id}-$itemIndex-${keys.length}',
        ),
      );
    }
    if (keys.length > childCount) {
      keys.removeRange(childCount, keys.length);
    }
    return keys;
  }

  int? _resolveListTextOffset(
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
    final indexedDescriptors = _buildIndexedListSelectionDescriptors(
      block,
      indentLevel: indentLevel,
    );
    if (indexedDescriptors.isEmpty) {
      return null;
    }

    final contentKeys = _listItemContentKeysFor(block);
    final rowKeys = _listItemKeysFor(block);
    _IndexedListSelectionDescriptor? nearestEntry;
    Rect? nearestRowRect;
    double bestDistance = double.infinity;

    for (final entry in indexedDescriptors) {
      final contentContext = contentKeys[entry.itemIndex].currentContext;
      final contentRenderObject = contentContext?.findRenderObject();
      Rect? contentRect;
      List<_IndexedBlockDescriptor>? childEntries;
      int? childOffset;
      if (contentRenderObject is RenderBox && contentRenderObject.hasSize) {
        contentRect = contentRenderObject.localToGlobal(Offset.zero) &
            contentRenderObject.size;
        childEntries = _buildIndexedBlockDescriptors(
          block.items[entry.itemIndex].children,
          indentLevel: entry.contentIndentLevel,
          separator: '\n',
        );
        childOffset = _resolveIndexedBlockTextOffsetInRoot(
          context,
          rootRenderObject: rootRenderObject,
          entries: childEntries,
          childKeys: _listItemChildKeysFor(block, entry.itemIndex),
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
            final projectedChildOffset = _resolveIndexedBlockTextOffsetInRoot(
              context,
              rootRenderObject: rootRenderObject,
              entries: childEntries,
              childKeys: _listItemChildKeysFor(block, entry.itemIndex),
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
      final preferEnd = globalPosition.dy > nearestRowRect!.center.dy ||
          globalPosition.dx > nearestRowRect!.center.dx;
      return nearestEntry.startOffset +
          (preferEnd ? nearestEntry.descriptor.plainText.length : 0);
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

  int _resolveDescriptorTextOffset(
    BuildContext context, {
    required _SelectableTextDescriptor descriptor,
    required Offset localPosition,
    required Size size,
    required TextDirection textDirection,
  }) {
    final pretext = descriptor.pretext;
    if (pretext != null) {
      final layout = _computeDescriptorPretextLayout(
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

    return _resolveTextOffsetInBox(
      descriptor.span,
      descriptor.plainText.length,
      localPosition,
      size,
      textDirection,
    );
  }

  MarkdownPretextLayoutResult _computeDescriptorPretextLayout(
    BuildContext context, {
    required _SelectableTextDescriptor descriptor,
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

  List<Rect> _resolveDescriptorSelectionRects(
    BuildContext context, {
    required _SelectableTextDescriptor descriptor,
    required DocumentRange range,
    required Size size,
    required TextDirection textDirection,
    Offset origin = Offset.zero,
  }) {
    final pretext = descriptor.pretext;
    if (pretext != null) {
      final layout = _computeDescriptorPretextLayout(
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
            box.left + origin.dx,
            box.top + origin.dy,
            box.right + origin.dx,
            box.bottom + origin.dy,
          ).inflate(1.5),
        )
        .toList(growable: false);
  }

  List<Rect> _resolveListSelectionRects(
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
    final indexedDescriptors = _buildIndexedListSelectionDescriptors(
      block,
      indentLevel: indentLevel,
    );
    if (indexedDescriptors.isEmpty) {
      return const <Rect>[];
    }

    final rects = <Rect>[];
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
        final childEntries = _buildIndexedBlockDescriptors(
          block.items[entry.itemIndex].children,
          indentLevel: entry.contentIndentLevel,
          separator: '\n',
        );
        contentRects = _resolveIndexedBlockSelectionRectsInRoot(
          context,
          rootRenderObject: rootRenderObject,
          entries: childEntries,
          childKeys: _listItemChildKeysFor(block, entry.itemIndex),
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
    final childEntries = _buildIndexedBlockDescriptors(
      block.items[itemIndex].children,
      indentLevel: contentIndentLevel,
      separator: '\n',
    );
    final childKeys = _listItemChildKeysFor(block, itemIndex);
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
      top - 1.5,
      rowOrigin.dx + extent,
      top + height + 1.5,
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

  int _tableTextOffsetForCell(
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
        final cellText = _flattenInlineText(row.cells[columnIndex].inlines);
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

  Rect? _resolveFirstLineRectForNestedBlockInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required BlockNode block,
    required _SelectableTextDescriptor descriptor,
    required RenderBox renderObject,
    required Offset origin,
    required TextDirection textDirection,
    required int indentLevel,
  }) {
    if (descriptor.plainText.isEmpty) {
      return null;
    }

    final rects = _resolveNestedBlockSelectionRects(
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
          path: const PathInBlock(<int>[0]),
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

  List<Rect> _resolveQuoteSelectionRects(
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
    final entries = _buildIndexedBlockDescriptors(
      block.children,
      separator: '\n\n',
    );
    if (entries.isEmpty) {
      return const <Rect>[];
    }
    return _resolveIndexedBlockSelectionRectsInRoot(
      context,
      rootRenderObject: rootRenderObject,
      entries: entries,
      childKeys: _quoteChildKeysFor(block),
      range: range,
    );
  }

  int? _resolveQuoteTextOffset(
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
    final entries = _buildIndexedBlockDescriptors(
      block.children,
      separator: '\n\n',
    );
    if (entries.isEmpty) {
      return null;
    }
    return _resolveIndexedBlockTextOffsetInRoot(
      context,
      rootRenderObject: rootRenderObject,
      entries: entries,
      childKeys: _quoteChildKeysFor(block),
      globalPosition: globalPosition,
    );
  }

  List<Rect> _resolveIndexedBlockSelectionRectsInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required List<_IndexedBlockDescriptor> entries,
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
        _resolveNestedBlockSelectionRects(
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

  int? _resolveIndexedBlockTextOffsetInRoot(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required List<_IndexedBlockDescriptor> entries,
    required List<GlobalKey> childKeys,
    required Offset globalPosition,
  }) {
    final textDirection = Directionality.of(context);
    final resolvedEntries = <_ResolvedIndexedBlockEntry>[];
    _IndexedBlockDescriptor? nearestEntry;
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
        _ResolvedIndexedBlockEntry(
          entry: entry,
          renderObject: childRenderObject,
          rect: rect,
        ),
      );
      if (rect.contains(globalPosition)) {
        return entry.startOffset +
            _resolveNestedBlockTextOffset(
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

  List<Rect> _resolveNestedBlockSelectionRects(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required BlockNode block,
    required _SelectableTextDescriptor descriptor,
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
        return _resolveDescriptorSelectionRects(
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
          block: _footnoteListAsOrderedList(block as FootnoteListBlock),
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
        return _resolveTextSpanSelectionRects(
          _buildCodeTextSpan(block as CodeBlock),
          range,
          size: renderObject.size,
          textDirection: textDirection,
          measurementPadding: widget.theme.codeBlockPadding
                  .resolve(Directionality.of(context)) +
              const EdgeInsets.only(top: _codeToolbarHeight),
          origin: origin,
        );
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        return <Rect>[(origin & renderObject.size).inflate(1.5)];
    }
  }

  int _resolveNestedBlockTextOffset(
    BuildContext context, {
    required RenderBox rootRenderObject,
    required BlockNode block,
    required _SelectableTextDescriptor descriptor,
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
        return _resolveDescriptorTextOffset(
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
              block: _footnoteListAsOrderedList(block as FootnoteListBlock),
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
        return _resolveTextSpanTextOffset(
          _buildCodeTextSpan(block as CodeBlock),
          descriptor.plainText.length,
          localPosition: localPosition,
          size: renderObject.size,
          textDirection: textDirection,
          measurementPadding: widget.theme.codeBlockPadding
                  .resolve(Directionality.of(context)) +
              const EdgeInsets.only(top: _codeToolbarHeight),
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

  List<Rect> _resolveTextSpanSelectionRects(
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
    final boxes = _mergeAdjacentTextSelectionBoxes(
      textPainter.getBoxesForSelection(
        TextSelection(
          baseOffset: range.start.textOffset,
          extentOffset: range.end.textOffset,
        ),
      ),
    );
    return boxes
        .map(
          (box) => Rect.fromLTRB(
            box.left + measurementPadding.left + origin.dx,
            box.top + measurementPadding.top + origin.dy,
            box.right + measurementPadding.left + origin.dx,
            box.bottom + measurementPadding.top + origin.dy,
          ).inflate(1.5),
        )
        .toList(growable: false);
  }

  List<TextBox> _mergeAdjacentTextSelectionBoxes(List<TextBox> boxes) {
    if (boxes.length < 2) {
      return boxes;
    }

    const lineTolerance = 2.0;
    const gapTolerance = 0.5;

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

  int _resolveTextSpanTextOffset(
    InlineSpan span,
    int textLength, {
    required Offset localPosition,
    required Size size,
    required TextDirection textDirection,
    required EdgeInsets measurementPadding,
  }) {
    return _resolveTextOffsetInBox(
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

  List<_IndexedBlockDescriptor> _buildIndexedBlockDescriptors(
    List<BlockNode> blocks, {
    int indentLevel = 0,
    required String separator,
  }) {
    final entries = <_IndexedBlockDescriptor>[];
    var offset = 0;
    for (var index = 0; index < blocks.length; index++) {
      final descriptor = _buildSelectableDescriptorForBlock(
        blocks[index],
        indentLevel: indentLevel,
      );
      if (descriptor.isEmpty) {
        continue;
      }
      if (entries.isNotEmpty) {
        offset += separator.length;
      }
      entries.add(
        _IndexedBlockDescriptor(
          childIndex: index,
          block: blocks[index],
          startOffset: offset,
          indentLevel: indentLevel,
          descriptor: descriptor,
        ),
      );
      offset += descriptor.plainText.length;
    }
    return entries;
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
    final prefix = _listItemPrefixText(
      block,
      index,
      indentLevel: indentLevel,
    );
    final contentDescriptor = _buildListItemSelectableDescriptor(
      block.items[index],
      indentLevel: indentLevel + 1,
    );
    if (contentDescriptor.isEmpty && block.items[index].taskState == null) {
      return null;
    }
    if (contentDescriptor.isEmpty) {
      final prefixOnly = prefix.trimRight();
      return _IndexedListSelectionDescriptor(
        itemIndex: index,
        startOffset: startOffset,
        prefixLength: prefixOnly.length,
        contentIndentLevel: indentLevel + 1,
        descriptor: _plainTextDescriptor(prefixOnly, widget.theme.bodyStyle),
        contentDescriptor: _plainTextDescriptor('', widget.theme.bodyStyle),
      );
    }
    final continuationPrefix = ' ' * prefix.length;
    final descriptor = _prefixSelectableTextDescriptor(
      contentDescriptor,
      firstPrefix: prefix,
      continuationPrefix: continuationPrefix,
      style: widget.theme.bodyStyle,
    );
    return _IndexedListSelectionDescriptor(
      itemIndex: index,
      startOffset: startOffset,
      prefixLength: prefix.length,
      contentIndentLevel: indentLevel + 1,
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

  Set<String> _collectBlockIds(List<BlockNode> blocks) {
    final ids = <String>{};

    void visit(BlockNode block) {
      ids.add(block.id);
      if (block is QuoteBlock) {
        for (final child in block.children) {
          visit(child);
        }
        return;
      }
      if (block is ListBlock) {
        for (final item in block.items) {
          for (final child in item.children) {
            visit(child);
          }
        }
        return;
      }
      if (block is FootnoteListBlock) {
        for (final item in block.items) {
          for (final child in item.children) {
            visit(child);
          }
        }
        return;
      }
      if (block is DefinitionListBlock) {
        for (final item in block.items) {
          for (final definition in item.definitions) {
            for (final child in definition) {
              visit(child);
            }
          }
        }
      }
    }

    for (final block in blocks) {
      visit(block);
    }
    return ids;
  }

  List<GlobalKey> _quoteChildKeysFor(QuoteBlock block) {
    final keys =
        _quoteChildKeysByBlock.putIfAbsent(block.id, () => <GlobalKey>[]);
    while (keys.length < block.children.length) {
      keys.add(GlobalKey(debugLabel: 'quote-${block.id}-${keys.length}'));
    }
    if (keys.length > block.children.length) {
      keys.removeRange(block.children.length, keys.length);
    }
    return keys;
  }

  bool _isBlockCoveredByTextSelection(
    int blockIndex,
    DocumentRange? selectionRange,
  ) {
    return selectionRange != null &&
        blockIndex >= selectionRange.start.blockIndex &&
        blockIndex <= selectionRange.end.blockIndex;
  }

  ListBlock _footnoteListAsOrderedList(FootnoteListBlock block) {
    return ListBlock(
      id: block.id,
      ordered: true,
      startIndex: 1,
      items: block.items,
      sourceRange: block.sourceRange,
    );
  }

  Widget _buildFootnoteListContainer({
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: widget.theme.dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: child,
      ),
    );
  }

  _SelectableTextDescriptor _buildSelectableDescriptorForBlock(
    BlockNode block, {
    int indentLevel = 0,
  }) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        if (_inlinesContainMath(heading.inlines)) {
          return _plainTextDescriptor(
            _flattenInlineText(heading.inlines),
            widget.theme.headingStyleForLevel(heading.level),
          );
        }
        return _descriptorFromInlines(
          widget.theme.headingStyleForLevel(heading.level),
          heading.inlines,
          textAlign: _resolvedInlineTextAlign(heading.inlines),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        if (_inlinesContainMath(paragraph.inlines)) {
          return _plainTextDescriptor(
            _flattenInlineText(paragraph.inlines),
            widget.theme.bodyStyle,
          );
        }
        return _descriptorFromInlines(
          widget.theme.bodyStyle,
          paragraph.inlines,
          textAlign: _resolvedInlineTextAlign(paragraph.inlines),
        );
      case MarkdownBlockKind.quote:
        return _buildQuoteSelectableDescriptor(block as QuoteBlock);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _buildListSelectableDescriptor(
          block as ListBlock,
          indentLevel: indentLevel,
        );
      case MarkdownBlockKind.definitionList:
        return _buildDefinitionListSelectableDescriptor(
          block as DefinitionListBlock,
        );
      case MarkdownBlockKind.footnoteList:
        return _buildFootnoteListSelectableDescriptor(
          block as FootnoteListBlock,
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

  _SelectableTextDescriptor _descriptorFromInlines(
    TextStyle style,
    List<InlineNode> inlines, {
    TextAlign textAlign = TextAlign.start,
  }) {
    return _descriptorFromSpan(
      _buildTextSpan(style, inlines),
      _flattenInlineText(inlines),
      pretext: _PretextTextDescriptor(
        runs: _buildPretextRuns(style, inlines),
        fallbackStyle: style,
        textAlign: textAlign,
      ),
    );
  }

  _SelectableTextDescriptor _descriptorFromSpan(
    TextSpan span,
    String plainText, {
    _PretextTextDescriptor? pretext,
  }) {
    return _SelectableTextDescriptor(
      plainText: plainText,
      span: span,
      pretext: pretext,
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
    if (nonEmpty.length == 1) {
      return nonEmpty.single;
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
      case MarkdownInlineKind.highlight:
        final highlight = inline as HighlightInline;
        final highlightStyle = _highlightStyle(baseStyle);
        return <InlineSpan>[
          TextSpan(
            style: highlightStyle,
            children: _buildInlineSpans(highlightStyle, highlight.children),
          ),
        ];
      case MarkdownInlineKind.subscript:
        final subscript = inline as SubscriptInline;
        final subscriptStyle = _subscriptStyle(baseStyle);
        return <InlineSpan>[
          TextSpan(
            style: subscriptStyle,
            children: _buildInlineSpans(subscriptStyle, subscript.children),
          ),
        ];
      case MarkdownInlineKind.superscript:
        final superscript = inline as SuperscriptInline;
        final superscriptStyle = _superscriptStyle(baseStyle);
        return <InlineSpan>[
          TextSpan(
            style: superscriptStyle,
            children: _buildInlineSpans(superscriptStyle, superscript.children),
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
      case MarkdownInlineKind.math:
        final math = inline as MathInline;
        final child = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: math.displayStyle ? 0 : 2,
            vertical: math.displayStyle ? 6 : 0,
          ),
          child: Math.tex(
            math.tex,
            mathStyle: math.displayStyle ? MathStyle.display : MathStyle.text,
            textStyle: baseStyle,
            onErrorFallback: (error) => Text(
              math.tex,
              style: baseStyle.merge(widget.theme.inlineCodeStyle),
            ),
          ),
        );
        return <InlineSpan>[
          WidgetSpan(
            alignment: math.displayStyle
                ? PlaceholderAlignment.middle
                : PlaceholderAlignment.baseline,
            baseline: math.displayStyle ? null : TextBaseline.alphabetic,
            child: child,
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
        case MarkdownInlineKind.highlight:
          buffer
              .write(_flattenInlineText((inline as HighlightInline).children));
          break;
        case MarkdownInlineKind.subscript:
          buffer
              .write(_flattenInlineText((inline as SubscriptInline).children));
          break;
        case MarkdownInlineKind.superscript:
          buffer.write(
            _flattenInlineText((inline as SuperscriptInline).children),
          );
          break;
        case MarkdownInlineKind.link:
          buffer.write(_flattenInlineText((inline as LinkInline).children));
          break;
        case MarkdownInlineKind.math:
          buffer.write((inline as MathInline).tex);
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

  bool _inlinesContainMath(List<InlineNode> inlines) {
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.math:
          return true;
        case MarkdownInlineKind.emphasis:
          if (_inlinesContainMath((inline as EmphasisInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.strong:
          if (_inlinesContainMath((inline as StrongInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.strikethrough:
          if (_inlinesContainMath((inline as StrikethroughInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.highlight:
          if (_inlinesContainMath((inline as HighlightInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.subscript:
          if (_inlinesContainMath((inline as SubscriptInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.superscript:
          if (_inlinesContainMath((inline as SuperscriptInline).children)) {
            return true;
          }
          break;
        case MarkdownInlineKind.link:
          if (_inlinesContainMath((inline as LinkInline).children)) {
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

  TextAlign _resolvedInlineTextAlign(List<InlineNode> inlines) {
    return _isStandaloneDisplayMath(inlines)
        ? TextAlign.center
        : TextAlign.start;
  }

  bool _isStandaloneDisplayMath(List<InlineNode> inlines) {
    if (inlines.length != 1) {
      return false;
    }
    final inline = inlines.single;
    return inline is MathInline && inline.displayStyle;
  }
}

@immutable
class _SelectableTextDescriptor {
  const _SelectableTextDescriptor({
    required this.plainText,
    required this.span,
    this.pretext,
  });

  final String plainText;
  final TextSpan span;
  final _PretextTextDescriptor? pretext;

  bool get isEmpty => plainText.isEmpty;
}

@immutable
class _PretextTextDescriptor {
  const _PretextTextDescriptor({
    required this.runs,
    required this.fallbackStyle,
    required this.textAlign,
  });

  final List<MarkdownPretextInlineRun> runs;
  final TextStyle fallbackStyle;
  final TextAlign textAlign;
}

@immutable
class _IndexedListSelectionDescriptor {
  const _IndexedListSelectionDescriptor({
    required this.itemIndex,
    required this.startOffset,
    required this.prefixLength,
    required this.contentIndentLevel,
    required this.descriptor,
    required this.contentDescriptor,
  });

  final int itemIndex;
  final int startOffset;
  final int prefixLength;
  final int contentIndentLevel;
  final _SelectableTextDescriptor descriptor;
  final _SelectableTextDescriptor contentDescriptor;
}

@immutable
class _IndexedBlockDescriptor {
  const _IndexedBlockDescriptor({
    required this.childIndex,
    required this.block,
    required this.startOffset,
    required this.indentLevel,
    required this.descriptor,
  });

  final int childIndex;
  final BlockNode block;
  final int startOffset;
  final int indentLevel;
  final _SelectableTextDescriptor descriptor;
}

@immutable
class _ResolvedIndexedBlockEntry {
  const _ResolvedIndexedBlockEntry({
    required this.entry,
    required this.renderObject,
    required this.rect,
  });

  final _IndexedBlockDescriptor entry;
  final RenderBox renderObject;
  final Rect rect;
}

@immutable
class _CachedBlockRow {
  const _CachedBlockRow({
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
