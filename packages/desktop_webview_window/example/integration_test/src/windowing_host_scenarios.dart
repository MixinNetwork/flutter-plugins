// These experimental SDK types are restricted to integration coverage. The
// plugin's public API and implementation do not import Flutter's windowing API.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_test/flutter_test.dart';

void registerWindowingHostTests() {
  // Stable SDKs ship the native windowing implementation while gating the
  // public tooling flag by channel. Enable it only in this integration fixture.
  if (const bool.fromEnvironment('WEBVIEW_TEST_WINDOWING')) {
    if (WidgetsBinding.instance.platformDispatcher.engineId !=
        PlatformDispatcher.instance.engineId) {
      throw StateError(
          'Native SDK windowing tests require flutter drive with test_driver/integration_test.dart');
    }
    isWindowingEnabled = true;
    WidgetsBinding.instance.windowingOwner = createDefaultWindowingOwner();
  }
  testWidgets(
      'titlebar host composes with SDK windows and survives an application window closing',
      (tester) async {
    final applications = <RegularWindowController>[];
    final browsers = <Webview>[];
    final visible = ValueNotifier<List<RegularWindowController>>([]);
    final toolbarHandles = <Webview>{};
    final engine = PlatformDispatcher.instance.engineId;
    try {
      await tester.runAsync(() async {
        for (var i = 0; i < 2; i++) {
          applications.add(RegularWindowController(
            size: const Size(480, 320),
            title: 'Application window $i',
          ));
        }
      });
      visible.value = List.of(applications);
      await tester.pumpWidget(
          WebviewTitleBarHost(
            titleBar: WebviewTitleBarConfiguration(
                builder: (context, webview, state) {
              toolbarHandles.add(webview);
              return const Text('Browser toolbar');
            }),
            child: ValueListenableBuilder<List<RegularWindowController>>(
              valueListenable: visible,
              builder: (context, controllers, _) => ViewCollection(views: [
                for (final controller in controllers)
                  RegularWindow(
                    key: ValueKey(controller),
                    controller: controller,
                    child: MaterialApp(
                        home: Text(controller == applications.first
                            ? 'Application one'
                            : 'Application two')),
                  ),
              ]),
            ),
          ),
          wrapWithView: false);
      await tester.runAsync(() async {
        await titleBarInitialization;
        browsers.add(await WebviewWindow.create());
      });
      await tester.pumpAndSettle();
      expect(find.text('Application one'), findsOneWidget);
      expect(find.text('Application two'), findsOneWidget);
      expect(find.text('Browser toolbar'), findsOneWidget);
      expect(toolbarHandles, contains(browsers.first));
      if (Platform.isMacOS) {
        await tester.runAsync(() async {
          final state = await const MethodChannel('webview_window')
              .invokeMapMethod<String, dynamic>('debugTitleBarState');
          expect(state!['engine'], engine);
        });
      }
      visible.value = [applications.last];
      await tester.pumpAndSettle();
      await tester.runAsync(() async => applications.first.destroy());
      await tester.pumpAndSettle();
      expect(find.text('Application one'), findsNothing);
      expect(find.text('Application two'), findsOneWidget);
      expect(find.text('Browser toolbar'), findsOneWidget);
      await tester.runAsync(() async {
        browsers.first.close();
        await const MethodChannel('desktop_webview_window/titlebars')
            .invokeMethod('getViews');
      });
      await tester.pumpAndSettle();
      expect(find.text('Browser toolbar'), findsNothing);
      expect(find.text('Application two'), findsOneWidget);
      await tester
          .runAsync(() async => browsers.add(await WebviewWindow.create()));
      await tester.pumpAndSettle();
      expect(find.text('Browser toolbar'), findsOneWidget);
      expect(toolbarHandles, contains(browsers.last));
    } finally {
      await tester.runAsync(() async {
        for (final browser in browsers) {
          browser.close();
        }
        await const MethodChannel('desktop_webview_window/titlebars')
            .invokeMethod('getViews');
      });
      await tester.pumpWidget(const ViewCollection(views: []),
          wrapWithView: false);
      await tester.runAsync(() async {
        for (final application in applications) {
          application.destroy();
          application.dispose();
        }
      });
      visible.dispose();
    }
  }, skip: !isWindowingEnabled);
}
