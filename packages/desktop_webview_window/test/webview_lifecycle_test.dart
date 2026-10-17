import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/browser_runtime.dart';
import 'package:desktop_webview_window/src/webview_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installFakeTransport);

  tearDown(() async {
    for (final id in List.of(browsers.keys)) {
      await sendBrowserEvent('onWindowClose', {'id': id});
    }
  });

  test('close is idempotent before and after native acknowledgement', () async {
    var closes = 0;
    fakeTransport.native = (call) async {
      if (call.method == 'close') closes++;
      return null;
    };
    final webview = WebviewImpl(123, windowHandle: 1, transport: fakeTransport);
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
      'native close before the create response completes onClose without registering the browser',
      () async {
    final response = Completer<Map<String, Object?>>();
    fakeTransport.native = (call) async => response.future;
    final creating = WebviewWindow.create();
    await Future<void>.delayed(Duration.zero);
    await sendBrowserEvent('onWindowClose', {'id': 303});
    response.complete(created(303));
    final webview = await creating;
    await webview.onClose;
    expect(browsers, isEmpty);
  });

  test('navigation state mirrors the native state, including the title',
      () async {
    fakeTransport.native = (call) async => created(404);
    final webview = await WebviewWindow.create();
    final states = <WebviewNavigationState>[];
    webview.navigationState
        .addListener(() => states.add(webview.navigationState.value));
    await sendBrowserEvent('onNavigationStateChanged', {
      'id': 404,
      'canGoBack': false,
      'canGoForward': false,
      'isLoading': true,
      'url': 'https://example.com/',
      'title': null,
    });
    await sendBrowserEvent('onNavigationStateChanged', {
      'id': 404,
      'canGoBack': true,
      'canGoForward': false,
      'isLoading': false,
      'url': 'https://example.com/',
      'title': 'Example',
    });
    expect(states, const [
      WebviewNavigationState(isLoading: true, url: 'https://example.com/'),
      WebviewNavigationState(
        canGoBack: true,
        url: 'https://example.com/',
        title: 'Example',
      ),
    ]);
  });

  test('closing clears the loading flag', () async {
    fakeTransport.native = (call) async => created(405);
    final webview = await WebviewWindow.create();
    await sendBrowserEvent('onNavigationStateChanged', {
      'id': 405,
      'canGoBack': false,
      'canGoForward': false,
      'isLoading': true,
      'url': null,
      'title': null,
    });
    await sendBrowserEvent('onWindowClose', {'id': 405});
    expect(webview.navigationState.value.isLoading, isFalse);
  });
}
