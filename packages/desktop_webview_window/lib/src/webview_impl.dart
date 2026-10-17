import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/src/cookie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeData;
import 'package:flutter/services.dart';

import 'title_bar_configuration.dart';
import 'title_bar_runtime.dart';
import 'webview.dart';

class WebviewImpl extends Webview with ChangeNotifier {
  final int viewId;

  final MethodChannel channel;

  final Map<String, JavaScriptMessageHandler> _javaScriptMessageHandlers = {};

  bool _closed = false;
  bool _closing = false;

  PromptHandler? _promptHandler;

  final _closeCompleter = Completer<void>();

  OnHistoryChangedCallback? _onHistoryChanged;

  final ValueNotifier<bool> _isNavigating = ValueNotifier<bool>(false);

  OnUrlRequestCallback? _onUrlRequestCallback;

  final Set<OnWebMessageReceivedCallback> _onWebMessageReceivedCallbacks = {};

  ThemeData? _titleBarTheme;

  ThemeData? get titleBarTheme => _titleBarTheme;
  Brightness? _appliedTitleBarBrightness;

  final WebviewTitleBarConfiguration? titleBarConfiguration;
  final _navigation = ValueNotifier(const WebviewNavigationState());

  @override
  ValueListenable<WebviewNavigationState> get navigationState => _navigation;

  WebviewTitleBarConfiguration get effectiveTitleBarConfiguration =>
      titleBarConfiguration ?? defaultTitleBarConfiguration.value;

  ThemeData? get effectiveTitleBarTheme =>
      _titleBarTheme ??
      effectiveTitleBarConfiguration.theme ??
      defaultTitleBarConfiguration.value.theme;

  WebviewImpl(this.viewId, this.channel, {this.titleBarConfiguration}) {
    defaultTitleBarConfiguration.addListener(_onDefaultTitleBarThemeChanged);
  }

  void _onDefaultTitleBarThemeChanged() {
    notifyListeners();
    unawaited(
        syncTitleBarBrightness().catchError((Object error, StackTrace stack) {
      FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack));
    }));
  }

  Future<void> syncTitleBarBrightness() async {
    if (_closed || _closing) return;
    final brightness = effectiveTitleBarTheme?.brightness;
    if (brightness == _appliedTitleBarBrightness) return;
    await _setNativeBrightness(brightness);
    _appliedTitleBarBrightness = brightness;
  }

  @override
  Future<void> setTitleBarTheme(ThemeData? theme) async {
    if (_closed || _closing) return;
    _titleBarTheme = theme;
    notifyListeners();
    await syncTitleBarBrightness();
  }

  @override
  Future<void> get onClose => _closeCompleter.future;

  void onClosed() {
    if (_closed) return;
    defaultTitleBarConfiguration.removeListener(_onDefaultTitleBarThemeChanged);
    _closed = true;
    _closing = true;
    _javaScriptMessageHandlers.clear();
    _onWebMessageReceivedCallbacks.clear();
    _onHistoryChanged = null;
    _onUrlRequestCallback = null;
    _promptHandler = null;
    _updateNavigation(isLoading: false);
    _closeCompleter.complete();
  }

  void onJavaScriptMessage(String name, dynamic body) {
    assert(!_closed);
    final handler = _javaScriptMessageHandlers[name];
    assert(handler != null, "handler $name is not registed.");
    handler?.call(name, body);
  }

  String onRunJavaScriptTextInputPanelWithPrompt(
    String prompt,
    String defaultText,
  ) {
    assert(!_closed);
    return _promptHandler?.call(prompt, defaultText) ?? defaultText;
  }

  void onHistoryChanged(bool canGoBack, bool canGoForward) {
    assert(!_closed);
    _updateNavigation(canGoBack: canGoBack, canGoForward: canGoForward);
    _onHistoryChanged?.call(canGoBack, canGoForward);
  }

  void onNavigationStarted() {
    _updateNavigation(isLoading: true);
  }

  bool notifyUrlChanged(String url) {
    _updateNavigation(url: url);
    if (_onUrlRequestCallback != null) {
      return _onUrlRequestCallback!(url);
    } else {
      return true;
    }
  }

  void notifyWebMessageReceived(String message) {
    for (final callback in _onWebMessageReceivedCallbacks) {
      callback(message);
    }
  }

  void onNavigationCompleted() {
    _updateNavigation(isLoading: false);
  }

  void _updateNavigation({
    bool? canGoBack,
    bool? canGoForward,
    bool? isLoading,
    String? url,
  }) {
    final next = WebviewNavigationState(
      canGoBack: canGoBack ?? _navigation.value.canGoBack,
      canGoForward: canGoForward ?? _navigation.value.canGoForward,
      isLoading: isLoading ?? _navigation.value.isLoading,
      url: url ?? _navigation.value.url,
    );
    if (next == _navigation.value) return;
    _navigation.value = next;
    _isNavigating.value = next.isLoading;
  }

  @override
  ValueListenable<bool> get isNavigating => _isNavigating;

  @override
  void registerJavaScriptMessageHandler(
    String name,
    JavaScriptMessageHandler handler,
  ) {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return;
    }
    assert(!_closed);
    if (_closed) {
      return;
    }
    assert(name.isNotEmpty);
    assert(!_javaScriptMessageHandlers.containsKey(name));
    _javaScriptMessageHandlers[name] = handler;
    channel.invokeMethod("registerJavaScriptInterface", {
      "viewId": viewId,
      "name": name,
    });
  }

  @override
  void unregisterJavaScriptMessageHandler(String name) {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return;
    }
    if (_closed) {
      return;
    }
    channel.invokeMethod("unregisterJavaScriptInterface", {
      "viewId": viewId,
      "name": name,
    });
  }

  @override
  void setPromptHandler(PromptHandler? handler) {
    if (!Platform.isMacOS) {
      return;
    }
    _promptHandler = handler;
  }

  @override
  void launch(String url, {bool triggerOnUrlRequestEvent = true}) async {
    await channel.invokeMethod("launch", {
      "url": url,
      "viewId": viewId,
      "triggerOnUrlRequestEvent": triggerOnUrlRequestEvent,
    });
  }

  @override
  void setBrightness(Brightness? brightness) {
    _appliedTitleBarBrightness = brightness;
    unawaited(_setNativeBrightness(brightness));
  }

  Future<void> _setNativeBrightness(Brightness? brightness) async {
    if (_closed || _closing || !(Platform.isMacOS || Platform.isWindows)) {
      return;
    }
    await channel.invokeMethod("setBrightness", {
      "viewId": viewId,
      "brightness": brightness?.index ?? -1,
    });
  }

  @override
  void addScriptToExecuteOnDocumentCreated(String javaScript) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    assert(javaScript.trim().isNotEmpty);
    channel.invokeMethod("addScriptToExecuteOnDocumentCreated", {
      "viewId": viewId,
      "javaScript": javaScript,
    });
  }

  @override
  Future<void> setApplicationNameForUserAgent(String applicationName) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    await channel.invokeMethod("setApplicationNameForUserAgent", {
      "viewId": viewId,
      "applicationName": applicationName,
    });
  }

  @override
  Future<void> forward() {
    return channel.invokeMethod("forward", {"viewId": viewId});
  }

  @override
  Future<void> setWebviewWindowVisibility(bool visible) {
    return channel.invokeMethod("setWebviewWindowVisibility", {
      "viewId": viewId,
      "visible": visible,
    });
  }

  @override
  Future<void> moveWebviewWindow(int left, int top, int width, int height) {
    return channel.invokeMethod("moveWebviewWindow", {
      "viewId": viewId,
      "left": left,
      "top": top,
      "width": width,
      "height": height,
    });
  }

  @override
  Future<void> bringToForeground({bool maximized = false}) {
    return channel.invokeMethod("bringToForeground", {
      "viewId": viewId,
      "maximized": maximized,
    });
  }

  @override
  Future<Map<dynamic, dynamic>?> getPositionalParameters() async {
    return await channel.invokeMethod("getPositionalParameters", {
      "viewId": viewId,
    });
  }

  @override
  Future<void> back() {
    return channel.invokeMethod("back", {"viewId": viewId});
  }

  @override
  Future<void> reload() {
    return channel.invokeMethod("reload", {"viewId": viewId});
  }

  @override
  Future<void> stop() {
    return channel.invokeMethod("stop", {"viewId": viewId});
  }

  @override
  Future<void> openDevToolsWindow() {
    return channel.invokeMethod('openDevToolsWindow', {"viewId": viewId});
  }

  @override
  void setOnHistoryChangedCallback(OnHistoryChangedCallback? callback) {
    _onHistoryChanged = callback;
  }

  @override
  void setOnUrlRequestCallback(OnUrlRequestCallback? callback) {
    _onUrlRequestCallback = callback;
  }

  @override
  void addOnWebMessageReceivedCallback(OnWebMessageReceivedCallback callback) {
    _onWebMessageReceivedCallbacks.add(callback);
  }

  @override
  void removeOnWebMessageReceivedCallback(
    OnWebMessageReceivedCallback callback,
  ) {
    _onWebMessageReceivedCallbacks.remove(callback);
  }

  @override
  void removeAllWebMessageReceivedCallback() {
    _onWebMessageReceivedCallbacks.clear();
  }

  @override
  void close() {
    if (_closed || _closing) {
      return;
    }
    _closing = true;
    channel.invokeMethod("close", {"viewId": viewId}).catchError((
      Object error,
    ) {
      _closing = false;
      FlutterError.reportError(FlutterErrorDetails(exception: error));
    });
  }

  @override
  Future<String?> evaluateJavaScript(String javaScript) async {
    final dynamic result = await channel.invokeMethod("evaluateJavaScript", {
      "viewId": viewId,
      "javaScriptString": javaScript,
    });
    if (result == null || result is String) {
      return result;
    }
    return json.encode(result);
  }

  @override
  Future<void> postWebMessageAsString(String webMessage) async {
    return channel.invokeMethod("postWebMessageAsString", {
      "viewId": viewId,
      "webMessage": webMessage,
    });
  }

  @override
  Future<void> postWebMessageAsJson(String webMessage) async {
    return channel.invokeMethod("postWebMessageAsJson", {
      "viewId": viewId,
      "webMessage": webMessage,
    });
  }

  @override
  Future<List<WebviewCookie>> getAllCookies() async {
    final result = await channel.invokeListMethod<Map>("getAllCookies", {
      "viewId": viewId,
    });

    return result
            ?.map((e) => WebviewCookie.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        [];
  }
}
