import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void registerTitleBarThemeTests() {
  testWidgets('titlebar themes synchronize native windows and Flutter toolbars',
      (tester) async {
    const native = MethodChannel('webview_example/native_test');
    final theme = ValueNotifier<ThemeData?>(ThemeData.light());
    final windows = <Webview>[];
    await tester.pumpWidget(
        ValueListenableBuilder<ThemeData?>(
          valueListenable: theme,
          builder: (context, value, _) => WebviewWindowApp(
            titleBar: WebviewTitleBarConfiguration(
              theme: value,
              builder: (context, webview, state) => Text(
                'Toolbar ${Theme.of(context).brightness.name}',
              ),
            ),
            child: const MaterialApp(home: SizedBox.shrink()),
          ),
        ),
        wrapWithView: false);
    try {
      await tester.runAsync(() async {
        await titleBarInitialization;
        for (var i = 0; i < 3; i++) {
          windows.add(await WebviewWindow.create(
            titleBar: i == 2 ? const WebviewTitleBarConfiguration.none() : null,
            configuration: CreateConfiguration(
              title: 'Theme test $i',
            ),
          ));
        }
      });
      await tester.pumpAndSettle();
      Future<void> expectNative(List<bool> dark) async {
        await tester.runAsync(() async {
          for (var i = 0; i < windows.length; i++) {
            final result = await native.invokeMapMethod<String, dynamic>(
              'inspect',
              {'title': 'Theme test $i'},
            );
            expect(result!['nativeDark'], dark[i], reason: 'Window $i');
          }
        });
      }

      expect(find.text('Toolbar light'), findsNWidgets(2));
      await expectNative([false, false, false]);
      await tester
          .runAsync(() => windows.first.setTitleBarTheme(ThemeData.dark()));
      await tester.pumpAndSettle();
      expect(find.text('Toolbar dark'), findsOneWidget);
      expect(find.text('Toolbar light'), findsOneWidget);
      await expectNative([true, false, false]);
      theme.value = ThemeData.dark();
      await tester.pumpAndSettle();
      expect(find.text('Toolbar dark'), findsNWidgets(2));
      await expectNative([true, true, true]);
      theme.value = ThemeData.light();
      await tester.pumpAndSettle();
      await expectNative([true, false, false]);
      await tester.runAsync(() => windows.first.setTitleBarTheme(null));
      await tester.pumpAndSettle();
      expect(find.text('Toolbar light'), findsNWidgets(2));
      await expectNative([false, false, false]);
    } finally {
      await tester.runAsync(() async {
        for (final view in windows) {
          view.close();
        }
        // A round trip ensures Windows has processed every native close.
        await const MethodChannel('desktop_webview_window/titlebars')
            .invokeMethod('getViews');
      });
      await tester.pumpWidget(const SizedBox.shrink());
      theme.dispose();
    }
  });
}
