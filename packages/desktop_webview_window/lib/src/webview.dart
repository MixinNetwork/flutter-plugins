import 'dart:ui';

/// Handle custom message from JavaScript in your app.
typedef JavaScriptMessageHandler = void Function(String name, dynamic body);

typedef PromptHandler = String Function(String prompt, String defaultText);

typedef OnHistoryChangedCallback = void Function(
    bool canGoBack, bool canGoForward);

abstract class Webview {
  Future<void> get onClose;

  /// Install a message handler that you can call from your Javascript code.
  ///
  /// available: macOS (10.10+)
  void registerJavaScriptMessageHandler(
      String name, JavaScriptMessageHandler handler);

  /// available: macOS
  void unregisterJavaScriptMessageHandler(String name);

  /// available: macOS
  void setPromptHandler(PromptHandler? handler);

  /// available: macOS, Windows
  void launch(String url);

  /// change webview theme.
  ///
  /// available: macOS (Brightness.dark only 10.14+)
  void setBrightness(Brightness? brightness);

  /// available: Windows, Linux, macOS
  void addScriptToExecuteOnDocumentCreated(String javaScript);

  /// Append a string to the webview's user-agent.
  ///
  /// available: macOS, Windows, Linux
  Future<void> setApplicationNameForUserAgent(String applicationName);

  /// Navigate to the previous page in the history.
  /// available: Windows
  Future<void> back();

  /// Navigate to the next page in the history.
  /// available: Windows
  Future<void> forward();

  /// Reload the current page.
  /// available: Windows
  Future<void> reload();

  /// Register a callback that will be invoked when the webview history changes.
  /// available: Windows.
  void setOnHistoryChangedCallback(OnHistoryChangedCallback? callback);
}
