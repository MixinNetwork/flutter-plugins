import 'dart:ui';

/// Handle custom message from JavaScript in your app.
typedef JavaScriptMessageHandler = void Function(String name, dynamic body);

typedef PromptHandler = String Function(String prompt, String defaultText);

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

  /// available: Windows, Linux
  void addScriptToExecuteOnDocumentCreated(String javaScript);
}
