import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _waitFor(Webview view, String script, Object? expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  Object? actual;
  do {
    actual = await view.evaluateJavaScript(script);
    if (actual == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(deadline));
  expect(actual, expected, reason: script);
}

Future<void> _waitForError(List<WebviewLoadError> errors) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (errors.isEmpty && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  // Give a duplicate report time to arrive.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  expect(errors, hasLength(1), reason: '$errors');
}

/// Cross-platform behavior of the bridge: page messaging, asynchronous
/// navigation decisions, typed script results and the native window handle.
void registerBridgeTests() {
  late HttpServer server;
  final views = <Webview>[];

  late HttpServer frameServer;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    frameServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // dart:io sends X-Frame-Options: SAMEORIGIN by default.
    frameServer.defaultResponseHeaders.removeAll('x-frame-options');
    Future<void> respond(HttpRequest request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(switch (request.uri.path) {
        // Another port is another origin.
        '/with-frame' => '<!doctype html><title>with-frame</title><body>'
            '<iframe src="http://127.0.0.1:'
            '${request.uri.queryParameters['port']}/frame"></iframe>',
        '/frame' => '<!doctype html><script>'
            'const forged = JSON.stringify({name: "ping", data: "frame"});'
            'try { webkit.messageHandlers.desktopWebview.postMessage(forged); }'
            ' catch (_) {}'
            'try { chrome.webview.postMessage(forged); } catch (_) {}'
            'try { desktopWebview.postMessage("ping", "frame"); } catch (_) {}'
            'parent.postMessage("sent", "*");'
            '</script>',
        _ => '<!doctype html><title>${request.uri.path}</title><body></body>',
      });
      await request.response.close();
    }

    server.listen(respond);
    frameServer.listen(respond);
  });

  tearDown(() async {
    await server.close(force: true);
    await frameServer.close(force: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  // Browser windows take focus from the application window. Mount a tree
  // first and run real asynchronous work outside the fake-async zone, so focus
  // updates complete before the test binding resets its FocusManager.
  Future<void> runScenario(
      WidgetTester tester, Future<void> Function() body) async {
    await tester.pumpWidget(const SizedBox.shrink());
    try {
      await tester.runAsync(() async {
        try {
          await body();
        } finally {
          // Close before testWidgets disposes its FocusManager. Native focus
          // changes caused by closing a browser still belong to this test.
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

  Future<Webview> create() async {
    final view = await WebviewWindow.create(
      configuration: const CreateConfiguration(windowWidth: 480),
    ).timeout(const Duration(seconds: 30));
    views.add(view);
    return view;
  }

  testWidgets('page and Dart exchange messages through one bridge API',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      final received = Completer<Object?>();
      String? origin;
      view.addJavaScriptHandler('ping', (data, from) {
        origin = from;
        received.complete(data);
      });
      await view.launch(url('/bridge'));
      await _waitFor(view, 'location.pathname', '/bridge');
      await _waitFor(view, 'typeof window.desktopWebview', 'object');
      await view.evaluateJavaScript('''
      window.desktopWebview.addEventListener('pong', data => {
        window.pong = data;
      });
      window.desktopWebview.postMessage('ping', {value: 42, list: [1, 'a']});
    ''');
      expect(await received.future.timeout(const Duration(seconds: 10)), {
        'value': 42,
        'list': [1, 'a'],
      });
      expect(origin, 'http://127.0.0.1:${server.port}');
      await view.postMessage('pong', {'ok': true});
      await _waitFor(view, 'window.pong && window.pong.ok', true);
    });
  });

  testWidgets('only the top-level document reaches JavaScript handlers',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      final received = <Object?>[];
      view.addJavaScriptHandler('ping', (data, origin) {
        received.add([data, origin]);
      });
      await view.addScriptToExecuteOnDocumentCreated(
          "addEventListener('message', e => { window.frameSent = e.data; });");
      await view.launch(url('/with-frame?port=${frameServer.port}'));
      await _waitFor(view, 'window.frameSent', 'sent');
      await view.evaluateJavaScript(
          "window.desktopWebview.postMessage('ping', 'top')");
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (received.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // Frame messages, if any were accepted, would have arrived first.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(received, [
        ['top', 'http://127.0.0.1:${server.port}'],
      ]);
    });
  });

  testWidgets('failed top-level loads are reported, declined ones are not',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      final errors = <WebviewLoadError>[];
      view.onLoadError.listen(errors.add);
      await view
          .setOnUrlRequestCallback((value) => !value.contains('/blocked'));
      await view.launch(url('/start'));
      await _waitFor(view, 'location.pathname', '/start');
      await view.launch(url('/blocked'));
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(errors, isEmpty);

      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final refused = 'http://127.0.0.1:${socket.port}/';
      await socket.close();
      await view.launch(refused);
      await _waitForError(errors);
      expect(errors.single.url, refused);
      expect(errors.single.kind, WebviewLoadErrorKind.connection,
          reason: '$errors');
      expect(errors.single.description, isNotEmpty);

      errors.clear();
      await view.launch('http://unknown-host.invalid/');
      await _waitForError(errors);
      // A local DNS proxy can answer for any name and fail the connection.
      expect(
          errors.single.kind,
          anyOf(WebviewLoadErrorKind.hostLookup,
              WebviewLoadErrorKind.connection));
    });
  });

  testWidgets('script results keep their JSON type', (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      await view.launch(url('/types'));
      await _waitFor(view, 'location.pathname', '/types');
      expect(await view.evaluateJavaScript('1 + 1'), 2);
      expect(await view.evaluateJavaScript("'text'"), 'text');
      expect(await view.evaluateJavaScript('({a: [true, null]})'), {
        'a': [true, null],
      });
      expect(await view.evaluateJavaScript('null'), isNull);
    });
  });

  testWidgets('a declined navigation is cancelled on every platform',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      final requested = <String>[];
      await view.setOnUrlRequestCallback((value) {
        requested.add(value);
        return !value.contains('/blocked');
      });
      await view.launch(url('/allowed'));
      await _waitFor(view, 'location.pathname', '/allowed');
      await view.launch(url('/blocked'));
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(await view.evaluateJavaScript('location.pathname'), '/allowed');
      expect(requested, containsAll([url('/allowed'), url('/blocked')]));
      // The state reports the current page, not the declined request.
      expect(view.navigationState.value.url, url('/allowed'));
    });
  });

  testWidgets('navigations to application schemes reach Dart', (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      final requested = Completer<String>();
      await view.setOnUrlRequestCallback((value) {
        if (value.startsWith('mixin:') && !requested.isCompleted) {
          requested.complete(value);
        }
        return !value.startsWith('mixin:');
      });
      await view.launch(url('/scheme'));
      await _waitFor(view, 'location.pathname', '/scheme');
      await view.evaluateJavaScript("location.href = 'mixin://pay?x=1'");
      expect(await requested.future.timeout(const Duration(seconds: 10)),
          'mixin://pay?x=1');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(await view.evaluateJavaScript('location.pathname'), '/scheme');
    });
  });

  testWidgets('native window handle is valid until the window closes',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      expect(view.nativeWindowHandle, isNot(0));
      await view.close();
      await view.onClose.timeout(const Duration(seconds: 10));
      views.remove(view);
      expect(view.nativeWindowHandle, 0);
    });
  });
}
