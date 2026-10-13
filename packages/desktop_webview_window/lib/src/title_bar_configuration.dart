import 'package:flutter/material.dart';

import 'webview.dart';

/// Rebuilt when the browser's navigation state or titlebar theme changes.
typedef WebviewTitleBarBuilder = Widget Function(
  BuildContext context,
  Webview webview,
  WebviewNavigationState state,
);

/// Flutter toolbar configuration, independent of the system titlebar.
///
/// A window without an override follows the host configuration. An explicit
/// configuration replaces it; a null theme still follows the host theme.
class WebviewTitleBarConfiguration {
  const WebviewTitleBarConfiguration({
    this.height = 40,
    this.topPadding,
    this.builder,
    this.theme,
    this.backgroundColor,
  })  : assert(height > 0),
        assert(topPadding == null || topPadding >= 0);

  /// Creates a browser without a Flutter toolbar or an additional Flutter view.
  const WebviewTitleBarConfiguration.none()
      : height = 0,
        topPadding = 0,
        builder = null,
        theme = null,
        backgroundColor = null;

  /// Toolbar content height in logical pixels, excluding [topPadding].
  final int height;

  /// Defaults to 24 on macOS with a system titlebar, and zero elsewhere.
  /// Always omitted when the Flutter toolbar is disabled.
  final int? topPadding;

  /// Null uses the built-in back, forward, reload and stop buttons.
  final WebviewTitleBarBuilder? builder;
  final ThemeData? theme;
  final Color? backgroundColor;

  bool get enabled => height > 0;
}
