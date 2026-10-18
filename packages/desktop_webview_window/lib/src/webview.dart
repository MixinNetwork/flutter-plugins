import 'dart:async';

import 'package:desktop_webview_window/src/cookie.dart';
import 'package:flutter/foundation.dart';

/// Receives `window.desktopWebview.postMessage(name, data)` from the
/// top-level document. [data] is the JSON-decoded value.
///
/// [origin] is the origin of the document that sent the message, serialized
/// as `scheme://host[:port]` (for example `https://example.com`), `file://`
/// for local files, or `null` for opaque origins. The bridge is available to
/// every page the browser navigates to, so check [origin] before acting on a
/// message that needs a trusted page. Messages from iframes are dropped.
typedef JavaScriptMessageHandler = void Function(Object? data, String origin);

typedef PromptHandler = String Function(String prompt, String defaultText);

/// Decides whether the browser may navigate to [url]. Return false to cancel.
/// The navigation waits for the callback, so it must answer synchronously; a
/// callback that throws allows the navigation. Schemes the WebView cannot
/// load, such as `mixin:`, reach the callback too; handle them and return
/// false.
typedef OnUrlRequestCallback = bool Function(String url);

/// Current browser navigation state, the same state native composers receive.
@immutable
class WebviewNavigationState {
  const WebviewNavigationState({
    this.canGoBack = false,
    this.canGoForward = false,
    this.isLoading = false,
    this.url,
    this.title,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;

  /// The URL of the current page.
  final String? url;

  /// The document title of the current page.
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is WebviewNavigationState &&
      canGoBack == other.canGoBack &&
      canGoForward == other.canGoForward &&
      isLoading == other.isLoading &&
      url == other.url &&
      title == other.title;

  @override
  int get hashCode =>
      Object.hash(canGoBack, canGoForward, isLoading, url, title);
}

/// A browser window. Operations complete when native code has applied them and
/// fail with a [PlatformException] when it reports an error. Operations a
/// platform does not support throw [UnsupportedError].
abstract class Webview {
  /// Process-wide browser ID. Distinct from any Flutter view ID.
  int get id;

  /// Completes once the native window has closed.
  Future<void> get onClose;

  ValueListenable<WebviewNavigationState> get navigationState;

  /// Native window pointer: `HWND` on Windows, `NSWindow*` on macOS and
  /// `GtkWindow*` on Linux. Returns 0 once the browser has closed.
  ///
  /// The window is owned by this plugin. Other libraries may borrow it to move,
  /// show, hide or focus the window, but must not destroy or retain it beyond
  /// [onClose], and must not replace its delegate or window procedure.
  int get nativeWindowHandle;

  /// Handles `window.desktopWebview.postMessage(name, data)` from the page.
  /// Replaces an existing handler with the same [name].
  void addJavaScriptHandler(String name, JavaScriptMessageHandler handler);

  void removeJavaScriptHandler(String name);

  /// Delivers [data] to listeners added with
  /// `window.desktopWebview.addEventListener(name, listener)`.
  /// [data] must be JSON-encodable.
  Future<void> postMessage(String name, Object? data);

  /// Answers JavaScript `prompt()`. macOS only.
  void setPromptHandler(PromptHandler? handler);

  /// Navigates to the given URL. With [triggerOnUrlRequestEvent] false, this
  /// navigation bypasses the [setOnUrlRequestCallback] decision.
  Future<void> launch(String url, {bool triggerOnUrlRequestEvent = true});

  /// Changes native window appearance, including the default toolbar, on
  /// macOS and Windows. Pass null to restore the platform default. Web content
  /// sees the same preference through `prefers-color-scheme`; the page decides
  /// which colors to render. Windows applies this to the individual WebView,
  /// without changing other windows sharing its profile.
  Future<void> setBrightness(Brightness? brightness);

  Future<void> addScriptToExecuteOnDocumentCreated(String javaScript);

  /// Append a string to the webview's user-agent.
  Future<void> setApplicationNameForUserAgent(String applicationName);

  Future<void> back();

  Future<void> forward();

  Future<void> reload();

  /// Stop all navigations and pending resource fetches.
  Future<void> stop();

  /// Opens the browser developer tools. Windows and Linux.
  Future<void> openDevToolsWindow();

  /// Installs the navigation decision for this browser. Top-level navigations
  /// wait for Dart only while a callback is installed.
  Future<void> setOnUrlRequestCallback(OnUrlRequestCallback? callback);

  /// Requests the window to close. [onClose] completes when it has closed.
  Future<void> close();

  /// Evaluates [javaScript] and returns its JSON-compatible result.
  Future<Object?> evaluateJavaScript(String javaScript);

  Future<List<WebviewCookie>> getAllCookies();
}
