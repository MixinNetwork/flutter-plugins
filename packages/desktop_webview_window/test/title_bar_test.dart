import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_messages.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
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

class _Dispatcher extends TestPlatformDispatcher {
  _Dispatcher({required super.platformDispatcher});
  final extraViews = <TestFlutterView>[];
  bool showMainView = true;

  @override
  Iterable<TestFlutterView> get views => [
        if (showMainView) ...super.views,
        ...extraViews,
      ];
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  late final _dispatcher =
      _Dispatcher(platformDispatcher: super.platformDispatcher);

  @override
  _Dispatcher get platformDispatcher => _dispatcher;
}

class _ExtraView extends TestFlutterView {
  _ExtraView(TestFlutterView main, _Dispatcher dispatcher, [this.id = 100])
      : super(
            view: main, platformDispatcher: dispatcher, display: main.display);

  final int id;

  @override
  int get viewId => id;

  @override
  void render(ui.Scene scene, {ui.Size? size}) {}

  @override
  void updateSemantics(ui.SemanticsUpdate update) {}
}

void main() {
  final binding = _Binding();
  const client = TitleBarMessages();
  const control = MethodChannel('desktop_webview_window/titlebars');

  tearDown(() {
    client.setMessageHandler(null);
    binding.platformDispatcher.extraViews.clear();
    binding.platformDispatcher.showMainView = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, null);
    titleBarInitialization = null;
  });

  test('local messages fan out and unsubscribe without a native relay',
      () async {
    final received = <String>[];
    Future<void> first(MethodCall call) async => received.add('first');
    Future<void> second(MethodCall call) async => received.add('second');
    client.addMessageHandler(first);
    client.addMessageHandler(second);
    await client.invokeMethod('event', {});
    expect(received, ['first', 'second']);
    received.clear();
    client.removeMessageHandler(first);
    await client.invokeMethod('event', {});
    expect(received, ['second']);
  });

  testWidgets(
      'main state survives titlebar close/recreate and isolated routing',
      (tester) async {
    final mainView = tester.view;
    binding.platformDispatcher.extraViews.add(
      _ExtraView(mainView, binding.platformDispatcher),
    );
    var browserId = 101;
    var visible = true;
    var mainBuilds = 0;
    final commands = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(control, (call) async {
      if (call.method == 'initialize') return tester.view.viewId;
      expect(call.method, 'getViews');
      return [
        if (visible)
          {'viewId': 100, 'webViewId': browserId, 'titleBarTopPadding': 0},
      ];
    });
    client.addMessageHandler((call) async {
      if (call.method == 'onClosePressed') commands.add(call);
    });
    final main = StatefulBuilder(builder: (context, setState) {
      mainBuilds++;
      return const MaterialApp(home: Text('main application'));
    });
    await tester.pumpWidget(
      WebviewWindowApp(
        titleBarBuilder: (context) {
          final state = TitleBarWebViewState.of(context);
          return TextButton(
            onPressed: TitleBarWebViewController.of(context).close,
            child: Text('${state.url ?? "empty"}:${state.isLoading}'),
          );
        },
        child: main,
      ),
      wrapWithView: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('main application'), findsOneWidget);
    expect(find.text('empty:false'), findsOneWidget);
    final initialMainBuilds = mainBuilds;
    await client.invokeMethod('onUrlRequested', {
      'webViewId': 999,
      'url': 'wrong',
    });
    await tester.pump();
    expect(find.text('empty:false'), findsOneWidget);
    await client.invokeMethod('onUrlRequested', {
      'webViewId': 101,
      'url': 'https://example.com',
    });
    await tester.pump();
    expect(find.text('https://example.com:false'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(commands.single.arguments, {'webViewId': 101});
    visible = false;
    await sendNative(control.name, 'viewsChanged');
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('main application'), findsOneWidget);
    await client.invokeMethod('onNavigationStarted', {'webViewId': 101});
    visible = true;
    browserId = 202;
    await sendNative(control.name, 'viewsChanged');
    await tester.pumpAndSettle();
    expect(find.text('empty:false'), findsOneWidget);
    expect(mainBuilds, initialMainBuilds);
    await tester.tap(find.byType(TextButton));
    expect(commands.last.arguments, {'webViewId': 202});
    binding.platformDispatcher.showMainView = false;
    await sendNative(control.name, 'viewsChanged');
    await tester.pumpAndSettle();
    expect(find.text('main application'), findsNothing);
    expect(find.text('empty:false'), findsOneWidget);
    binding.platformDispatcher.showMainView = true;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(titleBarInitialization, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('global and per-window themes update toolbars and native windows',
      (tester) async {
    final messenger = binding.defaultBinaryMessenger;
    const native = MethodChannel('webview_window');
    final nativeCalls = <MethodCall>[];
    var nextId = 101;
    var visible = false;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'create') return nextId++;
      nativeCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(control, (call) async {
      if (call.method == 'initialize') return tester.view.viewId;
      return [
        if (visible)
          {'viewId': 100, 'webViewId': 101, 'titleBarTopPadding': 24},
        if (visible) {'viewId': 200, 'webViewId': 102, 'titleBarTopPadding': 0},
      ];
    });
    binding.platformDispatcher.extraViews.addAll([
      _ExtraView(tester.view, binding.platformDispatcher),
      _ExtraView(tester.view, binding.platformDispatcher, 200),
    ]);
    final global = ValueNotifier<ThemeData?>(ThemeData.light());
    await tester.pumpWidget(
        ValueListenableBuilder<ThemeData?>(
          valueListenable: global,
          builder: (context, theme, _) => WebviewWindowApp(
            titleBarTheme: theme,
            titleBarBuilder: (context) => Text(
              Theme.of(context).brightness.name,
              key: const ValueKey('theme'),
            ),
            child: const MaterialApp(home: SizedBox.shrink()),
          ),
        ),
        wrapWithView: false);
    await tester.pumpAndSettle();
    final first = await WebviewWindow.create();
    final second = await WebviewWindow.create();
    final toolbarless = await WebviewWindow.create(
      configuration: const CreateConfiguration(titleBarHeight: 0),
    );
    // The override must survive a toolbar mounting after the API call.
    await first.setTitleBarTheme(ThemeData.dark());
    visible = true;
    await sendNative(control.name, 'viewsChanged');
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);
    expect(find.text('light'), findsOneWidget);
    final darkContext = tester.element(find.text('dark'));
    expect(Material.of(darkContext).color,
        ThemeData.dark().scaffoldBackgroundColor);
    global.value = ThemeData.dark();
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsNWidgets(2));
    global.value = ThemeData.light();
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);
    expect(find.text('light'), findsOneWidget);
    await first.setTitleBarTheme(null);
    await tester.pumpAndSettle();
    expect(find.text('light'), findsNWidgets(2));
    if (Platform.isMacOS || Platform.isWindows) {
      expect(
          nativeCalls
              .where((call) => call.method == 'setBrightness')
              .map((call) => call.arguments),
          [
            {'viewId': 101, 'brightness': 1},
            {'viewId': 102, 'brightness': 1},
            {'viewId': 103, 'brightness': 1},
            {'viewId': 101, 'brightness': 0},
            {'viewId': 102, 'brightness': 0},
            {'viewId': 103, 'brightness': 0},
            {'viewId': 102, 'brightness': 1},
            {'viewId': 103, 'brightness': 1},
            {'viewId': 101, 'brightness': 1},
          ]);
    }
    global.value = null;
    await tester.pumpAndSettle();
    if (Platform.isMacOS || Platform.isWindows) {
      expect(nativeCalls.last.arguments, {'viewId': 103, 'brightness': -1});
    }
    for (final view in [first, second, toolbarless]) {
      view.close();
      await sendNative(native.name, 'onWindowClose', {
        'id': view == first
            ? 101
            : view == second
                ? 102
                : 103,
      });
    }
    final callsAfterClose = nativeCalls.length;
    global.value = ThemeData.dark();
    await tester.pumpAndSettle();
    expect(nativeCalls.length, callsAfterClose);
    await first.setTitleBarTheme(ThemeData.dark());
    expect(nativeCalls.length, callsAfterClose);
    await tester.pumpWidget(const SizedBox.shrink());
    global.dispose();
    messenger.setMockMethodCallHandler(native, null);
    expect(tester.takeException(), isNull);
  });
}
