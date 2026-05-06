import 'package:flutter/material.dart';

import '../core/document.dart';
import '../render/selection/markdown_selection_gesture_detector.dart';
import '../render/shortcuts/markdown_shortcuts_scope.dart';
import 'selection_controller.dart';

class MarkdownSelectionHost extends StatefulWidget {
  const MarkdownSelectionHost({
    super.key,
    required this.child,
    required this.selectionController,
    required this.document,
    required this.scrollableKey,
    required this.scrollController,
    required this.onRequestToolbar,
    required this.hitTestPosition,
    required this.hitTestExactTextPosition,
    required this.selectWordAt,
    required this.selectBlockAt,
    required this.selectSelectionUnitAt,
    this.onCopyPlainText,
    this.onTapOutside,
    this.additionalAutoScrollTargets,
    this.isSelectable = true,
  });

  final Widget child;
  final MarkdownSelectionController selectionController;
  final MarkdownDocument document;
  final GlobalKey scrollableKey;
  final ScrollController scrollController;
  final void Function(Offset) onRequestToolbar;
  final MarkdownHitTestPositionCallback hitTestPosition;
  final MarkdownHitTestExactTextPositionCallback hitTestExactTextPosition;
  final MarkdownSelectWordCallback selectWordAt;
  final MarkdownSelectBlockCallback selectBlockAt;
  final MarkdownSelectSelectionUnitCallback selectSelectionUnitAt;
  final VoidCallback? onCopyPlainText;
  final VoidCallback? onTapOutside;
  final Iterable<MarkdownSelectionAutoScrollTarget> Function()?
      additionalAutoScrollTargets;
  final bool isSelectable;

  @override
  State<MarkdownSelectionHost> createState() => _MarkdownSelectionHostState();
}

class _MarkdownSelectionHostState extends State<MarkdownSelectionHost> {
  final FocusNode _selectionFocusNode =
      FocusNode(debugLabel: 'mixin_markdown_widget.selection');

  @override
  void dispose() {
    _selectionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gestureDetectorWrap = MarkdownSelectionGestureDetector(
      selectionController: widget.selectionController,
      selectionFocusNode: _selectionFocusNode,
      isSelectable: widget.isSelectable,
      scrollableKey: widget.scrollableKey,
      scrollController: widget.scrollController,
      onRequestToolbar: widget.onRequestToolbar,
      hitTestPosition: widget.hitTestPosition,
      hitTestExactTextPosition: widget.hitTestExactTextPosition,
      selectWordAt: widget.selectWordAt,
      selectBlockAt: widget.selectBlockAt,
      selectSelectionUnitAt: widget.selectSelectionUnitAt,
      additionalAutoScrollTargets: widget.additionalAutoScrollTargets,
      child: widget.child,
    );

    final tapRegion = TapRegion(
      onTapOutside: (_) {
        widget.selectionController.clear();
        _selectionFocusNode.unfocus();
        widget.onTapOutside?.call();
      },
      child: Focus(
        focusNode: _selectionFocusNode,
        canRequestFocus: true,
        child: gestureDetectorWrap,
      ),
    );

    return MarkdownShortcutsScope(
      selectionController: widget.selectionController,
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
