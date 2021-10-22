// You have generated a new plugin project without
// specifying the `--platforms` flag. A plugin project supports no platforms is generated.
// To add platforms, run `flutter create -t plugin --platforms <platforms> .` under the same
// directory. You can also find a detailed instruction on how to add platforms in the `pubspec.yaml` at https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin-platforms.

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'src/create_configuration.dart';
import 'src/webview.dart';
import 'src/webview_impl.dart';

export 'src/create_configuration.dart';
export 'src/webview.dart';

final List<WebviewImpl> _webviews = [];

class WebviewWindow {
  static const MethodChannel _channel = MethodChannel('webview_window');

  static bool _inited = false;

  static void _init() {
    if (_inited) {
      return;
    }
    _inited = true;
    _channel.setMethodCallHandler((call) async {
      try {
        return await handleMethodCall(call);
      } catch (e, s) {
        debugPrint('handleMethodCall error: $e $s');
      }
    });
  }

  static Future<Webview> create({
    CreateConfiguration configuration = const CreateConfiguration(),
  }) async {
    _init();
    final viewId = await _channel.invokeMethod(
      "create",
      configuration.toMap(),
    ) as int;
    final webview = WebviewImpl(viewId, _channel);
    _webviews.add(webview);
    return webview;
  }

  static Future<dynamic> handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map;
    final viewId = args['id'] as int;
    final webview = _webviews
        .cast<WebviewImpl?>()
        .firstWhere((e) => e?.viewId == viewId, orElse: () => null);
    assert(webview != null);
    if (webview == null) {
      return;
    }
    switch (call.method) {
      case "onWindowClose":
        _webviews.remove(webview);
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
      default:
        return;
    }
  }

  /// Clear all cookies and storage.
  static Future<void> clearAll() async {
    await _channel.invokeMethod('clearAll');

    // FIXME(boyan01) Move the logic to windows platform if WebView2 provider a way to clean caches.
    if (Platform.isWindows) {
      final dir = File(Platform.resolvedExecutable).parent;
      final webview2Dir = Directory(dir.path + "\\webview_window_WebView2");

      if (await (webview2Dir.exists())) {
        for (var i = 0; i <= 4; i++) {
          try {
            webview2Dir.delete(recursive: true);
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
