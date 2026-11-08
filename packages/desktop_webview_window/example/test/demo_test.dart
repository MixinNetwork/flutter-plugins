import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/src/native_transport.dart';
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
  const native = MethodChannel('webview_example/native_test');
  late DemoPageServer pages;
  late DemoState state;
  late List<MethodCall> calls;
  late List<MethodCall> nativeCalls;
  var nextId = 1000;

  setUp(() async {
    NativeTransport.debugOverride = _MockChannelTransport(channel);
    pages = await DemoPageServer.start();
    state = DemoState(pages);
    calls = [];
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
      nativeCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return {'id': ++nextId, 'windowHandle': 1};
      if (call.method == 'isWebviewAvailable') return true;
      return null;
    });
  });

  tearDown(() async {
    NativeTransport.debugOverride = null;
    await pages.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
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

  test('layouts map to composer arguments', () async {
    for (final layout in DemoLayout.values) {
      await state.open(DemoWindowOptions(layout: layout));
      final arguments =
          calls.lastWhere((call) => call.method == 'create').arguments as Map;
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

  test('a pending create catches up with the latest app theme', () async {
    final response = Completer<Map<String, Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return response.future;
      return null;
    });
    await state.setThemeMode(ThemeMode.dark);
    final opening = state.open();
    await Future<void>.delayed(Duration.zero);
    expect((calls.single.arguments as Map)['brightness'], 0);
    await state.setThemeMode(ThemeMode.light);
    response.complete({'id': ++nextId, 'windowHandle': 1});
    await opening;
    expect(state.windows.single.appearance, ThemeMode.light);
    if (Platform.isLinux) {
      expect(nativeCalls.map((call) => call.arguments['brightness']), [0, 1]);
    } else {
      final update =
          calls.singleWhere((call) => call.method == 'setBrightness');
      expect(update.arguments['brightness'], 1);
      expect(calls.indexOf(update),
          lessThan(calls.indexWhere((call) => call.method == 'launch')));
    }
    state.dispose();
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

  testWidgets('new window dialog maps layout and title bar choices',
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
    expect(arguments['titleBar'], 15);
    expect(arguments['composerArguments'], isNull);

    arguments = await openWith(() async {
      await tester.tap(find.widgetWithText(FilterChip, 'Reload'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Host'));
    });
    expect(arguments['titleBar'], 1 | 4);
    expect(arguments['composerArguments'], isNull);

    // The dialog keeps the previous choices.
    arguments = await openWith(() => tester.tap(find.text('Sidebar composer')));
    expect(arguments['titleBar'], 1 | 4);
    expect(arguments['composerArguments'], 'sidebar');
    expect(state.windows, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('app theme can override and resume the system appearance',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.runAsync(() async {
      await state.open();
      await state.open();
    });
    await tester.pumpWidget(DemoApp(state: state));
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;
    Future<void> choose(String current, String next) async {
      await tester.tap(find.byTooltip('App theme: $current'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(CheckedPopupMenuItem<ThemeMode>, next));
      await tester.pumpAndSettle();
    }

    expect(brightness(), Brightness.light);
    await choose('System', 'Dark');
    expect(brightness(), Brightness.dark);
    expect(state.windows.map((window) => window.appearance),
        everyElement(ThemeMode.dark));
    expect(
        Platform.isLinux
            ? nativeCalls.map((call) => call.arguments['brightness'])
            : calls
                .where((call) => call.method == 'setBrightness')
                .map((call) => call.arguments['brightness']),
        Platform.isLinux ? [0] : [0, 0]);
    await tester.runAsync(state.open);
    await tester.pumpAndSettle();
    expect(
        (calls.lastWhere((call) => call.method == 'create').arguments
            as Map)['brightness'],
        0);
    expect(state.windows.last.appearance, ThemeMode.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await choose('Dark', 'Light');
    expect(brightness(), Brightness.light);
    await choose('Light', 'System');
    expect(brightness(), Brightness.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expect(
        Platform.isLinux
            ? nativeCalls.map((call) => call.arguments['brightness'])
            : calls
                .where((call) => call.method == 'setBrightness')
                .map((call) => call.arguments['brightness']),
        Platform.isLinux ? [0, 1, -1] : [0, 0, 1, 1, 1, -1, -1, -1]);
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

// Keep widget tests on the mocked channel without loading Windows FFI code.
class _MockChannelTransport extends NativeTransport {
  _MockChannelTransport(this.channel) : super.testing();

  final MethodChannel channel;

  @override
  Future<T?> invoke<T>(String method, [Object? arguments]) =>
      channel.invokeMethod<T>(method, arguments);
}
