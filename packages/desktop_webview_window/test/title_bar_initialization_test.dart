import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('webview_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final createArguments = <Map<dynamic, dynamic>>[];
  var nextViewId = 0;
  final createdViewIds = <int>[];

  setUp(() {
    titleBarInitialization = null;
    createArguments.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') {
        createArguments.add(call.arguments as Map);
        final viewId = nextViewId++;
        createdViewIds.add(viewId);
        return viewId;
      }
      throw MissingPluginException();
    });
  });

  tearDown(() async {
    for (final viewId in createdViewIds) {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onWindowClose', {'id': viewId}),
        ),
        (_) {},
      );
    }
    createdViewIds.clear();
    messenger.setMockMethodCallHandler(channel, null);
    titleBarInitialization = null;
  });

  test(
    'omitting the title-bar hook removes default height and padding',
    () async {
      await WebviewWindow.create();

      expect(createArguments.single['titleBarHeight'], 0);
      expect(createArguments.single['titleBarTopPadding'], 0);
    },
  );

  test('omitting the hook removes custom title-bar space only', () async {
    const configuration = CreateConfiguration(
      windowWidth: 900,
      windowHeight: 600,
      title: 'Full-window content',
      titleBarHeight: 60,
      titleBarTopPadding: 24,
    );
    await WebviewWindow.create(configuration: configuration);

    expect(createArguments.single, {
      ...configuration.toMap(),
      'titleBarHeight': 0,
      'titleBarTopPadding': 0,
      'useTitleBar': false,
    });
    expect(configuration.titleBarHeight, 60);
    expect(configuration.titleBarTopPadding, 24);
  });

  test('system title bar defaults to visible and can be disabled', () async {
    await WebviewWindow.create();
    expect(createArguments.last['showSystemTitleBar'], isTrue);
    await WebviewWindow.create(
      configuration: const CreateConfiguration(showSystemTitleBar: false),
    );
    expect(createArguments.last['showSystemTitleBar'], isFalse);
  });

  testWidgets('mounting the root initializes the main engine before create',
      (tester) async {
    const control = MethodChannel('desktop_webview_window/titlebars');
    final calls = <String>[];
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call.method);
      if (call.method == 'initialize') {
        expect((call.arguments as Map)['mainViewId'], tester.view.viewId);
        return tester.view.viewId;
      }
      return call.method == 'getViews' ? [] : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(control, null));
    await tester.pumpWidget(
      const WebviewWindowApp(child: SizedBox.shrink()),
      wrapWithView: false,
    );
    await WebviewWindow.create();
    expect(calls.first, 'initialize');
    expect(createArguments.last['useTitleBar'], isTrue);
    expect(createArguments.last['titleBarHeight'], 40);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(titleBarInitialization, isNull);
  });
}
