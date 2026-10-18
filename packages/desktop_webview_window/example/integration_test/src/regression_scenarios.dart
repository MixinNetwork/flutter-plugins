import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _native = MethodChannel('webview_example/native_test');

Future<void> _until(FutureOr<bool> Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Previously reported URL, frame and native-window lifecycle regressions.
void registerRegressionTests() {
  late HttpServer server;
  final views = <Webview>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('''<!doctype html>
<title>Regression page</title>
<body style="margin:0;background:rgb(24,160,80)">
<h1>Rendered regression page</h1>
<iframe id="frame" srcdoc="<p id='ready'>srcdoc rendered</p>"></iframe>
</body>''');
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<Webview> create({String? mode}) async {
    final view = await WebviewWindow.create(
      configuration: CreateConfiguration(
        windowWidth: 640,
        windowHeight: 480,
        composerArguments: mode,
      ),
    ).timeout(const Duration(seconds: 30));
    views.add(view);
    return view;
  }

  Future<void> loaded(Webview view) => _until(
      () =>
          view.navigationState.value.title == 'Regression page' &&
          !view.navigationState.value.isLoading,
      'a real document finished loading');

  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    await tester.pumpWidget(const SizedBox.shrink());
    try {
      await tester.runAsync(() async {
        try {
          await body();
        } finally {
          for (final view in views) {
            await view.close();
            await view.onClose.timeout(const Duration(seconds: 10));
          }
          views.clear();
        }
      });
    } finally {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('SPA push replace hash and history update navigationState (#418)',
      (tester) async {
    await run(tester, () async {
      final view = await create();
      final observed = <String?>[];
      void record() => observed.add(view.navigationState.value.url);
      view.navigationState.addListener(record);
      try {
        await view.launch(url('/start'));
        await loaded(view);
        Future<void> change(String script, String path) async {
          await view.evaluateJavaScript(script);
          await _until(() => view.navigationState.value.url == url(path), path);
          expect(observed, contains(url(path)));
        }

        await change("history.pushState({}, '', '/spa-one')", '/spa-one');
        await change(
            "history.replaceState({}, '', '/spa-replaced')", '/spa-replaced');
        await change("location.hash = 'section'", '/spa-replaced#section');
        await view.evaluateJavaScript('history.back()');
        await _until(
            () => view.navigationState.value.url == url('/spa-replaced'),
            'back from hash');
        await view.evaluateJavaScript('history.back()');
        await _until(() => view.navigationState.value.url == url('/start'),
            'back from pushState');
        await view.evaluateJavaScript('history.forward()');
        await _until(
            () => view.navigationState.value.url == url('/spa-replaced'),
            'forward to replaced entry');
      } finally {
        view.navigationState.removeListener(record);
      }
    });
  });

  testWidgets('macOS renders srcdoc and survives reopen (#357, #290)',
      (tester) async {
    await run(tester, () async {
      for (var round = 0; round < 3; round++) {
        final view = await create();
        await view.launch(url('/document$round'));
        await loaded(view);
        await _until(
            () async =>
                await view.evaluateJavaScript(
                    "document.getElementById('frame').contentDocument"
                    "?.getElementById('ready')?.textContent") ==
                'srcdoc rendered',
            'srcdoc frame content');
        expect(
            await view.evaluateJavaScript(
                "document.getElementById('frame').contentWindow.location.href"),
            'about:srcdoc');
        final pixel = await _native.invokeListMethod<double>(
            'webviewPixel', {'handle': view.nativeWindowHandle});
        expect(pixel, isNotNull);
        expect(pixel![1], greaterThan(pixel[0] + 0.2));
        expect(pixel[1], greaterThan(pixel[2] + 0.1));
        await view.close();
        await view.onClose.timeout(const Duration(seconds: 10));
        views.remove(view);
      }
    });
  }, skip: !Platform.isMacOS);

  testWidgets(
      'native close and API close survive repeated reopen (#457, #478, #363, #410)',
      (tester) async {
    await run(tester, () async {
      for (var round = 0; round < 30; round++) {
        final view = await create();
        await view.launch(url('/close$round'));
        await loaded(view);
        if (round.isEven) {
          await _native
              .invokeMethod('nativeClose', {'handle': view.nativeWindowHandle});
        } else {
          await view.close();
        }
        await view.onClose.timeout(const Duration(seconds: 10));
        expect(view.nativeWindowHandle, 0);
        views.remove(view);
      }
      // The main engine must still be able to render after all child windows close.
    });
    await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr, child: Text('Main engine survived')));
    expect(find.text('Main engine survived'), findsOneWidget);
  });

  testWidgets('Windows minimizes before WebView2 initialization (#366)',
      (tester) async {
    await run(tester, () async {
      for (var round = 0; round < 10; round++) {
        final view = await create(mode: 'minimize:compose');
        final events = await _native.invokeListMethod<String>('composerEvents');
        expect(events, contains('${view.id}:minimized-before-create'));
        await _native
            .invokeMethod('restore', {'handle': view.nativeWindowHandle});
        await view.launch(url('/minimized$round'));
        await loaded(view);
        await view.close();
        await view.onClose.timeout(const Duration(seconds: 10));
        views.remove(view);
      }
    });
  }, skip: !Platform.isWindows);

  testWidgets('Windows native close resolves pending create (#367)',
      (tester) async {
    await run(tester, () async {
      for (var round = 0; round < 20; round++) {
        final view = await create(mode: 'close:initializing');
        // A native timer closes the visible shell while WebView2 starts.
        expect(view.nativeWindowHandle, 0);
        await view.onClose.timeout(const Duration(seconds: 10));
        views.remove(view);
        final events = await _native.invokeListMethod<String>('composerEvents');
        expect(events, contains('${view.id}:native-close-during-create'));
      }
    });
  }, skip: !Platform.isWindows);

  // Opt-in measurement: a real ten-second playlist, without a flaky CI limit.
  testWidgets('playlist memory samples after warmup (#310)', (tester) async {
    await run(tester, () async {
      const cycles = 30;
      final samples = <int>[];
      for (var round = 0; round < cycles + 5; round++) {
        final view = await create();
        await view.launch(url('/memory$round'));
        await loaded(view);
        await Future<void>.delayed(const Duration(seconds: 10));
        await view.close();
        await view.onClose.timeout(const Duration(seconds: 10));
        views.remove(view);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (round >= 5) samples.add(ProcessInfo.currentRss);
        // Include PID for correlating browser child-process measurements.
        // ignore: avoid_print
        print('DWW_MEMORY ${jsonEncode({
              'round': round,
              'pid': pid,
              'rss': ProcessInfo.currentRss
            })}');
      }
      expect(samples, hasLength(cycles));
    });
  },
      skip: !const bool.fromEnvironment('DWW_MEMORY_PROBE'),
      timeout: const Timeout(Duration(minutes: 10)));
}
