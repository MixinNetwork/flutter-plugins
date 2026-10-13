import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:desktop_webview_window/src/webview_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_window');

  test('close is idempotent before and after native acknowledgement', () async {
    var closes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
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
    'create omits toolbar without hook and preserves public config',
    () async {
      final configurations = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'create') {
          configurations.add(call.arguments as Map);
          return configurations.length;
        }
        return null;
      });
      titleBarHookRegistered = false;
      await WebviewWindow.create();
      expect(configurations.single['useTitleBar'], isFalse);
      runWebViewTitleBarWidget([]);
      await WebviewWindow.create(
        configuration: const CreateConfiguration(titleBarHeight: 0),
      );
      expect(configurations.last['useTitleBar'], isTrue);
      expect(configurations.last['titleBarHeight'], 0);
      expect(configurations.last['useSharedTitleBarEngineLinux'], isFalse);
    },
  );
  test(
    'native close arriving before create response still completes onClose',
    () async {
      final response = Completer<int>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => response.future,
      );
      final creating = WebviewWindow.create();
      await Future<void>.delayed(Duration.zero);
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onWindowClose', {'id': 303}),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      response.complete(303);
      final webview = await creating;
      await webview.onClose;
    },
  );
  test(
    'late titlebar readiness replays only the latest browser state',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const bridge = MethodChannel('webview_message/client_channel');
      final received = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async => 404);
      messenger.setMockMethodCallHandler(bridge, (call) async {
        received.add(call);
        return null;
      });
      await WebviewWindow.create();
      Future<void> send(String name, String method, Map args) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) => done.complete(),
        );
        await done.future;
      }

      await send(channel.name, 'onNavigationStarted', {'id': 404});
      await send(channel.name, 'onNavigationCompleted', {'id': 404});
      await send(channel.name, 'onUrlRequested', {
        'id': 404,
        'url': 'https://example.com',
      });
      received.clear();
      await send(bridge.name, 'onTitleBarReady', {'webViewId': 404});
      expect(received.map((e) => e.method), [
        'onNavigationCompleted',
        'onUrlRequested',
      ]);
      expect(received.last.arguments['url'], 'https://example.com');
      await send(channel.name, 'onWindowClose', {'id': 404});
      received.clear();
      await send(bridge.name, 'onTitleBarReady', {'webViewId': 404});
      expect(received, isEmpty);
      messenger.setMockMethodCallHandler(bridge, null);
    },
  );
}
