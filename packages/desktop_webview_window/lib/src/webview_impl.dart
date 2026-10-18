import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/src/cookie.dart';
import 'package:flutter/foundation.dart';

import 'js_bridge.dart';
import 'native_transport.dart';
import 'webview.dart';

class WebviewImpl extends Webview {
  WebviewImpl(this.id, {required int windowHandle, NativeTransport? transport})
      : _windowHandle = windowHandle,
        _transport = transport ?? NativeTransport.instance;

  @override
  final int id;

  final NativeTransport _transport;

  final Map<String, JavaScriptMessageHandler> _javaScriptHandlers = {};

  bool _closed = false;
  bool _closing = false;

  PromptHandler? _promptHandler;

  final _closeCompleter = Completer<void>();

  OnUrlRequestCallback? _onUrlRequestCallback;

  final _navigation = ValueNotifier(const WebviewNavigationState());

  final int _windowHandle;

  @override
  ValueListenable<WebviewNavigationState> get navigationState => _navigation;

  bool get isClosed => _closed;

  @override
  Future<void> setBrightness(Brightness? brightness) async {
    if (!(Platform.isMacOS || Platform.isWindows)) {
      throw UnsupportedError('setBrightness is supported on macOS and Windows');
    }
    if (_closed || _closing) return;
    await _invoke('setBrightness', {'brightness': brightness?.index ?? -1});
  }

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  int get nativeWindowHandle => _closed ? 0 : _windowHandle;

  void onClosed() {
    if (_closed) return;
    _closed = true;
    _closing = true;
    _javaScriptHandlers.clear();
    _onUrlRequestCallback = null;
    _promptHandler = null;
    if (_navigation.value.isLoading) {
      _navigation.value = WebviewNavigationState(
        canGoBack: _navigation.value.canGoBack,
        canGoForward: _navigation.value.canGoForward,
        url: _navigation.value.url,
        title: _navigation.value.title,
      );
    }
    _closeCompleter.complete();
  }

  void onJavaScriptMessage(String raw) {
    if (_closed) return;
    final message = decodeJavaScriptMessage(raw);
    if (message == null) return;
    _javaScriptHandlers[message.name]?.call(message.data);
  }

  String onPrompt(String prompt, String defaultText) =>
      _promptHandler?.call(prompt, defaultText) ?? defaultText;

  void onNavigationStateChanged({
    required bool canGoBack,
    required bool canGoForward,
    required bool isLoading,
    String? url,
    String? title,
  }) {
    if (_closed) return;
    _navigation.value = WebviewNavigationState(
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      isLoading: isLoading,
      url: url,
      title: title,
    );
  }

  /// Native code waits for the result before navigating.
  bool decideNavigation(String url) {
    final callback = _onUrlRequestCallback;
    if (_closed || callback == null) return true;
    try {
      return callback(url);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'desktop_webview_window',
        context: ErrorDescription('deciding a navigation'),
      ));
      return true;
    }
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) {
    if (_closed) {
      return Future.error(StateError('Browser $id has been closed'));
    }
    return _transport.invoke<T>(method, {'viewId': id, ...?arguments});
  }

  @override
  void addJavaScriptHandler(String name, JavaScriptMessageHandler handler) {
    if (_closed) throw StateError('Browser $id has been closed');
    _javaScriptHandlers[name] = handler;
  }

  @override
  void removeJavaScriptHandler(String name) {
    _javaScriptHandlers.remove(name);
  }

  @override
  Future<void> postMessage(String name, Object? data) {
    final message = encodeJavaScriptMessage(name, data);
    return _invoke('postJavaScriptMessage', {
      'message': message,
      'script': javaScriptDispatchScript(message),
    });
  }

  @override
  void setPromptHandler(PromptHandler? handler) {
    if (!Platform.isMacOS) {
      throw UnsupportedError('setPromptHandler is supported on macOS only');
    }
    _promptHandler = handler;
  }

  @override
  Future<void> launch(String url, {bool triggerOnUrlRequestEvent = true}) =>
      _invoke('launch', {
        'url': url,
        'triggerOnUrlRequestEvent': triggerOnUrlRequestEvent,
      });

  @override
  Future<void> addScriptToExecuteOnDocumentCreated(String javaScript) {
    if (javaScript.trim().isEmpty) {
      throw ArgumentError.value(javaScript, 'javaScript', 'Must not be empty');
    }
    return _invoke(
        'addScriptToExecuteOnDocumentCreated', {'javaScript': javaScript});
  }

  @override
  Future<void> setApplicationNameForUserAgent(String applicationName) =>
      _invoke('setApplicationNameForUserAgent',
          {'applicationName': applicationName});

  @override
  Future<void> back() => _invoke('back');

  @override
  Future<void> forward() => _invoke('forward');

  @override
  Future<void> reload() => _invoke('reload');

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<void> openDevToolsWindow() {
    if (Platform.isMacOS) {
      throw UnsupportedError(
          'macOS has no public API to open Web Inspector. Debug builds enable '
          'it from Safari\'s Develop menu.');
    }
    return _invoke('openDevToolsWindow');
  }

  @override
  Future<void> setOnUrlRequestCallback(OnUrlRequestCallback? callback) async {
    if (_closed) return;
    final enabled = _onUrlRequestCallback != null;
    _onUrlRequestCallback = callback;
    if (enabled == (callback != null)) return;
    await _invoke('setUrlRequestEnabled', {'enabled': callback != null});
  }

  @override
  Future<void> close() async {
    if (_closed || _closing) return;
    _closing = true;
    try {
      await _transport.invoke('close', {'viewId': id});
    } catch (_) {
      _closing = false;
      rethrow;
    }
  }

  @override
  Future<Object?> evaluateJavaScript(String javaScript) async {
    final result = await _invoke<String>(
        'evaluateJavaScript', {'javaScriptString': javaScript});
    return result == null ? null : jsonDecode(result);
  }

  @override
  Future<List<WebviewCookie>> getAllCookies() async {
    final result = await _invoke<List<Object?>>('getAllCookies');
    return [
      for (final cookie in result ?? const [])
        WebviewCookie.fromJson((cookie as Map).cast<String, dynamic>()),
    ];
  }
}
