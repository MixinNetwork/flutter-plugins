import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'src/create_configuration.dart';
import 'src/title_bar_configuration.dart';
import 'src/title_bar_runtime.dart';
import 'src/webview.dart';
import 'src/webview_impl.dart';

export 'src/create_configuration.dart';
export 'src/title_bar.dart';
export 'src/title_bar_configuration.dart';
export 'src/webview.dart';

class WebviewWindow {
  static const MethodChannel _channel = MethodChannel('webview_window');

  static bool _inited = false;
  static int _pendingCreates = 0;
  static final Set<int> _closedDuringCreate = {};
  static void _init() {
    if (_inited) {
      return;
    }
    _inited = true;
    _channel.setMethodCallHandler((call) async {
      try {
        return await _handleMethodCall(call);
      } catch (e, s) {
        debugPrint("method: ${call.method} args: ${call.arguments}");
        debugPrint('handleMethodCall error: $e $s');
      }
    });
  }

  /// Check if WebView runtime is available on the current devices.
  static Future<bool> isWebviewAvailable() async {
    if (Platform.isWindows) {
      final ret = await _channel.invokeMethod<bool>('isWebviewAvailable');
      return ret == true;
    }
    return true;
  }

  /// Creates a browser using the host defaults unless [titleBar] is supplied.
  /// A Flutter toolbar requires a mounted WebviewTitleBarHost. Use
  /// WebviewTitleBarConfiguration.none() for ordinary runApp without a host.
  static Future<Webview> create({
    CreateConfiguration? configuration,
    WebviewTitleBarConfiguration? titleBar,
  }) async {
    configuration ??= CreateConfiguration.platform();
    final arguments = configuration.toMap();
    final defaults = defaultTitleBarConfiguration.value;
    final resolved = titleBar ?? defaults;
    if (resolved.enabled) {
      final initialization = titleBarInitialization;
      if (initialization == null) {
        throw StateError(
          'A Flutter titlebar requires a mounted WebviewTitleBarHost. '
          'Use runWebviewWindowApp, mount the host, or explicitly pass '
          'WebviewTitleBarConfiguration.none().',
        );
      }
      await initialization;
      if (!identical(titleBarInitialization, initialization)) {
        throw StateError(
            'The titlebar host was removed while creating a browser');
      }
    }
    _init();
    arguments['useTitleBar'] = resolved.enabled;
    arguments['titleBarHeight'] = resolved.height;
    arguments['titleBarTopPadding'] =
        !resolved.enabled || !configuration.showSystemTitleBar
            ? 0
            : resolved.topPadding ?? (Platform.isMacOS ? 24 : 0);
    final theme = resolved.theme ?? defaults.theme;
    if (theme != null) arguments['titleBarBrightness'] = theme.brightness.index;
    _pendingCreates++;
    try {
      final viewId = await _channel.invokeMethod<int>('create', arguments);
      if (viewId == null) {
        throw StateError('Native create returned no browser ID');
      }
      final webview =
          WebviewImpl(viewId, _channel, titleBarConfiguration: titleBar);
      if (_closedDuringCreate.remove(viewId)) {
        webview.onClosed();
      } else {
        titleBarWebviews.value = {...titleBarWebviews.value, viewId: webview};
        await webview.syncTitleBarBrightness();
      }
      return webview;
    } finally {
      _pendingCreates--;
      if (_pendingCreates == 0) _closedDuringCreate.clear();
    }
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map;
    final viewId = args['id'] as int;
    final webview = titleBarWebviews.value[viewId];
    if (webview == null) {
      if (call.method == 'onWindowClose' && _pendingCreates > 0) {
        _closedDuringCreate.add(viewId);
      }
      return;
    }
    switch (call.method) {
      case "onWindowClose":
        titleBarWebviews.value = {...titleBarWebviews.value}..remove(viewId);
        webview.onClosed();
        break;
      case "onJavaScriptMessage":
        webview.onJavaScriptMessage(args['name'], args['body']);
        break;
      case "runJavaScriptTextInputPanelWithPrompt":
        return webview.onRunJavaScriptTextInputPanelWithPrompt(
          args['prompt'],
          args['defaultText'],
        );
      case "onHistoryChanged":
        webview.onHistoryChanged(args['canGoBack'], args['canGoForward']);
        break;
      case "onNavigationStarted":
        webview.onNavigationStarted();
        break;
      case "onUrlRequested":
        final url = args['url'] as String;
        final ret = webview.notifyUrlChanged(url);
        return ret;
      case "onWebMessageReceived":
        final message = args['message'] as String;
        webview.notifyWebMessageReceived(message);
        break;
      case "onNavigationCompleted":
        webview.onNavigationCompleted();
        break;
      default:
        return;
    }
  }

  /// Clear all cookies and storage.
  static Future<void> clearAll({
    String userDataFolderWindows = 'webview_window_WebView2',
  }) async {
    await _channel.invokeMethod('clearAll');

    // FIXME(boyan01) Move the logic to windows platform if WebView2 provider a way to clean caches.
    // https://docs.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder#create-user-data-folders
    if (Platform.isWindows) {
      final Directory webview2Dir;
      if (p.isAbsolute(userDataFolderWindows)) {
        webview2Dir = Directory(userDataFolderWindows);
      } else {
        webview2Dir = Directory(
          p.join(p.dirname(Platform.resolvedExecutable), userDataFolderWindows),
        );
      }

      if (await (webview2Dir.exists())) {
        for (var i = 0; i <= 4; i++) {
          try {
            await webview2Dir.delete(recursive: true);
            break;
          } catch (e) {
            debugPrint("delete cache failed. retring.... $e");
          }
          // wait to ensure all web window has been closed and file handle has been release.
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
  }
}
