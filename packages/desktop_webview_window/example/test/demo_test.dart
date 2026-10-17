import 'dart:async';

import 'package:desktop_webview_window/src/webview_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webview_window_example/demo_app.dart';
import 'package:webview_window_example/demo_page_server.dart';
import 'package:webview_window_example/demo_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('desktop_webview_window');
  late DemoPageServer pages;
  late DemoState state;
  late List<MethodCall> calls;
  var nextId = 1000;

  setUp(() async {
    pages = await DemoPageServer.start();
    state = DemoState(pages);
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return {'id': ++nextId, 'windowHandle': 1};
      if (call.method == 'isWebviewAvailable') return true;
      return null;
    });
  });

  tearDown(() async {
    await pages.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('invalid URL does not create a browser and logs the problem', () async {
    await state.open(const DemoWindowOptions(url: 'javascript:alert(1)'));
    expect(calls.where((call) => call.method == 'create'), isEmpty);
    expect(state.events.single.message, contains('valid http'));
    state.dispose();
  });

  test('async results stay with their original window and panel', () async {
    await state.open();
    await state.open();
    final first = state.windows.first;
    final second = state.windows.last;
    final response = Completer<String>();
    final operation = state.perform(
        first, DemoPanel.javascript, 'Run', () => response.future);
    state.select(second);
    response.complete('first window result');
    await operation;
    expect(
        first.results[DemoPanel.javascript], contains('first window result'));
    expect(first.results[DemoPanel.messages], isNull);
    expect(second.results[DemoPanel.javascript], isNull);
    expect(state.selected, same(second));
    (first.webview as WebviewImpl).onClosed();
    await first.webview.onClose;
    await Future<void>.delayed(Duration.zero);
    expect(state.windows, [second]);
    state.dispose();
  });

  test('layouts map to toolbar and composer arguments', () async {
    for (final layout in DemoLayout.values) {
      await state.open(DemoWindowOptions(layout: layout));
      final arguments =
          calls.lastWhere((call) => call.method == 'create').arguments as Map;
      expect(arguments['showToolbar'], layout == DemoLayout.toolbar);
      expect(arguments['composerArguments'],
          layout == DemoLayout.sidebar ? 'sidebar' : null);
    }
    state.dispose();
  });

  test('address input accepts bare hosts and rejects other schemes', () {
    expect(DemoState.normalizeUrl('mixin.one'), 'https://mixin.one');
    expect(DemoState.normalizeUrl(' http://a.test/x '), 'http://a.test/x');
    expect(DemoState.normalizeUrl('javascript:alert(1)'), isNull);
    expect(DemoState.normalizeUrl('file:///etc/hosts'), isNull);
    state.dispose();
  });

  test('a pending create is closed when the app has been disposed', () async {
    final response = Completer<Map<String, Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return response.future;
      return null;
    });
    final opening = state.open();
    await Future<void>.delayed(Duration.zero);
    state.dispose();
    response.complete({'id': ++nextId, 'windowHandle': 1});
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

  testWidgets('new window dialog maps layout and titlebar choices',
      (tester) async {
    await tester.pumpWidget(DemoApp(state: state));
    await tester.runAsync(() async {
      while (state.available == null) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpAndSettle();
    Future<Map> openWith(Future<void> Function() choose) async {
      await tester.tap(find.text('New window').first);
      await tester.pumpAndSettle();
      await choose();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        while (state.creating) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      return calls.lastWhere((call) => call.method == 'create').arguments
          as Map;
    }

    var arguments = await openWith(() async {});
    expect(arguments['showSystemTitleBar'], true);
    expect(arguments['showToolbar'], true);
    expect(arguments['composerArguments'], isNull);

    arguments = await openWith(() async {
      await tester.tap(find.text('Sidebar composer'));
      await tester.tap(find.byType(Switch));
    });
    expect(arguments['showSystemTitleBar'], false);
    expect(arguments['showToolbar'], false);
    expect(arguments['composerArguments'], 'sidebar');

    // The dialog keeps the previous choices.
    arguments = await openWith(() => tester.tap(find.text('None')));
    expect(arguments['showSystemTitleBar'], false);
    expect(arguments['showToolbar'], false);
    expect(arguments['composerArguments'], isNull);
    expect(state.windows, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow layout picks windows from a dropdown', (tester) async {
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await state.open();
      await state.open();
    });
    await tester.pumpWidget(DemoApp(state: state));
    await tester.pumpAndSettle();
    expect(state.selectedId, state.windows.last.id);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Browser 1 ·').last);
    await tester.pumpAndSettle();
    expect(state.selectedId, 1);
    await tester.tap(find.text('JavaScript'));
    await tester.pumpAndSettle();
    expect(find.text('Run'), findsOneWidget);
    await tester.tap(find.textContaining('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('This window'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
