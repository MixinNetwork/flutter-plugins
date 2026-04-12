import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';
import '../selection/selection_controller.dart';
import '../widgets/markdown_theme.dart';
import '../widgets/markdown_types.dart';
import 'code_syntax_highlighter.dart';

import 'builder/markdown_block_builder.dart';
import 'builder/markdown_inline_builder.dart';
import 'selection/markdown_descriptor_extractor.dart';
import 'selection/markdown_selection_gesture_detector.dart';
import 'selection/markdown_selection_resolver.dart';
import 'shortcuts/markdown_shortcuts_scope.dart';
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
    this.contextMenuBuilder,
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
  final MarkdownContextMenuBuilder? contextMenuBuilder;

  @override
  State<MarkdownDocumentView> createState() => _MarkdownDocumentViewState();
}

class _MarkdownDocumentViewState extends State<MarkdownDocumentView> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  final ScrollController _fallbackScrollController = ScrollController();
  final FocusNode _selectionFocusNode =
      FocusNode(debugLabel: 'mixin_markdown_widget.selection');
  final ContextMenuController _contextMenuController = ContextMenuController();
  final GlobalKey _scrollableKey = GlobalKey(debugLabel: 'markdown-scrollable');

  final MarkdownPlainTextSerializer _plainTextSerializer =
      const MarkdownPlainTextSerializer();
  final MarkdownCodeSyntaxHighlighter _codeSyntaxHighlighter =
      const MarkdownCodeSyntaxHighlighter();

  final Map<String, CachedBlockRow> _cachedBlockRows = {};

  late final MarkdownBlockKeysRegistry _keysRegistry;
  late MarkdownBlockBuilder _blockBuilder;

  ScrollController get _effectiveScrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void initState() {
    super.initState();
    _keysRegistry = MarkdownBlockKeysRegistry();
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

  @override
  void didUpdateWidget(covariant MarkdownDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final validIds = _collectBlockIds(widget.document.blocks);
    _keysRegistry.cleanupKeys(validIds);
    _cachedBlockRows.removeWhere((key, _) => !validIds.contains(key));

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
    _fallbackScrollController.dispose();
    _selectionFocusNode.dispose();
    _contextMenuController.remove();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _showToolbar(Offset globalPosition) {
    if (widget.selectionController == null) {
      return;
    }
    MarkdownContextMenu.show(
      context,
      contextMenuController: _contextMenuController,
      selectionController: widget.selectionController!,
      document: widget.document,
      globalPosition: globalPosition,
      onCopyPlainText: widget.onCopyPlainText,
      showCopyAllInContextMenu: widget.showCopyAllInContextMenu,
      contextMenuBuilder: widget.contextMenuBuilder,
    );
  }

  DocumentPosition? _hitTestPosition(Offset globalPosition,
      {required bool clamp}) {
    for (final block in widget.document.blocks) {
      // Depending on imports / architecture, blockKeys might store State directly
      final blockState =
          _keysRegistry.blockKeys[block.id]?.currentState as dynamic;
      final hit = blockState?.hitTestGlobal(globalPosition);
      if (hit != null) {
        return hit as DocumentPosition;
      }
    }
    if (!clamp) {
      return null;
    }

    dynamic nearestState;
    double bestDistance = double.infinity;
    for (final block in widget.document.blocks) {
      final blockState =
          _keysRegistry.blockKeys[block.id]?.currentState as dynamic;
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
    return nearestState?.boundaryPositionForGlobal(globalPosition)
        as DocumentPosition?;
  }

  SelectableMarkdownTableBlockState? _tableBlockStateContaining(
      Offset globalPosition) {
    for (final block in widget.document.blocks) {
      final state =
          _keysRegistry.tableBlockKeys[block.id]?.currentState as dynamic;
      if (state != null && state.containsGlobal(globalPosition) == true) {
        return state as SelectableMarkdownTableBlockState?;
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
      final state =
          _keysRegistry.tableBlockKeys[block.id]?.currentState as dynamic;
      if (state == null || state.containsGlobal(globalPosition) != true) {
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
            : MarkdownSelectionResolver(
                theme: widget.theme,
                extractor: MarkdownDescriptorExtractor(
                  theme: widget.theme,
                  plainTextSerializer: _plainTextSerializer,
                  inlineBuilder: MarkdownInlineBuilder(
                    theme: widget.theme,
                    recognizers: [],
                  ),
                ),
                keysRegistry: _keysRegistry,
                codeSyntaxHighlighter: _codeSyntaxHighlighter,
              ).tableTextOffsetForCell(
                block,
                cell,
                preferEnd: preferEnd,
              ),
      );
    }
    return null;
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

  dynamic _blockStateForIndex(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= widget.document.blocks.length) {
      return null;
    }
    final block = widget.document.blocks[blockIndex];
    return _keysRegistry.blockKeys[block.id]?.currentState as dynamic;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final inlineBuilder = MarkdownInlineBuilder(
      theme: widget.theme,
      recognizers: _recognizers,
      onTapLink: widget.onTapLink,
    );

    final descriptorExtractor = MarkdownDescriptorExtractor(
      theme: widget.theme,
      plainTextSerializer: _plainTextSerializer,
      inlineBuilder: inlineBuilder,
    );

    final selectionResolver = MarkdownSelectionResolver(
      theme: widget.theme,
      extractor: descriptorExtractor,
      keysRegistry: _keysRegistry,
      codeSyntaxHighlighter: _codeSyntaxHighlighter,
    );

    _blockBuilder = MarkdownBlockBuilder(
      theme: widget.theme,
      selectionController: widget.selectionController,
      document: widget.document,
      isSelectable: widget.selectable,
      keysRegistry: _keysRegistry,
      descriptorExtractor: descriptorExtractor,
      selectionResolver: selectionResolver,
      inlineBuilder: inlineBuilder,
      codeSyntaxHighlighter: _codeSyntaxHighlighter,
      plainTextSerializer: _plainTextSerializer,
      imageBuilder: widget.imageBuilder,
      onTapLink: widget.onTapLink,
      onRequestContextMenu: _showToolbar,
      cachedBlockRows: _cachedBlockRows,
    );

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
          return _blockBuilder.buildBlockListItem(
            context,
            block: block,
            blockIndex: index,
            selectionRange: selectionRange,
            tableSelection: tableSelection,
          );
        },
      ),
    );

    if (!widget.selectable || widget.selectionController == null) {
      return scrollable;
    }

    final gestureDetectorWrap = MarkdownSelectionGestureDetector(
      selectionController: widget.selectionController!,
      selectionFocusNode: _selectionFocusNode,
      isSelectable: widget.selectable,
      scrollableKey: _scrollableKey,
      scrollController: scrollController,
      onRequestToolbar: _showToolbar,
      hitTestPosition: _hitTestPosition,
      tableBlockStateContaining: _tableBlockStateContaining,
      tableBoundaryPositionForDrag: _tableBoundaryPositionForDrag,
      selectWordAt: _selectWordAt,
      selectBlockAt: _selectBlockAt,
      child: scrollable,
    );

    final tapRegion = TapRegion(
      onTapOutside: (_) {
        widget.selectionController!.clear();
        _selectionFocusNode.unfocus();
        _contextMenuController.remove();
      },
      child: Focus(
        focusNode: _selectionFocusNode,
        canRequestFocus: true,
        child: gestureDetectorWrap,
      ),
    );

    return MarkdownShortcutsScope(
      selectionController: widget.selectionController!,
      document: widget.document,
      onCopyPlainText: widget.onCopyPlainText,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!_selectionFocusNode.hasFocus) {
            _selectionFocusNode.requestFocus();
          }
        },
        child: tapRegion,
      ),
    );
  }
}
