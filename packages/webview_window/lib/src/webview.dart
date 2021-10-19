import 'dart:ui';

/// Handle custom message from JavaScript in your app.
typedef JavaScriptMessageHandler = void Function(String name, dynamic body);

typedef PromptHandler = String Function(String prompt, String defaultText);

abstract class Webview {
  /// Install a message handler that you can call from your Javascript code.
  /// @availabe macOS 10.10+
  void registerJavaScriptMessageHandler(
      String name, JavaScriptMessageHandler handler);

  void unregisterJavaScriptMessageHandler(String name);

  void setPromptHandler(PromptHandler? handler);

  void launch(String url);

  /// change webview theme.
  ///
  /// Brightness.dark only availabe on macOS 10.14+
  void setBrightness(Brightness? brightness);
}
