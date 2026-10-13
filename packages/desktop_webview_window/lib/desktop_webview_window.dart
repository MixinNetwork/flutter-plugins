// You have generated a new plugin project without
// specifying the `--platforms` flag. A plugin project supports no platforms is generated.
// To add platforms, run `flutter create -t plugin --platforms <platforms> .` under the same
// directory. You can also find a detailed instruction on how to add platforms in the `pubspec.yaml` at https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin-platforms.

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'src/create_configuration.dart';
import 'src/message_channel.dart';
import 'src/title_bar_state.dart';
import 'src/title_bar_runtime.dart';
import 'src/webview.dart';
import 'src/webview_impl.dart';

export 'src/create_configuration.dart';
export 'src/title_bar.dart' hide SharedTitleBarViews;
export 'src/webview.dart';

final List<WebviewImpl> _webviews = [];

class WebviewWindow {
  static const MethodChannel _channel = MethodChannel('webview_window');

  static const _otherIsolateMessageHandler = ClientMessageChannel();

  static bool _inited = false;
  static int _pendingCreates = 0;
  static final Set<int> _closedDuringCreate = {};
  static final Map<int, Map<String, Map<String, Object?>>> _titleBarStates = {};

  static Future<void> _sendTitleBarEvent(
    String method,
    Map<String, Object?> args,
  ) async {
    final id = args['webViewId'] as int;
    (_titleBarStates[id] ??= {})[method] = args;
    // Loading-start and loading-complete are one state, not two replay events.
    if (method == 'onNavigationStarted') {
      _titleBarStates[id]!.remove('onNavigationCompleted');
    }
    if (method == 'onNavigationCompleted') {
      _titleBarStates[id]!.remove('onNavigationStarted');
    }
    await _otherIsolateMessageHandler.invokeMethod(method, args);
  }

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
    _otherIsolateMessageHandler.setMessageHandler((call) async {
      try {
        return await _handleOtherIsolateMethodCall(call);
      } catch (e, s) {
        debugPrint('_handleOtherIsolateMethodCall error: $e $s');
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

  static Future<Webview> create({CreateConfiguration? configuration}) async {
    configuration ??= CreateConfiguration.platform();
    _init();
    final arguments = configuration.toMap();
    if (!titleBarInitialized) {
      arguments['titleBarHeight'] = 0;
      arguments['titleBarTopPadding'] = 0;
    }
    _pendingCreates++;
    try {
      final viewId = await _channel.invokeMethod("create", {
        ...arguments,
        'useTitleBar': titleBarHookRegistered && titleBarInitialized,
      }) as int;
      final webview = WebviewImpl(viewId, _channel);
      if (_closedDuringCreate.remove(viewId)) {
        webview.onClosed();
      } else {
        _webviews.add(webview);
      }
      return webview;
    } finally {
      _pendingCreates--;
      if (_pendingCreates == 0) _closedDuringCreate.clear();
    }
  }

  static Future<dynamic> _handleOtherIsolateMethodCall(MethodCall call) async {
    final webViewId = call.arguments['webViewId'] as int;
    final webView = _webviews.cast<WebviewImpl?>().firstWhere(
          (w) => w?.viewId == webViewId,
          orElse: () => null,
        );
    if (webView == null) {
      return;
    }
    switch (call.method) {
      case 'onTitleBarReady':
        final state = _titleBarStates[webViewId];
        if (state != null) {
          await Future.wait([
            for (final entry in List.of(state.entries))
              _otherIsolateMessageHandler.invokeMethod(entry.key, entry.value),
          ]);
        }
        break;
      case 'onBackPressed':
        await webView.back();
        break;
      case 'onForwardPressed':
        await webView.forward();
        break;
      case 'onRefreshPressed':
        await webView.reload();
        break;
      case 'onStopPressed':
        await webView.stop();
        break;
      case 'onClosePressed':
        webView.close();
        break;
    }
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map;
    final viewId = args['id'] as int;
    final webview = _webviews.cast<WebviewImpl?>().firstWhere(
          (e) => e?.viewId == viewId,
          orElse: () => null,
        );
    if (webview == null) {
      if (call.method == 'onWindowClose' && _pendingCreates > 0) {
        _closedDuringCreate.add(viewId);
      }
      return;
    }
    switch (call.method) {
      case "onWindowClose":
        _webviews.remove(webview);
        _titleBarStates.remove(viewId);
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
        await _sendTitleBarEvent('onHistoryChanged', {
          'webViewId': viewId,
          'canGoBack': args['canGoBack'] as bool,
          'canGoForward': args['canGoForward'] as bool,
        });
        break;
      case "onNavigationStarted":
        webview.onNavigationStarted();
        await _sendTitleBarEvent('onNavigationStarted', {'webViewId': viewId});
        break;
      case "onUrlRequested":
        final url = args['url'] as String;
        final ret = webview.notifyUrlChanged(url);
        await _sendTitleBarEvent('onUrlRequested', {
          'webViewId': viewId,
          'url': url,
        });
        return ret;
      case "onWebMessageReceived":
        final message = args['message'] as String;
        webview.notifyWebMessageReceived(message);
        await _otherIsolateMessageHandler.invokeMethod('onWebMessageReceived', {
          'webViewId': viewId,
          'message': message,
        });
        break;
      case "onNavigationCompleted":
        webview.onNavigationCompleted();
        await _sendTitleBarEvent('onNavigationCompleted', {
          'webViewId': viewId,
        });
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
