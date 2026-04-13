import 'package:flutter/material.dart';

import '../render/markdown_document_view.dart';
import '../selection/selection_controller.dart';
import 'markdown_controller.dart';
import 'markdown_theme.dart';
import 'markdown_types.dart';

class MarkdownWidget extends StatefulWidget {
  const MarkdownWidget({
    super.key,
    this.data,
    this.controller,
    this.theme,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.selectable = true,
    this.enableCopyFullDocumentShortcut = true,
    this.showCopyAllInContextMenu = true,
    this.selectionController,
    this.padding,
    this.onTapLink,
    this.imageBuilder,
    this.contextMenuBuilder,
  }) : assert(
          (data == null) != (controller == null),
          'Provide exactly one of data or controller.',
        );

  final String? data;
  final MarkdownController? controller;
  final MarkdownThemeData? theme;
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final bool selectable;
  final bool enableCopyFullDocumentShortcut;
  final bool showCopyAllInContextMenu;
  final MarkdownSelectionController? selectionController;
  final EdgeInsetsGeometry? padding;
  final MarkdownTapLinkCallback? onTapLink;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownContextMenuBuilder? contextMenuBuilder;

  @override
  State<MarkdownWidget> createState() => _MarkdownWidgetState();
}

typedef MarkownWidget = MarkdownWidget;

class _MarkdownWidgetState extends State<MarkdownWidget> {
  MarkdownController? _ownedController;
  late final MarkdownSelectionController _fallbackSelectionController;

  MarkdownController get _effectiveController =>
      widget.controller ?? _ownedController!;

  MarkdownSelectionController? get _effectiveSelectionController =>
      widget.selectable
          ? (widget.selectionController ?? _fallbackSelectionController)
          : null;

  @override
  void initState() {
    super.initState();
    _fallbackSelectionController = MarkdownSelectionController();
    if (widget.controller == null) {
      _ownedController = MarkdownController(data: widget.data ?? '');
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null && widget.controller != null) {
        _ownedController?.dispose();
        _ownedController = null;
      } else if (oldWidget.controller != null && widget.controller == null) {
        _ownedController = MarkdownController(data: widget.data ?? '');
      }
    }
    if (widget.controller == null && oldWidget.data != widget.data) {
      _ownedController?.setData(widget.data ?? '');
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    _fallbackSelectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inheritedTheme = MarkdownTheme.of(context);
    final resolvedTheme = (widget.theme ?? inheritedTheme).copyWith(
      padding: widget.padding ?? (widget.theme ?? inheritedTheme).padding,
    );
    return MarkdownTheme(
      data: resolvedTheme,
      child: Builder(
        builder: (context) {
          final theme = MarkdownTheme.of(context);
          final selectionController = _effectiveSelectionController;
          final animation = selectionController == null
              ? _effectiveController.documentListenable
              : Listenable.merge(
                  <Listenable>[
                    _effectiveController.documentListenable,
                    selectionController,
                  ],
                );
          return TextSelectionTheme(
            data: TextSelectionThemeData(selectionColor: theme.selectionColor),
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                selectionController
                    ?.attachDocument(_effectiveController.document);
                return MarkdownDocumentView(
                  document: _effectiveController.document,
                  theme: theme,
                  scrollController: widget.scrollController,
                  physics: widget.physics,
                  shrinkWrap: widget.shrinkWrap,
                  selectable: widget.selectable,
                  selectionController: selectionController,
                  onCopyPlainText: () {
                    _effectiveController.copyPlainTextToClipboard();
                  },
                  enableCopyFullDocumentShortcut:
                      widget.enableCopyFullDocumentShortcut,
                  showCopyAllInContextMenu: widget.showCopyAllInContextMenu,
                  onTapLink: widget.onTapLink,
                  imageBuilder: widget.imageBuilder,
                  contextMenuBuilder: widget.contextMenuBuilder,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
