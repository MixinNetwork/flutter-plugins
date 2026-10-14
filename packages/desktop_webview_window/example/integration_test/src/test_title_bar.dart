import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_window_example/demo_title_bar.dart';

// The macOS example fixture calls into the actual titlebar engine. Commands use
// the public controller, so tests exercise the existing cross-engine relay.
class TestTitleBar extends StatefulWidget {
  const TestTitleBar({super.key});

  @override
  State<TestTitleBar> createState() => _TestTitleBarState();
}

class _TestTitleBarState extends State<TestTitleBar> {
  static const _channel = MethodChannel('webview_example/titlebar_test');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      final state = TitleBarWebViewState.of(context);
      final controller = TitleBarWebViewController.of(context);
      switch (call.method) {
        case 'back':
          controller.back();
        case 'forward':
          controller.forward();
        case 'reload':
          controller.reload();
        case 'stop':
          controller.stop();
        case 'close':
          // Reply before closing the engine that owns this method channel.
          Timer.run(controller.close);
        case 'inspect':
          break;
        default:
          throw MissingPluginException(
              'Unknown titlebar operation: ${call.method}');
      }
      return {
        'url': state.url,
        'canGoBack': state.canGoBack,
        'canGoForward': state.canGoForward,
        'isLoading': state.isLoading,
      };
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const DemoTitleBar();
}
