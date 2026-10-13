import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:desktop_webview_window/src/webview_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'title_bar_initialization_test.dart' show sendBrowserEvent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    for (final id in List.of(titleBarWebviews.value.keys)) {
      await sendBrowserEvent('onWindowClose', {'id': id});
    }
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('close is idempotent before and after native acknowledgement', () async {
    var closes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'close') closes++;
      return null;
    });
    final webview = WebviewImpl(123, channel);
    webview.close();
    webview.close();
    await Future<void>.delayed(Duration.zero);
    expect(closes, 1);
    webview.onClosed();
    webview.onClosed();
    await webview.onClose;
    webview.close();
    expect(closes, 1);
  });

  test(
      'native close before the create response completes onClose without publishing a toolbar handle',
      () async {
    final response = Completer<int>();
    messenger.setMockMethodCallHandler(
        channel, (call) async => response.future);
    final creating = WebviewWindow.create(
        titleBar: const WebviewTitleBarConfiguration.none());
    await Future<void>.delayed(Duration.zero);
    await sendBrowserEvent('onWindowClose', {'id': 303});
    response.complete(303);
    final webview = await creating;
    await webview.onClose;
    expect(titleBarWebviews.value, isEmpty);
  });

  test(
      'application and late toolbar readers share the current navigation state',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async => 404);
    final webview = await WebviewWindow.create(
        titleBar: const WebviewTitleBarConfiguration.none());
    var updates = 0;
    webview.navigationState.addListener(() => updates++);
    await sendBrowserEvent('onNavigationStarted', {'id': 404});
    await sendBrowserEvent('onNavigationCompleted', {'id': 404});
    await sendBrowserEvent('onHistoryChanged',
        {'id': 404, 'canGoBack': true, 'canGoForward': false});
    await sendBrowserEvent(
        'onUrlRequested', {'id': 404, 'url': 'https://example.com'});
    expect(
        webview.navigationState.value,
        const WebviewNavigationState(
          canGoBack: true,
          url: 'https://example.com',
        ));
    expect(webview.isNavigating.value, isFalse);
    expect(updates, 4);
    await sendBrowserEvent('onNavigationCompleted', {'id': 404});
    expect(updates, 4);
  });
}
