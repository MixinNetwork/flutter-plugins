import 'package:flutter/foundation.dart';

import 'title_bar_configuration.dart';
import 'webview_impl.dart';

// Shared with browser instances, including windows without a Flutter toolbar.
final defaultTitleBarConfiguration =
    ValueNotifier<WebviewTitleBarConfiguration>(
        const WebviewTitleBarConfiguration());

// Native view registration can precede the create response. Publishing browser
// handles separately lets the host join the two without a readiness handshake.
final titleBarWebviews = ValueNotifier<Map<int, WebviewImpl>>({});

// Set while the multi-view application root is mounted. Native initialization
// must complete before a browser requests a view on the application engine.
Future<void>? titleBarInitialization;
