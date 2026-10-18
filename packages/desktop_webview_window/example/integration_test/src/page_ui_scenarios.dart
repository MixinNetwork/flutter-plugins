import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Implemented by the example runner's native test channel.
const _native = MethodChannel('webview_example/native_test');

Future<void> _until(FutureOr<bool> Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<Map<String, Object?>?> _sheet(Webview view) =>
    _native.invokeMapMethod<String, Object?>(
        'sheet', {'handle': view.nativeWindowHandle});

Future<Map<String, Object?>> _waitForSheet(Webview view) async {
  Map<String, Object?>? sheet;
  await _until(() async => (sheet = await _sheet(view)) != null, 'sheet');
  return sheet!;
}

Future<void> _endSheet(Webview view, [int index = 0]) => _native.invokeMethod(
    'endSheet', {'handle': view.nativeWindowHandle, 'index': index});

/// Native UI the page opens itself: JavaScript dialogs, file panels and
/// downloads. Requires the example runner's native test channel.
void registerPageUiTests() {
  late HttpServer server;
  final views = <Webview>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
          '<!doctype html><title>${request.uri.path}</title><body></body>');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<void> runScenario(
      WidgetTester tester, Future<void> Function() body) async {
    await tester.pumpWidget(const SizedBox.shrink());
    try {
      await tester.runAsync(() async {
        try {
          await body();
        } finally {
          for (final view in List.of(views)) {
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

  Future<Webview> open(String path) async {
    final view = await WebviewWindow.create(
      configuration: const CreateConfiguration(windowWidth: 480),
    ).timeout(const Duration(seconds: 30));
    views.add(view);
    await view.launch(url(path));
    await _until(
        () async => await view.evaluateJavaScript('location.pathname') == path,
        path);
    return view;
  }

  // Windows and Linux show their WebView's own dialogs.
  final dialogsSkip = !Platform.isMacOS;

  testWidgets('alert waits for the user', (tester) async {
    await runScenario(tester, () async {
      final view = await open('/alert');
      // A dialog blocks the page, so open it outside evaluateJavaScript.
      await view.evaluateJavaScript(
          "setTimeout(() => { alert('hello'); window.done = true; })");
      final sheet = await _waitForSheet(view);
      expect(sheet['kind'], 'alert');
      expect(sheet['buttons'], hasLength(1));
      await _endSheet(view, 0);
      await _until(
          () async => await view.evaluateJavaScript('window.done') == true,
          'alert returned');
    });
  }, skip: dialogsSkip);

  testWidgets('confirm returns the chosen button', (tester) async {
    await runScenario(tester, () async {
      final view = await open('/confirm');
      for (final (index, expected) in [(1, false), (0, true)]) {
        await view.evaluateJavaScript(
            "window.answer = undefined; setTimeout(() => { window.answer = confirm('sure?'); })");
        final sheet = await _waitForSheet(view);
        expect(sheet['buttons'], hasLength(2));
        await _endSheet(view, index);
        await _until(
            () async =>
                await view.evaluateJavaScript('window.answer') == expected,
            'confirm returned $expected');
      }
    });
  }, skip: dialogsSkip);

  testWidgets('closing the window ends an open dialog', (tester) async {
    await runScenario(tester, () async {
      final view = await open('/close-with-alert');
      await view.evaluateJavaScript("setTimeout(() => alert('open'))");
      await _waitForSheet(view);
      await view.close();
      await view.onClose.timeout(const Duration(seconds: 10));
      views.remove(view);
    });
  }, skip: dialogsSkip);

  testWidgets('a file input opens a panel and a cancel reaches the page',
      (tester) async {
    await runScenario(tester, () async {
      final view = await open('/upload');
      await view.evaluateJavaScript('''
        const input = document.createElement('input');
        input.type = 'file';
        input.multiple = true;
        input.addEventListener('cancel', () => window.cancelled = true);
        document.body.append(input);
        input.click();
      ''');
      expect((await _waitForSheet(view))['kind'], 'panel');
      await _endSheet(view);
      await _until(
          () async => await view.evaluateJavaScript('window.cancelled') == true,
          'cancel event');
    });
  }, skip: dialogsSkip);
}
