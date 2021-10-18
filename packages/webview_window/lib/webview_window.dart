// You have generated a new plugin project without
// specifying the `--platforms` flag. A plugin project supports no platforms is generated.
// To add platforms, run `flutter create -t plugin --platforms <platforms> .` under the same
// directory. You can also find a detailed instruction on how to add platforms in the `pubspec.yaml` at https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin-platforms.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:webview_window/src/create_configuration.dart';
import 'package:webview_window/src/webview.dart';
import 'package:webview_window/src/webview_impl.dart';

export 'src/webview.dart';
export 'src/create_configuration.dart';

final List<WebviewImpl> _webviews = [];

class WebviewWindow {
  static const MethodChannel _channel = MethodChannel('webview_window');

  static bool _inited = false;

  static void init() {
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
}
