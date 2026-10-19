import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webview_window_example/demo_page_server.dart';
import 'package:webview_window_example/demo_state.dart';

const _native = MethodChannel('webview_example/native_test');

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Background condition timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

void registerBackgroundTests() {
  _registerAppThemeTest();
  if (Platform.isLinux) {
    _registerLinuxBackgroundTests();
    return;
  }
  if (!Platform.isMacOS && !Platform.isWindows) return;

  testWidgets('appearance stays per window and survives navigation',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
            '<title>${request.uri.path}</title><body>Light-only page</body>');
        await request.response.close();
      });
      final views = <Webview>[];
      const script = 'matchMedia("(prefers-color-scheme: dark)").matches';
      final systemView = await WebviewWindow.create(
          configuration: const CreateConfiguration(openHidden: true));
      final systemDark = await systemView.evaluateJavaScript(script);
      await systemView.close();
      await systemView.onClose;
      try {
        for (final brightness in [Brightness.dark, Brightness.light]) {
          final view = await WebviewWindow.create(
            configuration: CreateConfiguration(
                windowWidth: 400, windowHeight: 300, brightness: brightness),
          );
          views.add(view);
          await _until(() async =>
              await view.evaluateJavaScript(script) ==
              (brightness == Brightness.dark));
          if (Platform.isWindows) {
            final startup = (await _native.invokeListMethod<double>(
                'hostErasePixel', {'handle': view.nativeWindowHandle}))!;
            expect(
                startup,
                everyElement(brightness == Brightness.dark
                    ? lessThan(0.3)
                    : greaterThan(0.9)));
            final blankLoaded = Completer<void>();
            var started = false;
            void onBlankNavigation() {
              if (view.navigationState.value.isLoading) started = true;
              if (started &&
                  !view.navigationState.value.isLoading &&
                  !blankLoaded.isCompleted) {
                blankLoaded.complete();
              }
            }

            view.navigationState.addListener(onBlankNavigation);
            try {
              await view.launch('about:blank');
              await blankLoaded.future.timeout(const Duration(seconds: 20));
              await view.evaluateJavaScript(
                  'document.write("<body>Light-only blank document</body>"); document.close();');
              expect(await view.evaluateJavaScript('document.body.textContent'),
                  'Light-only blank document');
              expect(await view.evaluateJavaScript(script),
                  brightness == Brightness.dark);
            } finally {
              view.navigationState.removeListener(onBlankNavigation);
            }
          }
          final path = '/page${views.length}';
          await view.launch('http://127.0.0.1:${server.port}$path');
          await _until(() async =>
              view.navigationState.value.title == path &&
              !view.navigationState.value.isLoading);
        }
        await _until(() async =>
            await views[0].evaluateJavaScript(script) == true &&
            await views[1].evaluateJavaScript(script) == false);
        if (Platform.isWindows) {
          final host = (await _native.invokeListMethod<double>(
              'hostErasePixel', {'handle': views[0].nativeWindowHandle}))!;
          expect(host, everyElement(lessThan(0.3)),
              reason:
                  'Resizing a dark window must not expose a white host surface');
        }
        if (Platform.isMacOS) {
          await _until(() async => !views[0].navigationState.value.isLoading);
          final light = (await _native.invokeListMethod<double>(
              'webviewPixel', {'handle': views[0].nativeWindowHandle}))!;
          expect(light[0], greaterThan(0.9));
          expect(light[3], greaterThan(0.99));
        }
        await views[0].setBrightness(null);
        await _until(() async =>
            await views[0].evaluateJavaScript(script) == systemDark);
        await views[0].setBrightness(Brightness.light);
        await _until(
            () async => await views[0].evaluateJavaScript(script) == false);
        await views[0].setBrightness(Brightness.dark);
        for (final (host, path) in [
          ('localhost', '/cross'),
          ('127.0.0.1', '/back')
        ]) {
          await views[0].launch('http://$host:${server.port}$path');
          await _until(() async =>
              views[0].navigationState.value.title == path &&
              !views[0].navigationState.value.isLoading);
          await _until(() async =>
              await views[0].evaluateJavaScript(script) == true &&
              await views[1].evaluateJavaScript(script) == false);
        }
      } finally {
        for (final view in views) {
          await view.close();
          await view.onClose;
        }
        await server.close(force: true);
      }
    });
    await tester.pumpAndSettle();
  });

  if (!Platform.isMacOS) return;
  testWidgets(
      'startup background ends after the first document, preserving light-only pages',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final cssRequested = Completer<void>();
      final releaseCss = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/slow.css') {
          cssRequested.complete();
          await releaseCss.future;
          request.response.headers.contentType = ContentType('text', 'css');
          request.response.write('html { background: #151515; color: white; }');
        } else {
          request.response.headers.contentType = ContentType.html;
          request.response.write(switch (request.uri.path) {
            '/dark' =>
              '<title>Dark</title><link rel="stylesheet" href="/slow.css"><body>Dark page</body>',
            '/scheme' =>
              '<meta name="color-scheme" content="light dark"><title>Scheme</title><body>System colors</body>',
            _ => '<title>Light</title><body>Light-only page</body>',
          });
        }
        await request.response.close();
      });
      final view = await WebviewWindow.create(
        configuration: const CreateConfiguration(
            windowWidth: 400, windowHeight: 300, brightness: Brightness.dark),
      );
      Future<List<double>> pixel(String method) async =>
          (await _native.invokeListMethod<double>(
              method, {'handle': view.nativeWindowHandle}))!;
      try {
        final startup = await pixel('startupPixel');
        expect(startup[0], lessThan(0.3));
        await view.launch('http://127.0.0.1:${server.port}/dark');
        await cssRequested.future.timeout(const Duration(seconds: 20));
        expect(view.navigationState.value.isLoading, isTrue);
        // A commit has occurred, but the render-blocking stylesheet has not
        // arrived. The startup surface must still be dark at this point.
        final waiting = await pixel('webviewPixel');
        final red = waiting[0] * waiting[3] + startup[0] * (1 - waiting[3]);
        expect(red, lessThan(0.3));
        expect(view.navigationState.value.isLoading, isTrue);
        releaseCss.complete();
        await _until(() async => !view.navigationState.value.isLoading);
        final dark = await pixel('webviewPixel');
        expect(dark[0], lessThan(0.3));
        expect(dark[3], greaterThan(0.99));
        await view.launch('http://127.0.0.1:${server.port}/scheme');
        await _until(() async =>
            view.navigationState.value.title == 'Scheme' &&
            !view.navigationState.value.isLoading);
        final scheme = await pixel('webviewPixel');
        expect(scheme[0], lessThan(0.3));
        expect(scheme[3], greaterThan(0.99));
        await view.launch('http://127.0.0.1:${server.port}/light');
        await _until(() async =>
            view.navigationState.value.title == 'Light' &&
            !view.navigationState.value.isLoading);
        Future<void> expectWhite() async {
          final light = await pixel('webviewPixel');
          expect(light[0], greaterThan(0.9));
          expect(light[3], greaterThan(0.99));
        }

        await expectWhite();
        await view.setBrightness(Brightness.light);
        await expectWhite();
        await view.setBrightness(Brightness.dark);
        await expectWhite();
      } finally {
        if (!releaseCss.isCompleted) releaseCss.complete();
        await view.close();
        await view.onClose;
        await server.close(force: true);
      }
    });
    await tester.pumpAndSettle();
  });
}

void _registerLinuxBackgroundTests() {
  testWidgets(
      'GTK uncovers painted content before the HTML stream or images finish',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final previous =
          (await _native.invokeMapMethod<String, Object?>('gtkTheme', {}))!;
      final cssRequested = Completer<void>();
      final releaseCss = Completer<void>();
      final imageRequested = Completer<void>();
      final releaseImage = Completer<void>();
      final releaseHtml = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/slow.css') {
          cssRequested.complete();
          await releaseCss.future;
          request.response.headers.contentType = ContentType('text', 'css');
          request.response.write('html { background: red; color: white; }');
        } else if (request.uri.path == '/slow.png') {
          imageRequested.complete();
          await releaseImage.future;
        } else {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<title>Slow image</title>'
              '<link rel="stylesheet" href="/slow.css">'
              '<body><p>${'Visible text ' * 100}</p>'
              '<img src="/slow.png">${' ' * 65536}');
          await request.response.flush();
          await releaseHtml.future;
        }
        await request.response.close();
      });
      Webview? view;
      try {
        await _native
            .invokeMethod('gtkTheme', {'name': 'Adwaita', 'dark': true});
        view = await WebviewWindow.create();
        final browser = view;
        Future<List<double>> visiblePixel() async =>
            (await _native.invokeListMethod<double>(
                'startupPixel', {'handle': browser.nativeWindowHandle}))!;
        await _until(() async => (await visiblePixel()).first < 0.3);
        await browser.launch('http://127.0.0.1:${server.port}/');
        await cssRequested.future.timeout(const Duration(seconds: 20));
        // Keep the render-blocking CSS pending across multiple frame clocks.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect((await visiblePixel()).first, lessThan(0.3));
        releaseCss.complete();
        await imageRequested.future.timeout(const Duration(seconds: 20));
        // Check the GTK container before requesting any offscreen WebKit
        // snapshot: page pixels alone do not prove that the window shows them.
        await _until(() async {
          final pixel = await visiblePixel();
          return pixel[0] > 0.9 && pixel[1] < 0.1;
        });
        expect(
            await browser.evaluateJavaScript(
                'performance.getEntriesByType("paint").some('
                'entry => entry.name === "first-contentful-paint")'),
            true);
        expect(
            await browser.evaluateJavaScript('document.readyState'), 'loading');
        expect(browser.navigationState.value.isLoading, isTrue);
        expect(releaseImage.isCompleted, isFalse);
        expect(releaseHtml.isCompleted, isFalse);
      } finally {
        if (!releaseCss.isCompleted) releaseCss.complete();
        if (!releaseImage.isCompleted) releaseImage.complete();
        if (!releaseHtml.isCompleted) releaseHtml.complete();
        if (view != null) {
          await view.close();
          await view.onClose;
        }
        await server.close(force: true);
        await _native.invokeMethod('gtkTheme', previous);
      }
    });
    await tester.pumpAndSettle();
  });
  testWidgets(
      'GTK startup uses the content surface, then restores the page canvas',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final previous =
          (await _native.invokeMapMethod<String, Object?>('gtkTheme', {}))!;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(switch (request.uri.path) {
          '/scheme' =>
            '<meta name="color-scheme" content="dark"><title>Scheme</title><body>System colors</body>',
          '/red' => '<html style="background:red"><title>Red</title></html>',
          _ =>
            '<title>Legacy</title><body>Black text without a background</body>',
        });
        await request.response.close();
      });
      Webview? view;
      try {
        // GtkSettings belongs to this example process; the desktop's saved
        // appearance is never changed.
        await _native
            .invokeMethod('gtkTheme', {'name': 'Adwaita', 'dark': true});
        view = await WebviewWindow.create(
          configuration:
              const CreateConfiguration(windowWidth: 400, windowHeight: 300),
        );
        final browser = view;
        Future<List<double>> canvas() async =>
            (await _native.invokeListMethod<double>(
                'startupPixel', {'handle': browser.nativeWindowHandle}))!;
        await _until(() async => (await canvas())[0] < 0.3);
        await _native
            .invokeMethod('gtkTheme', {'name': 'Adwaita', 'dark': false});
        await _until(() async => (await canvas())[0] > 0.99);
        await _native
            .invokeMethod('gtkTheme', {'name': 'Adwaita', 'dark': true});
        await _until(() async => (await canvas())[0] < 0.3);
        Future<List<double>> rendered() async =>
            (await _native.invokeListMethod<double>(
                'webviewPixel', {'handle': browser.nativeWindowHandle}))!;
        // The first document must exercise restoration as well as color-scheme.
        await browser.launch('http://127.0.0.1:${server.port}/scheme');
        await _until(() async =>
            browser.navigationState.value.title == 'Scheme' &&
            !browser.navigationState.value.isLoading);
        for (var sample = 0; sample < 5; sample++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          final scheme = await rendered();
          expect(scheme[0], lessThan(0.3),
              reason:
                  'The first dark color-scheme document needs a dark rendered canvas');
          expect(scheme[3], greaterThan(0.99));
        }
        await browser.launch('http://127.0.0.1:${server.port}/red');
        await _until(() async =>
            browser.navigationState.value.title == 'Red' &&
            !browser.navigationState.value.isLoading);
        final red = await rendered();
        expect(red[0], greaterThan(0.9));
        expect(red[1], lessThan(0.1),
            reason: 'Snapshot must capture the real red page');
        await browser.launch('http://127.0.0.1:${server.port}/');
        await _until(() async =>
            browser.navigationState.value.title == 'Legacy' &&
            !browser.navigationState.value.isLoading);
        expect(await rendered(), everyElement(greaterThan(0.99)));
        await _native
            .invokeMethod('gtkTheme', {'name': 'Adwaita', 'dark': false});
        await _native
            .invokeMethod('gtkTheme', {'name': 'Adwaita', 'dark': true});
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(await rendered(), everyElement(greaterThan(0.99)));
      } finally {
        if (view != null) {
          await view.close();
          await view.onClose;
        }
        await server.close(force: true);
        await _native.invokeMethod('gtkTheme', previous);
      }
    });
    await tester.pumpAndSettle();
  });
}

void _registerAppThemeTest() {
  testWidgets('app theme updates existing browsers and subsequent creation',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final pages = await DemoPageServer.start();
      final state = DemoState(pages);
      const script = 'matchMedia("(prefers-color-scheme: dark)").matches';
      Future<void> expectTheme(bool dark) async {
        await _until(() async {
          for (final window in state.windows) {
            if (await window.webview.evaluateJavaScript(script) != dark) {
              return false;
            }
          }
          return true;
        });
        expect(state.windows.map((window) => window.appearance),
            everyElement(dark ? ThemeMode.dark : ThemeMode.light));
      }

      try {
        await state.open();
        expect(state.windows, hasLength(1));
        await _until(() async =>
            state.windows.first.navigation.title != null &&
            !state.windows.first.navigation.isLoading);
        final systemDark =
            await state.windows.first.webview.evaluateJavaScript(script);
        await state.setThemeMode(ThemeMode.light);
        await state.open();
        expect(state.windows, hasLength(2));
        await expectTheme(false);
        await state.setThemeMode(ThemeMode.dark);
        await expectTheme(true);
        await state.open();
        expect(state.windows, hasLength(3));
        await expectTheme(true);
        await state.setThemeMode(ThemeMode.light);
        await expectTheme(false);
        // Reset from the opposite preference so a no-op System setter fails.
        await state.setThemeMode(
            systemDark == true ? ThemeMode.light : ThemeMode.dark);
        await expectTheme(systemDark != true);
        await state.setThemeMode(ThemeMode.system);
        await _until(() async {
          for (final window in state.windows) {
            if (await window.webview.evaluateJavaScript(script) != systemDark) {
              return false;
            }
          }
          return true;
        });
        expect(state.windows.map((window) => window.appearance),
            everyElement(ThemeMode.system));
      } finally {
        await state.setThemeMode(ThemeMode.system);
        for (final window in List.of(state.windows)) {
          await window.webview.close();
          await window.webview.onClose;
        }
        state.dispose();
        await pages.close();
      }
    });
    await tester.pumpAndSettle();
  });
}
