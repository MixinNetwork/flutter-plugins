import 'package:flutter/material.dart';

import '../core/document.dart';
import '../selection/selection_controller.dart';
import 'markdown_theme.dart';

typedef MarkdownTapLinkCallback = void Function(
  String destination,
  String? title,
  String label,
);

typedef MarkdownImageBuilder = Widget Function(
  BuildContext context,
  ImageBlock block,
  MarkdownThemeData theme,
);
typedef MarkdownCodeBlockBuilder = Widget Function(
  BuildContext context,
  String code,
  String? language,
  MarkdownThemeData theme,
);

typedef MarkdownBulletBuilder = Widget Function(
  BuildContext context,
  int bulletIndex,
  bool isOrdered,
  int? orderedStart,
  MarkdownTaskListItemState? taskState,
  MarkdownThemeData theme,
);

/// Builds the context menu shown on right click. Pass null as the builder to
/// show no menu; the default is [defaultMarkdownContextMenuBuilder].
typedef MarkdownContextMenuBuilder = Widget Function(
  BuildContext context,
  MarkdownContextMenuDetails details,
);

/// What a [MarkdownContextMenuBuilder] knows about a right click.
@immutable
class MarkdownContextMenuDetails {
  const MarkdownContextMenuDetails({
    required this.anchors,
    required this.buttonItems,
    required this.selectionController,
    required this.hide,
    this.linkDestination,
  });

  /// Where the menu opens: at the pointer.
  final TextSelectionToolbarAnchors anchors;

  /// The default items for the current selection and pointer: Copy when text
  /// is selected, Copy link over a link, Select all, and Copy all when the
  /// widget copies the whole document. Each item closes the menu.
  final List<ContextMenuButtonItem> buttonItems;

  /// The selection, already updated for the right click.
  final MarkdownSelectionController selectionController;

  /// The destination of the link under the pointer, if any.
  final String? linkDestination;

  /// Closes the menu. Custom items call it after their action.
  final VoidCallback hide;
}

/// The platform's text selection toolbar with [MarkdownContextMenuDetails.buttonItems].
Widget defaultMarkdownContextMenuBuilder(
  BuildContext context,
  MarkdownContextMenuDetails details,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: details.anchors,
    buttonItems: details.buttonItems,
  );
}
