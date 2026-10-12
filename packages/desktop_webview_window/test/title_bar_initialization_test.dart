import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/title_bar_state.dart';
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
    titleBarInitialized = false;
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
    titleBarInitialized = false;
  });

  test('omitting the title-bar hook removes default height and padding',
      () async {
    await WebviewWindow.create();

    expect(createArguments.single['titleBarHeight'], 0);
    expect(createArguments.single['titleBarTopPadding'], 0);
  });

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
    });
    expect(configuration.titleBarHeight, 60);
    expect(configuration.titleBarTopPadding, 24);
  });

  for (final args in <List<String>>[
    [],
    ['application-argument']
  ]) {
    test('calling the hook with $args preserves title-bar configuration',
        () async {
      // Main-isolate startup does not render a title bar, but enables the hook
      // that will render one when the native platform starts a title-bar engine.
      expect(runWebViewTitleBarWidget(args), isFalse);

      await WebviewWindow.create();
      expect(createArguments.last, CreateConfiguration.platform().toMap());

      const configuration = CreateConfiguration(
        titleBarHeight: 60,
        titleBarTopPadding: 24,
      );
      await WebviewWindow.create(configuration: configuration);
      expect(createArguments.last, configuration.toMap());
    });
  }
}
