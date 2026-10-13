import 'dart:async';
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
  _ExtraView(TestFlutterView main, _Dispatcher dispatcher)
      : super(
            view: main, platformDispatcher: dispatcher, display: main.display);

  @override
  int get viewId => 100;

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
}
