import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'title_bar_initialization_test.dart' show sendBrowserEvent;

class _Dispatcher extends TestPlatformDispatcher {
  _Dispatcher({required super.platformDispatcher});
  final extraViews = <TestFlutterView>[];
  bool showMainView = true;

  @override
  Iterable<TestFlutterView> get views => [
        if (showMainView) ...super.views,
        ...extraViews,
      ];

  @override
  TestFlutterView? get implicitView => showMainView ? super.implicitView : null;
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  late final _dispatcher =
      _Dispatcher(platformDispatcher: super.platformDispatcher);
  @override
  _Dispatcher get platformDispatcher => _dispatcher;
}

class _ExtraView extends TestFlutterView {
  _ExtraView(TestFlutterView main, _Dispatcher dispatcher, this.id)
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
  const control = MethodChannel('desktop_webview_window/titlebars');
  const native = MethodChannel('webview_window');
  final messenger = binding.defaultBinaryMessenger;
  var nextId = 100;
  final descriptors = <Map<String, int>>[];
  final calls = <MethodCall>[];

  Future<void> refresh() async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
        control.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('viewsChanged')),
        (_) => done.complete());
    await done.future;
  }

  setUp(() {
    nextId = 100;
    descriptors.clear();
    calls.clear();
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call);
      if (call.method == 'getMainView') return 0;
      if (call.method == 'getViews') return List.of(descriptors);
      return null;
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      if (call.method == 'create') return ++nextId;
      return null;
    });
  });

  tearDown(() async {
    for (final id in List.of(titleBarWebviews.value.keys)) {
      await sendBrowserEvent('onWindowClose', {'id': id});
    }
    binding.platformDispatcher.extraViews.clear();
    binding.platformDispatcher.showMainView = true;
    messenger.setMockMethodCallHandler(control, null);
    messenger.setMockMethodCallHandler(native, null);
  });

  testWidgets(
      'headless host preserves application views and routes each toolbar to its browser',
      (tester) async {
    final main = tester.view;
    final appView = _ExtraView(main, binding.platformDispatcher, 300);
    final barView = _ExtraView(main, binding.platformDispatcher, 100);
    binding.platformDispatcher.extraViews.addAll([appView, barView]);
    binding.platformDispatcher.showMainView = false;
    descriptors.add({'viewId': 100, 'webViewId': 101, 'titleBarTopPadding': 0});
    Webview? toolbarBrowser;
    Widget builder(
        BuildContext context, Webview webview, WebviewNavigationState state) {
      toolbarBrowser = webview;
      return TextButton(
          onPressed: webview.reload,
          child: Text('${state.url ?? "empty"}:${state.isLoading}'));
    }

    var appBuilds = 0;
    final application = View(
        view: appView,
        child: StatefulBuilder(builder: (context, setState) {
          appBuilds++;
          return const MaterialApp(home: Text('owned application window'));
        }));
    await tester.pumpWidget(
        WebviewTitleBarHost(
          titleBar: WebviewTitleBarConfiguration(builder: builder),
          child: application,
        ),
        wrapWithView: false);
    await tester.pumpAndSettle();
    expect(find.text('owned application window'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(calls.where((call) => call.method == 'getMainView'), isEmpty);
    final first = await WebviewWindow.create();
    await sendBrowserEvent(
        'onUrlRequested', {'id': 101, 'url': 'https://example.com/first'});
    await tester.pumpAndSettle();
    expect(toolbarBrowser, same(first));
    expect(find.text('https://example.com/first:false'), findsOneWidget);
    final initialBuilds = appBuilds;
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(TextButton)), view: barView);
    await gesture.up(view: barView);
    expect(calls.last.arguments, {'viewId': 101});
    await sendBrowserEvent('onNavigationStarted', {'id': 999});
    await tester.pump();
    expect(find.text('https://example.com/first:false'), findsOneWidget);
    await sendBrowserEvent('onNavigationStarted', {'id': 101});
    await tester.pump();
    expect(find.text('https://example.com/first:true'), findsOneWidget);
    expect(first.navigationState.value.isLoading, isTrue);
    await sendBrowserEvent('onWindowClose', {'id': 101});
    descriptors.clear();
    await refresh();
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('owned application window'), findsOneWidget);
    final second = await WebviewWindow.create();
    descriptors.add({'viewId': 100, 'webViewId': 102, 'titleBarTopPadding': 0});
    await refresh();
    await tester.pumpAndSettle();
    expect(toolbarBrowser, same(second));
    expect(find.text('empty:false'), findsOneWidget);
    expect(appBuilds, initialBuilds);
    final nextGesture = await tester
        .startGesture(tester.getCenter(find.byType(TextButton)), view: barView);
    await nextGesture.up(view: barView);
    expect(calls.last.arguments, {'viewId': 102});
    binding.platformDispatcher.showMainView = true;
    await tester.pumpWidget(const ViewCollection(views: []),
        wrapWithView: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host can anchor titlebars inside an existing runApp view',
      (tester) async {
    binding.platformDispatcher.extraViews
        .add(_ExtraView(tester.view, binding.platformDispatcher, 100));
    descriptors.add({'viewId': 100, 'webViewId': 101, 'titleBarTopPadding': 0});
    await tester.pumpWidget(WebviewTitleBarHost(
      titleBar: WebviewTitleBarConfiguration(
          builder: (context, webview, state) => const Text('toolbar')),
      child: const MaterialApp(home: Text('main application')),
    ));
    await WebviewWindow.create();
    await tester.pumpAndSettle();
    expect(find.text('main application'), findsOneWidget);
    expect(find.text('toolbar'), findsOneWidget);
    expect(find.byType(ViewAnchor), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'global builder and theme update while window overrides stay local',
      (tester) async {
    for (final id in [100, 200]) {
      binding.platformDispatcher.extraViews
          .add(_ExtraView(tester.view, binding.platformDispatcher, id));
    }
    descriptors.addAll([
      {'viewId': 100, 'webViewId': 101, 'titleBarTopPadding': 24},
      {'viewId': 200, 'webViewId': 102, 'titleBarTopPadding': 0},
    ]);
    final theme = ValueNotifier<ThemeData?>(ThemeData.light());
    var prefix = 'shared';
    await tester.pumpWidget(ValueListenableBuilder<ThemeData?>(
      valueListenable: theme,
      builder: (context, value, _) => WebviewTitleBarHost(
        titleBar: WebviewTitleBarConfiguration(
            theme: value,
            builder: (context, webview, state) =>
                Text('$prefix ${Theme.of(context).brightness.name}')),
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    ));
    final first = await WebviewWindow.create();
    final second = await WebviewWindow.create(
        titleBar: WebviewTitleBarConfiguration(
      builder: (context, webview, state) =>
          Text('custom ${Theme.of(context).brightness.name}'),
      theme: ThemeData.dark(),
    ));
    await WebviewWindow.create(
        titleBar: const WebviewTitleBarConfiguration.none());
    await tester.pumpAndSettle();
    expect(find.text('shared light'), findsOneWidget);
    expect(find.text('custom dark'), findsOneWidget);
    var navigationNotifications = 0;
    first.navigationState.addListener(() => navigationNotifications++);
    await first.setTitleBarTheme(ThemeData.dark());
    await tester.pumpAndSettle();
    expect(find.text('shared dark'), findsOneWidget);
    await first.setTitleBarTheme(null);
    prefix = 'updated';
    theme.value = ThemeData.dark();
    await tester.pumpAndSettle();
    expect(find.text('updated dark'), findsOneWidget);
    expect(find.text('custom dark'), findsOneWidget);
    theme.value = ThemeData.light();
    await second.setTitleBarTheme(ThemeData.light());
    await tester.pumpAndSettle();
    expect(find.text('updated light'), findsOneWidget);
    expect(find.text('custom light'), findsOneWidget);
    await second.setTitleBarTheme(null);
    await tester.pumpAndSettle();
    expect(find.text('custom dark'), findsOneWidget);
    theme.value = null;
    await tester.pumpAndSettle();
    final brightness =
        calls.where((call) => call.method == 'setBrightness').toList();
    if (brightness.isNotEmpty) {
      expect(
          brightness
              .lastWhere((call) => (call.arguments as Map)['viewId'] == 101)
              .arguments,
          {'viewId': 101, 'brightness': -1});
      expect(
          brightness
              .lastWhere((call) => (call.arguments as Map)['viewId'] == 103)
              .arguments,
          {'viewId': 103, 'brightness': -1});
    }
    expect(navigationNotifications, 0);
    for (final id in [101, 102, 103]) {
      await sendBrowserEvent('onWindowClose', {'id': id});
    }
    final callsAfterClose = calls.length;
    theme.value = ThemeData.dark();
    await tester.pumpAndSettle();
    expect(calls.length, callsAfterClose);
    await tester.pumpWidget(const SizedBox.shrink());
    theme.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'convenience root passes browser state and commands to the builder',
      (tester) async {
    binding.platformDispatcher.extraViews
        .add(_ExtraView(tester.view, binding.platformDispatcher, 100));
    descriptors.add({'viewId': 100, 'webViewId': 101, 'titleBarTopPadding': 0});
    await tester.pumpWidget(
        WebviewWindowApp(
          titleBar: WebviewTitleBarConfiguration(
            builder: (context, webview, state) => TextButton(
              onPressed: webview.close,
              child: Text('${state.canGoBack}'),
            ),
          ),
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
        wrapWithView: false);
    await tester.pumpAndSettle();
    await WebviewWindow.create();
    await sendBrowserEvent('onHistoryChanged',
        {'id': 101, 'canGoBack': true, 'canGoForward': false});
    await tester.pumpAndSettle();
    expect(find.text('true'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(calls.last.method, 'close');
    expect(calls.last.arguments, {'viewId': 101});
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
