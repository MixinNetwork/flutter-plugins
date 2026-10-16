import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Object?> readScript(Webview view, String script) async {
  final result = await view.evaluateJavaScript(script);
  return result == null ? null : jsonDecode(result);
}

Future<void> waitForScript(Webview view, String script, Object expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  Object? actual;
  do {
    actual = await readScript(view, script);
    if (actual == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(deadline));
  expect(actual, expected, reason: script);
}

void registerWindowsWebviewTests() {
  late HttpServer server;
  late Directory profile;
  final views = <Webview>[];
  final requests = <String>[];

  setUp(() async {
    requests.clear();
    profile = await Directory.systemTemp.createTemp('webview-regression-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add('${request.method} ${request.uri.path} $body');
      if (request.uri.path == '/redirect') {
        request.response.statusCode = 302;
        request.response.headers.set('Location', '/blocked');
        await request.response.close();
        return;
      }
      request.response.headers.set('Cache-Control', 'max-age=3600');
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><title>WebView regression</title>',
      );
      await request.response.close();
    });
  });

  Future<void> closeView(Webview view) async {
    view.close();
    // close() is fire-and-forget on Windows. A following call on the same
    // channel waits until native window destruction has been processed.
    await WebviewWindow.isWebviewAvailable();
  }

  Future<void> closeViews() async {
    for (final view in views) {
      await closeView(view);
    }
    views.clear();
    // Let native activation events settle before Flutter disposes its focus tree.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    FocusManager.instance.applyFocusChangesIfNeeded();
  }

  tearDown(() async {
    await server.close(force: true);
    // WebView2 may retain the profile lock until its browser process exits.
  });

  Future<void> runScenario(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      try {
        await body();
      } finally {
        await closeViews();
      }
    });
    await tester.pump();
  }

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<Webview> create({bool hidden = false, bool denyMedia = false}) async {
    final view = await WebviewWindow.create(
      titleBar: const WebviewTitleBarConfiguration.none(),
      configuration: CreateConfiguration(
        openHidden: hidden,
        denyCameraAndMicrophone: denyMedia,
        userDataFolderWindows: profile.path,
      ),
    );
    views.add(view);
    return view;
  }

  testWidgets('a newer explicit launch replaces an allowed URL request', (
    tester,
  ) async {
    await runScenario(tester, () async {
      final view = await create();
      var replaced = false;
      view.setOnUrlRequestCallback((requested) {
        if (requested == url('/old') && !replaced) {
          replaced = true;
          view.launch(url('/new'), triggerOnUrlRequestEvent: false);
        }
        return true;
      });
      view.launch(url('/old'));
      await waitForScript(view, 'location.pathname', '/new');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(await readScript(view, 'location.pathname'), '/new');
    });
  });

  testWidgets('a hidden page becomes visible when maximized and activated', (
    tester,
  ) async {
    await runScenario(tester, () async {
      final view = await create(hidden: true);
      view.launch(url('/visibility'), triggerOnUrlRequestEvent: false);
      await waitForScript(view, 'location.pathname', '/visibility');
      await waitForScript(view, 'document.visibilityState', 'hidden');
      await view.bringToForeground(maximized: true);
      await waitForScript(view, 'document.visibilityState', 'visible');
      await view.setWebviewWindowVisibility(false);
      await waitForScript(view, 'document.visibilityState', 'hidden');
      await view.bringToForeground(maximized: true);
      await waitForScript(view, 'document.visibilityState', 'visible');
    });
  });

  testWidgets('media denial does not persist in the shared profile', (
    tester,
  ) async {
    await runScenario(tester, () async {
      final denied = await create(denyMedia: true);
      denied.launch(url('/permissions'), triggerOnUrlRequestEvent: false);
      await waitForScript(denied, 'location.pathname', '/permissions');
      for (final constraint in ['video', 'audio']) {
        await denied.evaluateJavaScript('''
          window.mediaResult = 'pending';
          navigator.mediaDevices.getUserMedia({$constraint: true}).then(
            stream => {
              stream.getTracks().forEach(track => track.stop());
              window.mediaResult = 'allowed';
            },
            error => { window.mediaResult = error.name; }
          );
        ''');
        await waitForScript(denied, 'window.mediaResult', 'NotAllowedError');
      }
      await closeView(denied);
      views.remove(denied);

      final normal = await create();
      normal.launch(url('/permissions'), triggerOnUrlRequestEvent: false);
      await waitForScript(normal, 'location.pathname', '/permissions');
      for (final permission in ['camera', 'microphone']) {
        await normal.evaluateJavaScript('''
          window.permissionResult = 'pending';
          navigator.permissions.query({name: '$permission'}).then(
            result => { window.permissionResult = result.state; }
          );
        ''');
        await waitForScript(normal, 'window.permissionResult', 'prompt');
      }
    });
  });
  testWidgets('allowed form preserves POST body exactly once', (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      view.setOnUrlRequestCallback((_) => true);
      view.launch(url('/form'));
      await waitForScript(view, 'location.pathname', '/form');
      await view.evaluateJavaScript("""
        const form = document.createElement('form');
        form.method = 'POST'; form.action = '/posted';
        const input = document.createElement('input');
        input.name = 'token'; input.value = 'hello world';
        form.appendChild(input); document.body.appendChild(form); form.submit();
      """);
      await waitForScript(view, 'location.pathname', '/posted');
      expect(requests.where((r) => r.contains('/posted')).toList(),
          ['POST /posted token=hello+world']);
    });
  });

  testWidgets('denied GET stays on current document', (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      view.launch(url('/initial'), triggerOnUrlRequestEvent: false);
      await waitForScript(view, 'location.pathname', '/initial');
      var denied = false;
      view.setOnUrlRequestCallback((u) {
        denied = true;
        return false;
      });
      view.launch(url('/blocked'));
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(denied, true);
      expect(requests.any((r) => r.contains('/blocked')), false);
      expect(await readScript(view, 'location.pathname'), '/initial');
    });
  });

  testWidgets('denied redirect never reaches server', (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      view.launch(url('/initial'), triggerOnUrlRequestEvent: false);
      await waitForScript(view, 'location.pathname', '/initial');
      final decisions = <String>[];
      view.setOnUrlRequestCallback((u) {
        decisions.add(u);
        return !u.endsWith('/blocked');
      });
      view.launch(url('/redirect'));
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(decisions, contains(url('/blocked')));
      expect(requests.any((r) => r.contains('/blocked')), false);
      expect(await readScript(view, 'location.pathname'), '/initial');
    });
  });

  testWidgets('denied cached navigation stays on current document',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      view.launch(url('/cached'), triggerOnUrlRequestEvent: false);
      await waitForScript(view, 'location.pathname', '/cached');
      view.launch(url('/initial'), triggerOnUrlRequestEvent: false);
      await waitForScript(view, 'location.pathname', '/initial');
      final decisions = <String>[];
      view.setOnUrlRequestCallback((u) {
        decisions.add(u);
        return false;
      });
      view.launch(url('/cached'));
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(decisions, contains(url('/cached')));
      expect(await readScript(view, 'location.pathname'), '/initial');
    });
  });

  testWidgets('denied back navigation stays on current document',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create();
      view.launch(url('/cached'), triggerOnUrlRequestEvent: false);
      await waitForScript(view, 'location.pathname', '/cached');
      view.launch(url('/initial'), triggerOnUrlRequestEvent: false);
      await waitForScript(view, 'location.pathname', '/initial');
      final decisions = <String>[];
      view.setOnUrlRequestCallback((u) {
        decisions.add(u);
        return false;
      });
      await view.back();
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(decisions, contains(url('/cached')));
      expect(await readScript(view, 'location.pathname'), '/initial');
    });
  });
}
