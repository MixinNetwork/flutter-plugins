import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Implemented by the example runner's native test composer.
const _native = MethodChannel('webview_example/native_test');

Future<List<String>> _events(Webview view) async {
  final all = await _native.invokeListMethod<String>('composerEvents');
  return [
    for (final event in all!)
      if (event.startsWith('${view.id}:'))
        event.substring('${view.id}:'.length),
  ];
}

Future<Map<String, int>> _geometry(Webview view) async =>
    (await _native.invokeMapMethod<String, int>(
        'geometry', {'handle': view.nativeWindowHandle}))!;

Future<void> _until(FutureOr<bool> Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _loaded(Webview view, String title) => _until(
    () =>
        view.navigationState.value.title == title &&
        !view.navigationState.value.isLoading,
    'title $title');

/// Native composer ownership, layout and close semantics. Requires the example
/// runner's test composer.
void registerComposerTests() {
  late HttpServer server;
  final views = <Webview>[];

  setUp(() async {
    await _native.invokeMethod('clearComposerEvents');
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

  Future<Webview> create([String? arguments]) async {
    final view = await WebviewWindow.create(
      configuration: CreateConfiguration(
        windowWidth: 640,
        windowHeight: 480,
        composerArguments: arguments,
      ),
    ).timeout(const Duration(seconds: 30));
    views.add(view);
    return view;
  }

  testWidgets('default and application-owned windows keep their own layout',
      (tester) async {
    await runScenario(tester, () async {
      final standard = await create();
      final sidebar = await create('sidebar');
      await standard.launch(url('/standard'));
      await sidebar.launch(url('/sidebar'));
      await _loaded(standard, '/standard');
      await _loaded(sidebar, '/sidebar');

      Future<void> checkLayout() async {
        await _until(() async {
          final top = await _geometry(standard);
          final side = await _geometry(sidebar);
          return top['webX'] == 0 &&
              top['webY']! > 0 &&
              top['webWidth'] == top['contentWidth'] &&
              top['webY']! + top['webHeight']! == top['contentHeight'] &&
              side['webY'] == 0 &&
              side['webX']! > 0 &&
              side['webHeight'] == side['contentHeight'] &&
              side['webX']! + side['webWidth']! == side['contentWidth'];
        }, 'toolbar above the default page, sidebar left of the other');
      }

      await checkLayout();
      for (final view in [standard, sidebar]) {
        await _native.invokeMethod('resize', {
          'handle': view.nativeWindowHandle,
          'width': 900,
          'height': 600,
        });
      }
      await _until(() async {
        final top = await _geometry(standard);
        final side = await _geometry(sidebar);
        return top['contentWidth'] == 900 && side['contentWidth'] == 900;
      }, 'resized');
      await checkLayout();

      // The application composer saw the default window only at compose.
      expect(await _events(standard), ['compose']);
      expect(await _events(sidebar), contains('navigation'));

      // Default toolbar: back, forward, reload. Back returns to the first page.
      await standard.launch(url('/second'));
      await _loaded(standard, '/second');
      await _native.invokeMethod(
          'clickButton', {'handle': standard.nativeWindowHandle, 'index': 0});
      await _loaded(standard, '/standard');
      expect(standard.navigationState.value.canGoForward, isTrue);

      // The sidebar's buttons drive navigation through the same API.
      await sidebar.launch(url('/sidebar-next'));
      await _loaded(sidebar, '/sidebar-next');
      await _native.invokeMethod(
          'clickButton', {'handle': sidebar.nativeWindowHandle, 'index': 0});
      await _loaded(sidebar, '/sidebar');

      for (final view in [standard, sidebar]) {
        await view.close();
        await view.onClose.timeout(const Duration(seconds: 10));
        views.remove(view);
      }
      expect(await _events(standard), ['compose']);
      final events = await _events(sidebar);
      expect(events.first, 'compose');
      expect(events.last, 'closing');
      expect(events.where((event) => event == 'closing'), hasLength(1));
    });
  });

  testWidgets('a close requested while composing returns a closed browser',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create('close:compose');
      await view.onClose.timeout(const Duration(seconds: 1));
      views.remove(view);
      expect(view.nativeWindowHandle, 0);
      expect(await _events(view), ['compose', 'close-accepted', 'closing']);
    });
  });

  testWidgets('a close requested from navigation_changed runs afterwards',
      (tester) async {
    await runScenario(tester, () async {
      final view = await create('close:navigation');
      await view.launch(url('/page'));
      await view.onClose.timeout(const Duration(seconds: 20));
      views.remove(view);
      final events = await _events(view);
      expect(events.sublist(events.length - 2), ['close-accepted', 'closing']);
      expect(events.where((event) => event == 'closing'), hasLength(1));
      await expectLater(view.reload(), throwsStateError);
    });
  });

  testWidgets('a close requested from closing is ignored', (tester) async {
    await runScenario(tester, () async {
      final view = await create('close:closing');
      await view.close();
      await view.close();
      await view.onClose.timeout(const Duration(seconds: 10));
      views.remove(view);
      final events = await _events(view);
      expect(events.sublist(events.length - 2), ['closing', 'close-ignored']);
    });
  });

  testWidgets('browsers survive twenty close/recreate rounds', (tester) async {
    await runScenario(tester, () async {
      for (var round = 0; round < 20; round++) {
        final view = await create(round.isEven ? null : 'sidebar');
        await view.launch(url('/round$round'));
        await _loaded(view, '/round$round');
        await view.close();
        await view.onClose.timeout(const Duration(seconds: 10));
        views.remove(view);
      }
    });
  });
}
