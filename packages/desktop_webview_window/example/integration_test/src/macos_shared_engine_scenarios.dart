import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _toolbars = <int, _TestToolbarState>{};
const _native = MethodChannel('webview_window');
const _geometry = MethodChannel('webview_example/native_test');

Widget buildSharedEngineTestToolbar(
        BuildContext context, Webview webview, WebviewNavigationState state) =>
    _TestToolbar(webview: webview, state: state);

void registerSharedEngineTests() {
  testWidgets('system titlebar visibility leaves no reserved space when hidden',
      (tester) async {
    await tester.pumpWidget(
      const WebviewWindowApp(
        titleBar:
            WebviewTitleBarConfiguration(builder: buildSharedEngineTestToolbar),
        child: MaterialApp(home: SizedBox.shrink()),
      ),
      wrapWithView: false,
    );
    await tester.runAsync(() async {
      await titleBarInitialization;
      for (final system in [true, false]) {
        for (final toolbar in [true, false]) {
          final title = 'Titlebar visibility $system $toolbar';
          final view = await WebviewWindow.create(
            titleBar: toolbar
                ? const WebviewTitleBarConfiguration(
                    topPadding: 24, builder: buildSharedEngineTestToolbar)
                : const WebviewTitleBarConfiguration.none(),
            configuration: CreateConfiguration(
              title: title,
              showSystemTitleBar: system,
            ),
          );
          try {
            final geometry = (await _geometry.invokeMapMethod<String, dynamic>(
              'inspect',
              {'title': title},
            ))!;
            expect(geometry['titled'], system);
            expect(geometry['closeButtonVisible'], system);
            expect(geometry['canBecomeKey'], isTrue);
            if (system && !toolbar) {
              expect(geometry['fullSizeContentView'], isFalse);
              expect(geometry['transparentTitlebar'], isFalse);
              expect(geometry['webTopInWindow'],
                  lessThanOrEqualTo(geometry['contentLayoutTop'] as num));
            }
            expect(geometry['webWidth'], geometry['contentWidth']);
            final reserved = (geometry['contentHeight'] as num) -
                (geometry['webHeight'] as num);
            expect(reserved, toolbar ? (system ? 64 : 40) : 0);
          } finally {
            view.close();
            await view.onClose.timeout(const Duration(seconds: 10));
          }
        }
      }
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('native shared titlebars route and survive close/recreate', (
    tester,
  ) async {
    await tester.pumpWidget(
      const WebviewWindowApp(
        titleBar:
            WebviewTitleBarConfiguration(builder: buildSharedEngineTestToolbar),
        child: MaterialApp(home: SizedBox.shrink()),
      ),
      wrapWithView: false,
    );
    await tester.runAsync(() async {
      await titleBarInitialization;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '''<!doctype html><title>${request.uri.path}</title>
<input id="input"><button id="button" onclick="window.clicked=true">Click</button>
<a id="next" href="${request.uri.path}/next">Next</a>''',
        );
        await request.response.close();
      });
      final open = <Webview>[];
      var serial = 0;
      Future<Map> nativeState() async =>
          Map.from((await _native.invokeMethod<Map>('debugTitleBarState'))!);
      Future<Webview> create({bool toolbar = true}) async {
        final view = await WebviewWindow.create(
          titleBar: toolbar ? null : const WebviewTitleBarConfiguration.none(),
          configuration: CreateConfiguration(
            title: 'Integration browser ${++serial}',
            windowWidth: 640,
            windowHeight: 480,
          ),
        ).timeout(const Duration(seconds: 20));
        open.add(view);
        return view;
      }

      Future<void> close(Webview view) async {
        view.close();
        view.close();
        await view.onClose.timeout(const Duration(seconds: 10));
        open.remove(view);
      }

      String url(String path) => 'http://127.0.0.1:${server.port}$path';
      Future<Object?> script(Webview view, String code) async {
        final value = await view.evaluateJavaScript('JSON.stringify(($code))');
        return value == null ? null : jsonDecode(value);
      }

      Future<void> waitFor(Webview view, String code, Object expected) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        Object? actual;
        do {
          actual = await script(view, code);
          if (actual == expected) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        } while (DateTime.now().isBefore(deadline));
        expect(actual, expected, reason: code);
      }

      Future<Map> toolbar(Map descriptor, String operation) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          final toolbar = _toolbars[descriptor['viewId']];
          if (toolbar != null) {
            return toolbar
                .command(operation)
                .timeout(const Duration(seconds: 10));
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        throw StateError('Toolbar did not mount: $descriptor');
      }

      Future<void> waitToolbar(
        Map descriptor,
        String key,
        Object expected,
      ) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          final state = await toolbar(descriptor, 'inspect');
          if (state[key] == expected) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect((await toolbar(descriptor, 'inspect'))[key], expected);
      }

      try {
        // The main engine is already running; a bare browser adds no Flutter view.
        final applicationEngine = PlatformDispatcher.instance.engineId;
        expect((await nativeState())['engine'], applicationEngine);
        final bare = await create(toolbar: false);
        expect((await nativeState())['views'], isEmpty);
        bare.launch(url('/bare'));
        await waitFor(bare, 'document.title', '/bare');
        await close(bare);

        final first = await create();
        first.launch(url('/first'));
        final second = await create();
        second.launch(url('/second'));
        await waitFor(first, 'document.title', '/first');
        await waitFor(second, 'document.title', '/second');
        final initial = await nativeState();
        final engine = initial['engine'];
        expect(engine, applicationEngine);
        final descriptors = (initial['views'] as List).cast<Map>();
        expect(descriptors, hasLength(2));
        expect(descriptors.map((d) => d['viewId']),
            isNot(contains(initial['mainViewId'])));
        final firstBar = descriptors[0];
        final secondBar = descriptors[1];
        expect(firstBar['viewId'], isNot(secondBar['viewId']));
        expect(firstBar['webViewId'], isNot(secondBar['webViewId']));
        await waitToolbar(firstBar, 'url', url('/first'));
        await waitToolbar(secondBar, 'url', url('/second'));

        await first.evaluateJavaScript(
          "document.getElementById('next').click()",
        );
        await waitFor(first, 'document.title', '/first/next');
        await waitToolbar(firstBar, 'canGoBack', true);
        await toolbar(firstBar, 'back');
        await waitFor(first, 'document.title', '/first');
        await waitToolbar(firstBar, 'canGoForward', true);
        await toolbar(firstBar, 'forward');
        await waitFor(first, 'document.title', '/first/next');
        expect(await script(second, 'document.title'), '/second');
        await waitToolbar(secondBar, 'url', url('/second'));

        // DOM interaction asserts WKWebView behavior, not native key delivery.
        await first.evaluateJavaScript('''
          document.getElementById('input').focus();
          document.getElementById('input').value = 'integration input';
          document.getElementById('button').click();
        ''');
        expect(await script(first, 'document.activeElement.id'), 'input');
        expect(
          await script(first, "document.getElementById('input').value"),
          'integration input',
        );
        expect(await script(first, 'window.clicked'), true);
        await toolbar(secondBar, 'stop');
        await toolbar(firstBar, 'reload');
        await waitFor(first, "document.getElementById('input').value", '');

        final width = await script(second, 'innerWidth') as num;
        final height = await script(second, 'innerHeight') as num;
        await _geometry.invokeMethod('resize', {
          'title': 'Integration browser 3',
          'width': 820.0,
          'height': 620.0,
        });
        await waitFor(
          second,
          'innerWidth > $width && innerHeight > $height',
          true,
        );
        expect((await nativeState())['views'], hasLength(2));

        // Closing through the toolbar exercises the same-isolate command route.
        await toolbar(firstBar, 'close');
        await first.onClose.timeout(const Duration(seconds: 10));
        open.remove(first);
        expect((await nativeState())['views'], hasLength(1));
        await toolbar(secondBar, 'reload');
        await waitFor(second, 'document.title', '/second');
        for (var round = 0; round < 20; round++) {
          final view = await create();
          if (round < 10) {
            view.launch(url('/cycle$round'));
            await waitFor(view, 'document.title', '/cycle$round');
          }
          await close(view);
          final state = await nativeState();
          expect(state['engine'], engine);
          expect(state['views'], hasLength(1));
        }
        await close(second);
        expect((await nativeState())['views'], isEmpty);
        final reopened = await create();
        reopened.launch(url('/reopened'));
        await waitFor(reopened, 'document.title', '/reopened');
        final finalState = await nativeState();
        expect(finalState['engine'], engine);
        await waitToolbar(
          (finalState['views'] as List).single as Map,
          'url',
          url('/reopened'),
        );
        await close(reopened);
        expect((await nativeState())['views'], isEmpty);
      } finally {
        for (final view in List.of(open)) {
          await close(view);
        }
        await server.close(force: true);
        FocusManager.instance.applyFocusChangesIfNeeded();
      }
    });
    await tester.pump();
  }, skip: !Platform.isMacOS);
}

class _TestToolbar extends StatefulWidget {
  const _TestToolbar({required this.webview, required this.state});
  final Webview webview;
  final WebviewNavigationState state;

  @override
  State<_TestToolbar> createState() => _TestToolbarState();
}

class _TestToolbarState extends State<_TestToolbar> {
  int? _viewId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewId = View.of(context).viewId;
    _toolbars[_viewId!] = this;
  }

  Future<Map> command(String operation) async {
    final state = widget.state;
    final reply = {
      'url': state.url,
      'canGoBack': state.canGoBack,
      'canGoForward': state.canGoForward,
      'isLoading': state.isLoading,
    };
    switch (operation) {
      case 'back':
        await widget.webview.back();
      case 'forward':
        await widget.webview.forward();
      case 'reload':
        await widget.webview.reload();
      case 'stop':
        await widget.webview.stop();
      case 'close':
        widget.webview.close();
    }
    return reply;
  }

  @override
  void dispose() {
    _toolbars.remove(_viewId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(widget.state.url ?? 'Waiting for native page');
}
