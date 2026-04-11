import 'package:flutter/widgets.dart';

import '../core/document.dart';
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
