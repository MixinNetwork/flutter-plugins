import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'title_bar_configuration.dart';
import 'title_bar_runtime.dart';
import 'webview.dart';
import 'webview_impl.dart';

const _control = MethodChannel('desktop_webview_window/titlebars');

/// Convenience entrypoint for an application with a runner-owned main view.
///
/// On macOS, create that view with
/// `DesktopWebviewWindowPlugin.createMainViewController()` in the runner.
/// Applications that already own their views should use [WebviewTitleBarHost]
/// with `runWidget` instead.
void runWebviewWindowApp(
  Widget app, {
  WebviewTitleBarConfiguration? titleBar,
}) {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(WebviewWindowApp(
    titleBar: titleBar,
    child: app,
  ));
}

/// Convenience root for a runner-owned main view. Mount with `runWidget`.
///
/// [child] is ordinary application content. For a child that already creates
/// its own views, use [WebviewTitleBarHost] instead.
class WebviewWindowApp extends StatefulWidget {
  const WebviewWindowApp({
    super.key,
    required this.child,
    this.titleBar,
  });

  final Widget child;
  final WebviewTitleBarConfiguration? titleBar;

  @override
  State<WebviewWindowApp> createState() => _WebviewWindowAppState();
}

class _WebviewWindowAppState extends State<WebviewWindowApp>
    with WidgetsBindingObserver {
  int? _mainViewId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadMainView());
  }

  Future<void> _loadMainView() async {
    try {
      final id = await _control.invokeMethod<int>('getMainView', {
        'mainViewId':
            WidgetsBinding.instance.platformDispatcher.implicitView?.viewId,
      });
      if (id == null) {
        throw StateError('No runner-owned main view. Use WebviewTitleBarHost '
            'for an application that creates its own windows.');
      }
      if (mounted) setState(() => _mainViewId = id);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'desktop_webview_window',
        context: ErrorDescription('loading the runner-owned main view'),
      ));
    }
  }

  @override
  void didChangeMetrics() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return WebviewTitleBarHost(
      titleBar: widget.titleBar ?? const WebviewTitleBarConfiguration(),
      child: ViewCollection(views: [
        for (final view in views)
          if (view.viewId == _mainViewId)
            View(key: ValueKey(view.viewId), view: view, child: widget.child),
      ]),
    );
  }
}

/// Composes browser toolbar views with the application's existing widget tree.
///
/// Install exactly one host per engine, above any windows that can outlive the
/// main window. With `runWidget`, [child] must provide its own views. Inside an
/// existing view (for example with `runApp`), side views use [ViewAnchor].
/// Native multi-view support must already be configured on macOS.
class WebviewTitleBarHost extends StatefulWidget {
  const WebviewTitleBarHost({
    super.key,
    required this.child,
    this.titleBar = const WebviewTitleBarConfiguration(),
  });

  final Widget child;

  /// Defaults for browsers without an override. Builder and theme updates apply
  /// to existing toolbars; height, padding and enabled state apply at creation.
  final WebviewTitleBarConfiguration titleBar;

  @override
  State<WebviewTitleBarHost> createState() => _WebviewTitleBarHostState();
}

class _WebviewTitleBarHostState extends State<WebviewTitleBarHost>
    with WidgetsBindingObserver {
  Map<int, Map<Object?, Object?>> _views = {};
  bool _refreshing = false;
  bool _refreshAgain = false;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    if (titleBarInitialization != null) {
      throw StateError(
          'Only one WebviewTitleBarHost may be mounted per engine');
    }
    defaultTitleBarConfiguration.value = widget.titleBar;
    _initialization = _control.invokeMethod<void>('initialize', {
      // Native borrowing needs the actual engine, not a test binding's ID.
      'engineId': PlatformDispatcher.instance.engineId,
    });
    titleBarInitialization = _initialization;
    WidgetsBinding.instance.addObserver(this);
    _control.setMethodCallHandler((call) async {
      if (call.method == 'viewsChanged') await _refresh();
    });
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(WebviewTitleBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    defaultTitleBarConfiguration.value = widget.titleBar;
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      await _initialization;
      do {
        _refreshAgain = false;
        final snapshot = await _control.invokeListMethod<dynamic>('getViews');
        if (!mounted) return;
        final views = <int, Map<Object?, Object?>>{};
        for (final item in snapshot ?? const []) {
          final descriptor = Map<Object?, Object?>.from(item as Map);
          views[descriptor['viewId'] as int] = descriptor;
        }
        setState(() => _views = views);
      } while (_refreshAgain && mounted);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'desktop_webview_window',
        context: ErrorDescription('loading toolbar views'),
      ));
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeMetrics() {
    // AddView/RemoveView and the native snapshot can arrive in either order.
    setState(() {});
  }

  @override
  void dispose() {
    if (_initialization != null &&
        identical(titleBarInitialization, _initialization)) {
      titleBarInitialization = null;
      defaultTitleBarConfiguration.value = const WebviewTitleBarConfiguration();
      _control.setMethodCallHandler(null);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchored = View.maybeOf(context) != null;
    return ValueListenableBuilder<Map<int, WebviewImpl>>(
      valueListenable: titleBarWebviews,
      child: widget.child,
      builder: (context, browsers, child) {
        final toolbars = <Widget>[
          for (final view in WidgetsBinding.instance.platformDispatcher.views)
            if (_views[view.viewId] case final descriptor?)
              if (browsers[descriptor['webViewId']] case final webview?)
                View(
                  key: ValueKey(view.viewId),
                  view: view,
                  child: _TitleBarApp(
                    webview: webview,
                    topPadding: descriptor['titleBarTopPadding'] as int? ?? 0,
                  ),
                ),
        ];
        return anchored
            ? ViewAnchor(view: ViewCollection(views: toolbars), child: child!)
            : ViewCollection(views: [child!, ...toolbars]);
      },
    );
  }
}

class _TitleBarApp extends StatelessWidget {
  const _TitleBarApp({required this.webview, required this.topPadding});

  final WebviewImpl webview;
  final int topPadding;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([webview, webview.navigationState]),
        builder: (context, _) {
          final configuration = webview.effectiveTitleBarConfiguration;
          final state = webview.navigationState.value;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: webview.effectiveTitleBarTheme,
            home: Builder(
                builder: (context) => Material(
                      color: configuration.backgroundColor ??
                          Theme.of(context).scaffoldBackgroundColor,
                      child: Padding(
                        padding: EdgeInsets.only(top: topPadding.toDouble()),
                        child: Builder(
                          builder: (context) => (configuration.builder ??
                              _defaultTitleBar)(context, webview, state),
                        ),
                      ),
                    )),
          );
        },
      );
}

Widget _defaultTitleBar(
        BuildContext context, Webview webview, WebviewNavigationState state) =>
    Row(
      children: [
        IconButton(
          tooltip: 'Back',
          padding: EdgeInsets.zero,
          splashRadius: 16,
          iconSize: 16,
          onPressed: state.canGoBack ? webview.back : null,
          icon: const Icon(Icons.arrow_back),
        ),
        IconButton(
          tooltip: 'Forward',
          padding: EdgeInsets.zero,
          splashRadius: 16,
          iconSize: 16,
          onPressed: state.canGoForward ? webview.forward : null,
          icon: const Icon(Icons.arrow_forward),
        ),
        IconButton(
          tooltip: state.isLoading ? 'Stop' : 'Reload',
          padding: EdgeInsets.zero,
          splashRadius: 16,
          iconSize: 16,
          onPressed: state.isLoading ? webview.stop : webview.reload,
          icon: Icon(state.isLoading ? Icons.close : Icons.refresh),
        ),
        const Spacer(),
      ],
    );
