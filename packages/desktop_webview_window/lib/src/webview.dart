import 'package:desktop_webview_window/src/cookie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeData;

/// Handle custom message from JavaScript in your app.
typedef JavaScriptMessageHandler = void Function(String name, dynamic body);

typedef PromptHandler = String Function(String prompt, String defaultText);

typedef OnHistoryChangedCallback = void Function(
    bool canGoBack, bool canGoForward);

/// Callback when WebView start to load a URL.
/// [url] is the URL string.
typedef OnUrlRequestCallback = bool Function(String url);

/// Callback when WebView receives a web message
/// [message] constains the webmessage
typedef OnWebMessageReceivedCallback = void Function(String message);

/// Current browser navigation state, shared by the application and toolbar.
@immutable
class WebviewNavigationState {
  const WebviewNavigationState({
    this.canGoBack = false,
    this.canGoForward = false,
    this.isLoading = false,
    this.url,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;

  /// The most recently requested URL. This is not a committed-navigation URL.
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is WebviewNavigationState &&
      canGoBack == other.canGoBack &&
      canGoForward == other.canGoForward &&
      isLoading == other.isLoading &&
      url == other.url;

  @override
  int get hashCode => Object.hash(canGoBack, canGoForward, isLoading, url);
}

abstract class Webview {
  Future<void> get onClose;

  ValueListenable<WebviewNavigationState> get navigationState;

  ///  true if the webview is currently loading a page.
  ValueListenable<bool> get isNavigating;

  /// Install a message handler that you can call from your Javascript code.
  ///
  /// available: macOS (10.10+)
  void registerJavaScriptMessageHandler(
    String name,
    JavaScriptMessageHandler handler,
  );

  /// available: macOS
  void unregisterJavaScriptMessageHandler(String name);

  /// available: macOS
  void setPromptHandler(PromptHandler? handler);

  /// Navigates to the given URL.
  void launch(String url, {bool triggerOnUrlRequestEvent = true});

  /// Overrides this window's toolbar theme and native titlebar brightness.
  /// Pass null to resume following the window configuration or host theme.
  /// Native titlebar synchronization is supported on macOS and Windows.
  Future<void> setTitleBarTheme(ThemeData? theme);

  /// Changes native window appearance on macOS and Windows.
  /// Pass null to restore the platform default. Does not theme Flutter widgets.
  /// macOS may also apply this appearance to web content.
  void setBrightness(Brightness? brightness);

  void addScriptToExecuteOnDocumentCreated(String javaScript);

  /// Append a string to the webview's user-agent.
  Future<void> setApplicationNameForUserAgent(String applicationName);

  /// Navigate to the previous page in the history.
  Future<void> back();

  /// Navigate to the next page in the history.
  Future<void> forward();

  /// Show or hide webview window
  Future<void> setWebviewWindowVisibility(bool visible);

  /// Move and Resize the webview window
  Future<void> moveWebviewWindow(int left, int top, int width, int height);

  /// Activates the webview window (giving it the focus)
  Future<void> bringToForeground({bool maximized = false});

  /// get position, extents and maximization info of the webview window
  Future<Map<dynamic, dynamic>?> getPositionalParameters();

  /// Reload the current page.
  Future<void> reload();

  /// Stop all navigations and pending resource fetches.
  Future<void> stop();

  /// Opens the Browser DevTools in a separate window
  Future<void> openDevToolsWindow();

  /// Register a callback that will be invoked when the webview history changes.
  void setOnHistoryChangedCallback(OnHistoryChangedCallback? callback);

  void setOnUrlRequestCallback(OnUrlRequestCallback? callback);

  void addOnWebMessageReceivedCallback(OnWebMessageReceivedCallback callback);

  void removeOnWebMessageReceivedCallback(
    OnWebMessageReceivedCallback callback,
  );

  void removeAllWebMessageReceivedCallback();

  /// Close the web view window.
  void close();

  /// evaluate JavaScript in the web view.
  Future<String?> evaluateJavaScript(String javaScript);

  /// post a web message as String to the top level document in this WebView
  Future<void> postWebMessageAsString(String webMessage);

  /// post a web message as JSON to the top level document in this WebView
  Future<void> postWebMessageAsJson(String webMessage);

  Future<List<WebviewCookie>> getAllCookies();
}
