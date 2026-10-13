import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> sendBrowserEvent(String method, Map<String, Object?> args) async {
  final done = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
          'webview_window',
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall(method, args)),
          (_) => done.complete());
  await done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('webview_window');
  const control = MethodChannel('desktop_webview_window/titlebars');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final creates = <Map<dynamic, dynamic>>[];
  final controlCalls = <MethodCall>[];
  var nextId = 100;

  setUp(() {
    creates.clear();
    controlCalls.clear();
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'create') {
        creates.add(call.arguments as Map);
        return ++nextId;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(control, (call) async {
      controlCalls.add(call);
      if (call.method == 'getMainView') return 0;
      if (call.method == 'getViews') return [];
      return null;
    });
  });

  tearDown(() async {
    for (final id in List.of(titleBarWebviews.value.keys)) {
      await sendBrowserEvent('onWindowClose', {'id': id});
    }
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(control, null);
  });

  test('missing host reports a requested toolbar instead of hiding it',
      () async {
    await expectLater(WebviewWindow.create(), throwsStateError);
    await expectLater(
        WebviewWindow.create(
          titleBar: const WebviewTitleBarConfiguration(height: 60),
        ),
        throwsStateError);
    expect(creates, isEmpty);
  });

  test('explicit none creates a native browser without initializing a host',
      () async {
    await WebviewWindow.create(
      titleBar: const WebviewTitleBarConfiguration.none(),
      configuration:
          const CreateConfiguration(windowWidth: 900, windowHeight: 600),
    );
    expect(creates.single['useTitleBar'], isFalse);
    expect(creates.single['titleBarHeight'], 0);
    expect(creates.single['titleBarTopPadding'], 0);
    expect(creates.single['windowWidth'], 900);
    expect(controlCalls, isEmpty);
  });

  testWidgets(
      'host waits for engine attachment but renders the application immediately',
      (tester) async {
    final ready = Completer<void>();
    messenger.setMockMethodCallHandler(control, (call) async {
      controlCalls.add(call);
      if (call.method == 'initialize') {
        await ready.future;
        return null;
      }
      return [];
    });
    await tester.pumpWidget(const WebviewTitleBarHost(
      titleBar: WebviewTitleBarConfiguration(height: 48, topPadding: 12),
      child: Text('application', textDirection: TextDirection.ltr),
    ));
    expect(find.text('application'), findsOneWidget);
    final creating = WebviewWindow.create();
    await tester.pump();
    expect(creates, isEmpty);
    expect(controlCalls.first.method, 'initialize');
    expect(controlCalls.first.arguments, isNot(contains('mainViewId')));
    ready.complete();
    await creating;
    expect(creates.single['titleBarHeight'], 48);
    expect(creates.single['titleBarTopPadding'], 12);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(titleBarInitialization, isNull);
  });

  testWidgets(
      'per-window configuration overrides defaults and system titlebar is independent',
      (tester) async {
    await tester.pumpWidget(const WebviewTitleBarHost(
      titleBar: WebviewTitleBarConfiguration(height: 48, topPadding: 12),
      child: SizedBox.shrink(),
    ));
    await WebviewWindow.create(
        titleBar:
            const WebviewTitleBarConfiguration(height: 60, topPadding: 20));
    expect(creates.last['titleBarHeight'], 60);
    expect(creates.last['titleBarTopPadding'], 20);
    await WebviewWindow.create(
        configuration: const CreateConfiguration(showSystemTitleBar: false));
    expect(creates.last['showSystemTitleBar'], isFalse);
    expect(creates.last['useTitleBar'], isTrue);
    expect(creates.last['titleBarHeight'], 48);
    expect(creates.last['titleBarTopPadding'], 0);
    await WebviewWindow.create(
        titleBar: const WebviewTitleBarConfiguration.none());
    expect(creates.last['useTitleBar'], isFalse);
    expect(creates.last['showSystemTitleBar'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending creation fails if its host was unmounted',
      (tester) async {
    final ready = Completer<void>();
    messenger.setMockMethodCallHandler(control, (call) async {
      if (call.method == 'initialize') {
        await ready.future;
        return null;
      }
      return [];
    });
    await tester
        .pumpWidget(const WebviewTitleBarHost(child: SizedBox.shrink()));
    final creating = WebviewWindow.create();
    final result = expectLater(creating, throwsStateError);
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete();
    await result;
    expect(creates, isEmpty);
  });

  testWidgets('convenience root alone queries the runner-owned main view',
      (tester) async {
    await tester.pumpWidget(
        const WebviewWindowApp(
          child: Text('main', textDirection: TextDirection.ltr),
        ),
        wrapWithView: false);
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
    expect(controlCalls.map((call) => call.method), contains('getMainView'));
    await WebviewWindow.create();
    expect(creates.single['useTitleBar'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
