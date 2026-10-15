import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _geometry = MethodChannel('webview_example/native_test');

void registerMacOSWebviewTests() {
  testWidgets('titlebar space is reserved only when enabled', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      for (final toolbar in [true, false]) {
        final title = 'Titlebar layout $toolbar';
        final view = await WebviewWindow.create(
          configuration: CreateConfiguration(
            title: title,
            titleBarHeight: toolbar ? 44 : 0,
            titleBarTopPadding: toolbar ? 24 : 0,
          ),
        );
        try {
          final geometry = (await _geometry.invokeMapMethod<String, dynamic>(
            'inspect',
            {'title': title},
          ))!;
          expect(geometry['webWidth'], geometry['contentWidth']);
          final reserved = (geometry['contentHeight'] as num) -
              (geometry['webHeight'] as num);
          expect(reserved, toolbar ? 68 : 0);
        } finally {
          view.close();
          await view.onClose.timeout(const Duration(seconds: 10));
        }
      }
    });
    await tester.pump();
  });

  testWidgets('native browsers and titlebars stay independent through reuse',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response
            .write('''<!doctype html><title>${request.uri.path}</title>
<input id="input"><button id="button" onclick="window.clicked=true">Click</button>
<a id="next" href="${request.uri.path}/next">Next</a>''');
        await request.response.close();
      });
      final open = <Webview, String>{};
      var serial = 0;
      Future<Webview> create({bool toolbar = true}) async {
        final title = 'Integration browser ${++serial}';
        final view = await WebviewWindow.create(
          configuration: CreateConfiguration(
            title: title,
            windowWidth: 640,
            windowHeight: 480,
            titleBarHeight: toolbar ? 44 : 0,
            titleBarTopPadding: toolbar ? 24 : 0,
          ),
        ).timeout(const Duration(seconds: 20));
        open[view] = title;
        return view;
      }

      Future<void> close(Webview view) async {
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

      Future<Map<String, dynamic>> toolbar(
          Webview view, String operation) async {
        return (await _geometry.invokeMapMethod<String, dynamic>(
          'titlebar',
          {'title': open[view], 'operation': operation},
        ).timeout(const Duration(seconds: 10)))!;
      }

      Future<void> waitToolbar(
          Webview view, String key, Object expected) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        Object? actual;
        do {
          try {
            actual = (await toolbar(view, 'inspect'))[key];
            if (actual == expected) return;
          } on MissingPluginException {
            // A new titlebar engine may not have mounted its widget yet.
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        } while (DateTime.now().isBefore(deadline));
        expect(actual, expected, reason: 'Titlebar $key');
      }

      try {
        final bare = await create(toolbar: false);
        bare.launch(url('/bare'));
        await waitFor(bare, 'document.title', '/bare');
        await close(bare);

        final first = await create();
        // The current per-window engine API has no state replay. Wait for its
        // toolbar to mount before starting navigation, as a user would.
        await waitToolbar(first, 'isLoading', false);
        first.launch(url('/first'));
        final second = await create();
        await waitToolbar(second, 'isLoading', false);
        second.launch(url('/second'));
        await waitFor(first, 'document.title', '/first');
        await waitFor(second, 'document.title', '/second');
        await waitToolbar(first, 'url', url('/first'));
        await waitToolbar(second, 'url', url('/second'));

        await first
            .evaluateJavaScript("document.getElementById('next').click()");
        await waitFor(first, 'document.title', '/first/next');
        await waitToolbar(first, 'canGoBack', true);
        await toolbar(first, 'back');
        await waitFor(first, 'document.title', '/first');
        await waitToolbar(first, 'canGoForward', true);
        await toolbar(first, 'forward');
        await waitFor(first, 'document.title', '/first/next');
        expect(await script(second, 'document.title'), '/second');
        await waitToolbar(second, 'url', url('/second'));

        // This verifies DOM interaction, not physical keyboard/mouse delivery.
        await first.evaluateJavaScript('''
          document.getElementById('input').focus();
          document.getElementById('input').value = 'integration input';
          document.getElementById('button').click();
        ''');
        expect(await script(first, 'document.activeElement.id'), 'input');
        expect(await script(first, "document.getElementById('input').value"),
            'integration input');
        expect(await script(first, 'window.clicked'), true);
        await toolbar(second, 'stop');
        await toolbar(first, 'reload');
        await waitFor(first, "document.getElementById('input').value", '');

        final width = await script(second, 'innerWidth') as num;
        final height = await script(second, 'innerHeight') as num;
        await _geometry.invokeMethod('resize', {
          'title': open[second],
          'width': 820.0,
          'height': 620.0,
        });
        await waitFor(
            second, 'innerWidth > $width && innerHeight > $height', true);

        await toolbar(first, 'close');
        await first.onClose.timeout(const Duration(seconds: 10));
        open.remove(first);
        await toolbar(second, 'reload');
        await waitFor(second, 'document.title', '/second');
        for (var round = 0; round < 20; round++) {
          final view = await create();
          if (round < 10) {
            view.launch(url('/cycle$round'));
            await waitFor(view, 'document.title', '/cycle$round');
          }
          await close(view);
        }
        await waitToolbar(second, 'url', url('/second'));
        await close(second);
        final reopened = await create();
        await waitToolbar(reopened, 'isLoading', false);
        reopened.launch(url('/reopened'));
        await waitFor(reopened, 'document.title', '/reopened');
        await waitToolbar(reopened, 'url', url('/reopened'));
        await close(reopened);
      } finally {
        for (final view in List.of(open.keys)) {
          await close(view);
        }
        await server.close(force: true);
        FocusManager.instance.applyFocusChangesIfNeeded();
      }
    });
    await tester.pump();
  });
}
