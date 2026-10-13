import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/message_channel.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:desktop_webview_window/src/title_bar.dart'
    show SharedTitleBarViews;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> sendNative(String channel, String method, [Object? args]) async {
  final done = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) => done.complete(),
      );
  await done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const client = ClientMessageChannel();
  const control = MethodChannel('desktop_webview_window/titlebars');

  tearDown(() {
    client.setMessageHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, null);
    titleBarHookRegistered = false;
  });

  test('entry hook registers primary isolate without running a second app', () {
    expect(runWebViewTitleBarWidget([]), isFalse);
    expect(titleBarHookRegistered, isTrue);
    expect(runWebViewTitleBarWidget(['web_view_title_bar']), isFalse);
    expect(
      runWebViewTitleBarWidget(['web_view_title_bar', 'invalid']),
      isFalse,
    );
  });

  test(
    'message channel dispatches to all live titlebars and removes listeners',
    () async {
      final received = <String>[];
      Future<void> first(MethodCall call) async => received.add('first');
      Future<void> second(MethodCall call) async => received.add('second');
      client.addMessageHandler(first);
      client.addMessageHandler(second);
      await sendNative('webview_message/client_channel', 'event', {});
      expect(received, ['first', 'second']);
      received.clear();
      client.removeMessageHandler(first);
      await sendNative('webview_message/client_channel', 'event', {});
      expect(received, ['second']);
    },
  );

  testWidgets(
    'snapshot binds browser ID separately and closes/recreates safely',
    (tester) async {
      var browserId = 101;
      var visible = true;
      final commands = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(control, (call) async {
        expect(call.method, 'getViews');
        return [
          if (visible)
            {
              'viewId': tester.view.viewId,
              'webViewId': browserId,
              'titleBarTopPadding': 0,
            },
        ];
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('webview_message/client_channel'),
        (call) async {
          if (call.method != 'onTitleBarReady') commands.add(call);
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('webview_message/client_channel'),
          null,
        ),
      );
      await tester.pumpWidget(
        SharedTitleBarViews(
          builder: (context) {
            final state = TitleBarWebViewState.of(context);
            return TextButton(
              onPressed: TitleBarWebViewController.of(context).close,
              child: Text('${state.url ?? "empty"}:${state.isLoading}'),
            );
          },
        ),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('empty:false'), findsOneWidget);
      await sendNative('webview_message/client_channel', 'onUrlRequested', {
        'webViewId': 999,
        'url': 'wrong',
      });
      await tester.pump();
      expect(find.text('empty:false'), findsOneWidget);
      await sendNative('webview_message/client_channel', 'onUrlRequested', {
        'webViewId': 101,
        'url': 'https://example.com',
      });
      await tester.pump();
      expect(find.text('https://example.com:false'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      expect(commands.single.method, 'onClosePressed');
      expect(commands.single.arguments, {'webViewId': 101});
      visible = false;
      await sendNative(control.name, 'viewsChanged');
      await tester.pumpAndSettle();
      expect(find.byType(TextButton), findsNothing);
      await sendNative(
        'webview_message/client_channel',
        'onNavigationStarted',
        {'webViewId': 101},
      );
      visible = true;
      browserId = 202;
      await sendNative(control.name, 'viewsChanged');
      await tester.pumpAndSettle();
      expect(find.text('empty:false'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      expect(commands.last.arguments, {'webViewId': 202});
      await tester.pumpWidget(
        const ViewCollection(views: []),
        wrapWithView: false,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
