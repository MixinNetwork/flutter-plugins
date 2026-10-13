import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'title_bar_runtime.dart';

import 'message_channel.dart';
import 'title_bar_state.dart';

const _channel = ClientMessageChannel();

/// runs the title bar
/// title bar is a widget that displays the title of the webview window
/// return true if the args is matchs the title bar
///
/// Call this from main before creating any webview windows to enable their
/// title-bar controls.
///
/// Without this hook, web content fills the window.
///
/// [builder] custom TitleBar widget builder.
/// can use [TitleBarWebViewController] to controller the WebView
/// use [TitleBarWebViewState] to triger the title bar status.
///
bool runWebViewTitleBarWidget(
  List<String> args, {
  WidgetBuilder? builder,
  Color? backgroundColor,
}) {
  titleBarInitialized = true;
  if (args.isEmpty || args[0] != 'web_view_title_bar') {
    titleBarHookRegistered = true;
    return false;
  }
  if (args.length < 2) {
    return false;
  }
  if (args[1] == 'shared') {
    WidgetsFlutterBinding.ensureInitialized();
    runWidget(
      SharedTitleBarViews(
        builder: builder ?? _defaultTitleBar,
        backgroundColor: backgroundColor,
      ),
    );
    return true;
  }
  final webViewId = int.tryParse(args[1]);
  if (webViewId == null) {
    return false;
  }
  final titleBarTopPadding = int.tryParse(args.length > 2 ? args[2] : '0') ?? 0;
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    _TitleBarApp(
      webViewId: webViewId,
      titleBarTopPadding: titleBarTopPadding,
      backgroundColor: backgroundColor,
      builder: builder ?? _defaultTitleBar,
    ),
  );
  return true;
}

/// Internal root for the dedicated toolbar isolate. Browser IDs are not view IDs.
@visibleForTesting
class SharedTitleBarViews extends StatefulWidget {
  const SharedTitleBarViews({
    super.key,
    required this.builder,
    this.backgroundColor,
  });

  final WidgetBuilder builder;
  final Color? backgroundColor;

  @override
  State<SharedTitleBarViews> createState() => _SharedTitleBarViewsState();
}

class _SharedTitleBarViewsState extends State<SharedTitleBarViews>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('desktop_webview_window/titlebars');
  Map<int, Map<Object?, Object?>> _views = {};
  bool _refreshing = false;
  bool _refreshAgain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'viewsChanged') {
        await _refresh();
      }
    });
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final snapshot = await _channel.invokeListMethod<dynamic>('getViews');
        if (!mounted) return;
        final views = <int, Map<Object?, Object?>>{};
        for (final item in snapshot ?? const []) {
          final descriptor = Map<Object?, Object?>.from(item as Map);
          views[descriptor['viewId'] as int] = descriptor;
        }
        setState(() => _views = views);
      } while (_refreshAgain && mounted);
    } on PlatformException catch (error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'desktop_webview_window',
          context: ErrorDescription('loading toolbar views'),
        ),
      );
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeMetrics() {
    // AddView/RemoveView and the native snapshot can arrive in either order.
    // Never replace PlatformDispatcher.onMetricsChanged: the binding owns it.
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViewCollection(
      views: [
        for (final view in WidgetsBinding.instance.platformDispatcher.views)
          if (_views[view.viewId] case final descriptor?)
            View(
              key: ValueKey(view.viewId),
              view: view,
              child: _TitleBarApp(
                key: ValueKey(descriptor['webViewId']),
                webViewId: descriptor['webViewId'] as int,
                titleBarTopPadding:
                    descriptor['titleBarTopPadding'] as int? ?? 0,
                builder: widget.builder,
                backgroundColor: widget.backgroundColor,
              ),
            ),
      ],
    );
  }
}

mixin TitleBarWebViewController {
  static TitleBarWebViewController of(BuildContext context) {
    final state = context.findAncestorStateOfType<_TitleBarAppState>();
    assert(
      state != null,
      'only can find TitleBarWebViewController in widget which run from runWebViewTitleBarWidget',
    );
    return state!;
  }

  int get _webViewId;

  /// navigate back
  void back() {
    _channel.invokeMethod('onBackPressed', {'webViewId': _webViewId});
  }

  /// navigate forward
  void forward() {
    _channel.invokeMethod('onForwardPressed', {'webViewId': _webViewId});
  }

  /// reload the webview
  void reload() {
    _channel.invokeMethod('onRefreshPressed', {'webViewId': _webViewId});
  }

  /// stop loading the webview
  void stop() {
    _channel.invokeMethod('onStopPressed', {'webViewId': _webViewId});
  }

  /// close the webview
  void close() {
    _channel.invokeMethod('onClosePressed', {'webViewId': _webViewId});
  }
}

class TitleBarWebViewState extends InheritedWidget {
  const TitleBarWebViewState({
    super.key,
    required super.child,
    required this.isLoading,
    required this.canGoBack,
    required this.canGoForward,
    required this.url,
  });

  final bool isLoading;
  final bool canGoBack;
  final bool canGoForward;
  final String? url;

  static TitleBarWebViewState of(BuildContext context) {
    final TitleBarWebViewState? result =
        context.dependOnInheritedWidgetOfExactType<TitleBarWebViewState>();
    assert(result != null, 'No WebViewState found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(TitleBarWebViewState oldWidget) {
    return isLoading != oldWidget.isLoading ||
        canGoBack != oldWidget.canGoBack ||
        canGoForward != oldWidget.canGoForward ||
        url != oldWidget.url;
  }
}

class _TitleBarApp extends StatefulWidget {
  const _TitleBarApp({
    super.key,
    required this.webViewId,
    required this.titleBarTopPadding,
    required this.builder,
    this.backgroundColor,
  });

  final int webViewId;

  final int titleBarTopPadding;

  final WidgetBuilder builder;

  final Color? backgroundColor;

  @override
  State<_TitleBarApp> createState() => _TitleBarAppState();
}

class _TitleBarAppState extends State<_TitleBarApp>
    with TitleBarWebViewController {
  bool _canGoBack = false;
  bool _canGoForward = false;

  bool _isLoading = false;

  String? _url;

  @override
  int get _webViewId => widget.webViewId;

  @override
  void initState() {
    super.initState();
    _channel.addMessageHandler(_handleMessage);
    unawaited(
      _channel.invokeMethod('onTitleBarReady', {'webViewId': _webViewId}),
    );
  }

  Future<dynamic> _handleMessage(MethodCall call) async {
    final args = call.arguments as Map;
    final webViewId = args['webViewId'] as int;
    if (!mounted || webViewId != widget.webViewId) {
      return;
    }
    switch (call.method) {
      case "onHistoryChanged":
        setState(() {
          _canGoBack = args['canGoBack'] as bool;
          _canGoForward = args['canGoForward'] as bool;
        });
        break;
      case "onNavigationStarted":
        setState(() {
          _isLoading = true;
        });
        break;
      case "onNavigationCompleted":
        setState(() {
          _isLoading = false;
        });
        break;
      case "onUrlRequested":
        setState(() {
          _url = args['url'] as String;
        });
        break;
    }
  }

  @override
  void dispose() {
    _channel.removeMessageHandler(_handleMessage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color:
            widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: EdgeInsets.only(top: widget.titleBarTopPadding.toDouble()),
          child: TitleBarWebViewState(
            isLoading: _isLoading,
            canGoBack: _canGoBack,
            canGoForward: _canGoForward,
            url: _url,
            child: Builder(builder: widget.builder),
          ),
        ),
      ),
    );
  }
}

Widget _defaultTitleBar(BuildContext context) {
  final state = TitleBarWebViewState.of(context);
  final controller = TitleBarWebViewController.of(context);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 16,
        iconSize: 16,
        onPressed: !state.canGoBack ? null : controller.back,
        icon: const Icon(Icons.arrow_back),
      ),
      IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 16,
        iconSize: 16,
        onPressed: !state.canGoForward ? null : controller.forward,
        icon: const Icon(Icons.arrow_forward),
      ),
      if (state.isLoading)
        IconButton(
          padding: EdgeInsets.zero,
          splashRadius: 16,
          iconSize: 16,
          onPressed: controller.stop,
          icon: const Icon(Icons.close),
        )
      else
        IconButton(
          padding: EdgeInsets.zero,
          splashRadius: 16,
          iconSize: 16,
          onPressed: controller.reload,
          icon: const Icon(Icons.refresh),
        ),
      const Spacer(),
    ],
  );
}
