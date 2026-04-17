import 'package:flutter/widgets.dart';

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

typedef MarkdownContextMenuBuilder = Widget Function(
  BuildContext context,
  MarkdownSelectionController selectionController,
  List<ContextMenuButtonItem> buttonItems,
  TextSelectionToolbarAnchors anchors,
);
