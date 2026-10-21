import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/document.dart';
import '../render/selection/markdown_selection_gesture_detector.dart';
import '../render/shortcuts/markdown_shortcuts_scope.dart';
import '../widgets/markdown_types.dart';
import 'selection_controller.dart';

class MarkdownSelectionHost extends StatefulWidget {
  const MarkdownSelectionHost({
    super.key,
    required this.child,
    required this.selectionController,
    required this.document,
    required this.scrollableKey,
    required this.scrollController,
    required this.hitTestPosition,
    required this.hitTestExactTextPosition,
    required this.selectWordAt,
    required this.selectBlockAt,
    required this.selectSelectionUnitAt,
    this.contextMenuBuilder,
    this.linkDestinationAt,
    this.showCopyAllInContextMenu = true,
    this.onCopyPlainText,
    this.additionalAutoScrollTargets,
    this.isSelectable = true,
  });

  final Widget child;
  final MarkdownSelectionController selectionController;
  final MarkdownDocument document;
  final GlobalKey scrollableKey;
  final ScrollController scrollController;
  final MarkdownHitTestPositionCallback hitTestPosition;
  final MarkdownHitTestExactTextPositionCallback hitTestExactTextPosition;
  final MarkdownSelectWordCallback selectWordAt;
  final MarkdownSelectBlockCallback selectBlockAt;
  final MarkdownSelectSelectionUnitCallback selectSelectionUnitAt;
  final MarkdownContextMenuBuilder? contextMenuBuilder;
  final String? Function(Offset globalPosition)? linkDestinationAt;
  final bool showCopyAllInContextMenu;
  final VoidCallback? onCopyPlainText;
  final Iterable<MarkdownSelectionAutoScrollTarget> Function()?
      additionalAutoScrollTargets;
  final bool isSelectable;

  @override
  State<MarkdownSelectionHost> createState() => _MarkdownSelectionHostState();
}

class _MarkdownSelectionHostState extends State<MarkdownSelectionHost> {
  final FocusNode _selectionFocusNode =
      FocusNode(debugLabel: 'mixin_markdown_widget.selection');
  final ContextMenuController _contextMenuController = ContextMenuController();
  ScrollPosition? _ancestorScrollPosition;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The menu sits in the overlay, so it would stay behind when an
    // enclosing scrollable moves the text.
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _ancestorScrollPosition) {
      _ancestorScrollPosition?.removeListener(_hideContextMenu);
      _ancestorScrollPosition = position?..addListener(_hideContextMenu);
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.contextMenuBuilder == null) {
      _hideContextMenu();
    }
  }

  @override
  void dispose() {
    _ancestorScrollPosition?.removeListener(_hideContextMenu);
    _contextMenuController.remove();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  void _hideContextMenu() {
    if (_contextMenuController.isShown) {
      _contextMenuController.remove();
    }
  }

  void _handleSecondaryPointerDown(Offset globalPosition) {
    final builder = widget.contextMenuBuilder;
    if (builder == null) {
      return;
    }
    _selectForContextMenu(globalPosition);
    final linkDestination = widget.linkDestinationAt?.call(globalPosition);
    final details = MarkdownContextMenuDetails(
      anchors: TextSelectionToolbarAnchors(primaryAnchor: globalPosition),
      buttonItems: _buttonItems(linkDestination),
      selectionController: widget.selectionController,
      linkDestination: linkDestination,
      hide: _hideContextMenu,
    );
    _contextMenuController.show(
      context: context,
      // Clicks on the menu are not outside the selection.
      contextMenuBuilder: (context) => TapRegion(
        groupId: this,
        child: builder(context, details),
      ),
    );
  }

  /// Keeps a selection under the pointer. Otherwise Apple platforms select
  /// the word under the pointer and others clear the selection.
  void _selectForContextMenu(Offset globalPosition) {
    final position = widget.hitTestExactTextPosition(globalPosition);
    final range = widget.selectionController.normalizedRange;
    if (position != null &&
        range != null &&
        range.start != range.end &&
        _compareOffsets(range.start, position) <= 0 &&
        _compareOffsets(position, range.end) <= 0) {
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        if (position != null) {
          widget.selectWordAt(position, globalPosition: globalPosition);
          return;
        }
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        break;
    }
    widget.selectionController.clear();
  }

  // Offsets are in block display space; the path at a leaf boundary can be
  // either leaf.
  static int _compareOffsets(DocumentPosition a, DocumentPosition b) {
    final blockComparison = a.blockIndex.compareTo(b.blockIndex);
    return blockComparison != 0
        ? blockComparison
        : a.textOffset.compareTo(b.textOffset);
  }

  List<ContextMenuButtonItem> _buttonItems(String? linkDestination) {
    final selectionController = widget.selectionController;
    final range = selectionController.normalizedRange;
    final onCopyPlainText = widget.onCopyPlainText;
    VoidCallback hideAnd(VoidCallback action) => () {
          _hideContextMenu();
          action();
        };
    return <ContextMenuButtonItem>[
      if (range != null && range.start != range.end)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: hideAnd(selectionController.copySelectionToClipboard),
        ),
      if (linkDestination != null)
        ContextMenuButtonItem(
          label: 'Copy link',
          onPressed: hideAnd(
            () => Clipboard.setData(ClipboardData(text: linkDestination)),
          ),
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed:
            hideAnd(() => selectionController.selectAll(widget.document)),
      ),
      if (onCopyPlainText != null && widget.showCopyAllInContextMenu)
        ContextMenuButtonItem(
          label: 'Copy all',
          onPressed: hideAnd(onCopyPlainText),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final gestureDetectorWrap = MarkdownSelectionGestureDetector(
      selectionController: widget.selectionController,
      selectionFocusNode: _selectionFocusNode,
      isSelectable: widget.isSelectable,
      scrollableKey: widget.scrollableKey,
      scrollController: widget.scrollController,
      onSecondaryPointerDown: _handleSecondaryPointerDown,
      hitTestPosition: widget.hitTestPosition,
      hitTestExactTextPosition: widget.hitTestExactTextPosition,
      selectWordAt: widget.selectWordAt,
      selectBlockAt: widget.selectBlockAt,
      selectSelectionUnitAt: widget.selectSelectionUnitAt,
      additionalAutoScrollTargets: widget.additionalAutoScrollTargets,
      child: widget.child,
    );

    final tapRegion = TapRegion(
      groupId: this,
      onTapOutside: (_) {
        widget.selectionController.clear();
        _selectionFocusNode.unfocus();
        _hideContextMenu();
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
      // Escape closes an open menu first; with no menu, the action is
      // disabled and Escape reaches the scope above to clear the selection.
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: _HideContextMenuAction(_contextMenuController),
          },
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (_) {
              _hideContextMenu();
              return false;
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if ((event.buttons & kSecondaryMouseButton) == 0) {
                  _hideContextMenu();
                }
                if (!_selectionFocusNode.hasFocus) {
                  _selectionFocusNode.requestFocus();
                }
              },
              child: tapRegion,
            ),
          ),
        ),
      ),
    );
  }
}

class _HideContextMenuAction extends Action<DismissIntent> {
  _HideContextMenuAction(this.controller);

  final ContextMenuController controller;

  @override
  bool isEnabled(DismissIntent intent) => controller.isShown;

  @override
  void invoke(DismissIntent intent) => controller.remove();
}
