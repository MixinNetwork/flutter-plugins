import 'dart:async';

import 'package:desktop_webview_window/src/title_bar_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webview_window_example/demo_app.dart';
import 'package:webview_window_example/demo_page_server.dart';
import 'package:webview_window_example/demo_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_window');
  late DemoPageServer pages;
  late DemoState state;
  late List<MethodCall> calls;
  var nextId = 1000;

  setUp(() async {
    pages = await DemoPageServer.start();
    state = DemoState(pages);
    calls = [];
    titleBarInitialized = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return ++nextId;
      if (call.method == 'isWebviewAvailable') return true;
      return null;
    });
  });

  tearDown(() async {
    titleBarInitialized = false;
    await pages.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('invalid URL does not create a browser and logs the problem', () async {
    await state.open(url: 'javascript:alert(1)');
    expect(calls.where((call) => call.method == 'create'), isEmpty);
    expect(state.events.single.message, contains('valid http'));
    state.dispose();
  });

  test('async results stay with their original window after selection changes',
      () async {
    await state.open(count: 2);
    final first = state.windows.first;
    final second = state.windows.last;
    final response = Completer<String>();
    final operation = state.perform(first, 'Execute', () => response.future);
    state.select(second);
    response.complete('first window result');
    await operation;
    expect(first.result, contains('first window result'));
    expect(second.result, isNot(contains('first window result')));
    expect(state.selected, same(second));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'webview_window',
      const StandardMethodCodec().encodeMethodCall(MethodCall(
        'onWindowClose',
        {
          'id': (calls.firstWhere((call) => call.method == 'launch').arguments
              as Map)['viewId']
        },
      )),
      (_) {},
    );
    await first.webview.onClose;
    await Future<void>.delayed(Duration.zero);
    expect(state.windows, [second]);
    state.dispose();
  });

  test('a pending create is closed when the app has been disposed', () async {
    final response = Completer<int>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return response.future;
      return null;
    });
    final opening = state.open();
    await Future<void>.delayed(Duration.zero);
    state.dispose();
    response.complete(++nextId);
    await opening;
    expect(state.windows, isEmpty);
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
  });

  test('event history retains only the latest 200 entries', () {
    for (var i = 0; i < 250; i++) {
      state.log('Event $i');
    }
    expect(state.events, hasLength(200));
    expect(state.events.first.message, 'Event 50');
    state.clearEvents();
    expect(state.events, isEmpty);
    state.dispose();
  });

  testWidgets('Flutter titlebar switch controls reserved height and padding',
      (tester) async {
    await tester.pumpWidget(DemoApp(state: state));
    await tester.pumpAndSettle();
    Future<void> openAndCheck(bool titleBar) async {
      await tester.runAsync(() async {
        await tester.tap(find.text('Open window'));
        while (state.creating) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      final arguments =
          calls.lastWhere((call) => call.method == 'create').arguments as Map;
      expect(arguments['titleBarHeight'], titleBar ? 44 : 0);
      if (!titleBar) expect(arguments['titleBarTopPadding'], 0);
    }

    await openAndCheck(true);
    await tester.tap(find.descendant(
      of: find.widgetWithText(Row, 'Flutter titlebar'),
      matching: find.byType(Checkbox),
    ));
    await tester.pumpAndSettle();
    await openAndCheck(false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('window selection and app theme work at a narrow size',
      (tester) async {
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => state.open(count: 2));
    await tester.pumpWidget(DemoApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('WINDOWS · 2'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Browser 1'));
    await tester.pumpAndSettle();
    expect(state.selectedId, 1);
    await tester.tap(find.byTooltip('Toggle app theme'));
    await tester.pumpAndSettle();
    expect(state.darkMode.value, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
