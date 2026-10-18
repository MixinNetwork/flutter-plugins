import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:desktop_webview_window/src/js_bridge.dart';
import 'package:desktop_webview_window/src/browser_runtime.dart';
import 'package:desktop_webview_window/src/webview_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeTransport fake;
  final calls = <MethodCall>[];
  var nextId = 500;

  setUp(() {
    calls.clear();
    fake = installFakeTransport();
    fake.native = (call) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          return created(++nextId);
        case 'evaluateJavaScript':
          return jsonEncode({
            'a': [1, true, null]
          });
        default:
          return null;
      }
    };
  });

  tearDown(() async {
    for (final id in List.of(browsers.keys)) {
      await sendBrowserEvent('onWindowClose', {'id': id});
    }
  });

  Future<Webview> create() => WebviewWindow.create();

  test('create injects the JavaScript bridge and nested Windows options',
      () async {
    await WebviewWindow.create(
      configuration: const CreateConfiguration(
        openHidden: true,
        brightness: Brightness.dark,
        windows: WindowsWebviewOptions(
          userDataFolder: 'profile',
          denyCameraAndMicrophone: true,
        ),
      ),
    );
    final arguments = calls.single.arguments as Map;
    final token = (browsers.values.single).bridgeToken;
    expect(token, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(arguments['javaScriptBridge'], javaScriptBridgeSource(token));
    expect(arguments['openHidden'], isTrue);
    expect(arguments['brightness'], 0);
    expect(arguments['userDataFolderWindows'], 'profile');
    expect(arguments['denyCameraAndMicrophone'], isTrue);
    expect(arguments['titleBar'], 15);
    expect(arguments['composerArguments'], isNull);
  });

  test('composer arguments and title bar items reach native unchanged',
      () async {
    await WebviewWindow.create(
      configuration: const CreateConfiguration(
        titleBar: TitleBarOptions(showNavigation: false, showHost: false),
        composerArguments: '{"layout":"sidebar"}',
      ),
    );
    final arguments = calls.single.arguments as Map;
    expect(arguments['titleBar'], 2 | 4);
    expect(arguments['composerArguments'], '{"layout":"sidebar"}');
    expect(arguments['brightness'], -1);
  });

  test('page messages reach the named handler with decoded data and origin',
      () async {
    final webview = await create();
    final token = (webview as WebviewImpl).bridgeToken;
    final received = <Object?>[];
    webview.addJavaScriptHandler(
        'login', (data, origin) => received.add([data, origin]));
    Future<void> send(String message, [String? source]) =>
        sendBrowserEvent('onJavaScriptMessage', {
          'id': webview.id,
          'message': message,
          'source': source,
        });
    await send(
        token +
            jsonEncode({
              'name': 'login',
              'data': {'token': 'x'}
            }),
        'https://example.com/login?next=/');
    await send(token + jsonEncode({'name': 'other', 'data': 1}));
    await send('${token}not json');
    // Frames without the bridge cannot know the token.
    await send(jsonEncode({'name': 'login', 'data': 'forged'}),
        'https://example.com/');
    webview.removeJavaScriptHandler('login');
    await send(token + jsonEncode({'name': 'login', 'data': 2}));
    expect(received, [
      [
        {'token': 'x'},
        'https://example.com'
      ],
    ]);
  });

  test('message origins are serialized like the web platform', () {
    expect(javaScriptMessageOrigin('https://Example.com:443/a'),
        'https://example.com');
    expect(javaScriptMessageOrigin('http://127.0.0.1:8080/x'),
        'http://127.0.0.1:8080');
    expect(javaScriptMessageOrigin('file:///tmp/index.html'), 'file://');
    expect(javaScriptMessageOrigin('about:blank'), 'null');
    expect(javaScriptMessageOrigin('data:text/html,hi'), 'null');
    expect(javaScriptMessageOrigin(null), 'null');
  });

  test('each browser gets its own bridge token', () async {
    final first = await create() as WebviewImpl;
    final second = await create() as WebviewImpl;
    expect(first.bridgeToken, isNot(second.bridgeToken));
  });

  test('postMessage sends the JSON message and its WebKit dispatch script',
      () async {
    final webview = await create();
    await webview.postMessage('theme', {'dark': true});
    final arguments = calls.last.arguments as Map;
    expect(calls.last.method, 'postJavaScriptMessage');
    final message = arguments['message'] as String;
    expect(jsonDecode(message), {
      'name': 'theme',
      'data': {'dark': true}
    });
    expect(arguments['script'], contains(jsonEncode(message)));
  });

  test('evaluateJavaScript returns the decoded value', () async {
    final webview = await create();
    expect(await webview.evaluateJavaScript('x'), {
      'a': [1, true, null]
    });
  });

  test('native errors reach the caller instead of being swallowed', () async {
    final webview = await create();
    fake.native = (call) async =>
        throw PlatformException(code: 'invalid_argument', message: 'bad');
    await expectLater(webview.launch('::'), throwsA(isA<PlatformException>()));
  });

  test('closed browsers reject further operations', () async {
    final webview = await create();
    await sendBrowserEvent('onWindowClose', {'id': webview.id});
    expect(webview.nativeWindowHandle, 0);
    await expectLater(webview.reload(), throwsStateError);
    await webview.close();
  });

  test('nativeWindowHandle comes from the create reply', () async {
    final webview = await create();
    expect(webview.nativeWindowHandle, 0x1000 + webview.id);
  });

  test('a close requested while composing returns a closed browser', () async {
    fake.native = (call) async => created(77, closed: true);
    final webview = await create();
    await webview.onClose.timeout(const Duration(seconds: 1));
    expect(webview.nativeWindowHandle, 0);
    expect(browsers, isEmpty);
  });

  Future<Object?> request(int id, String url) =>
      sendBrowserEvent('onUrlRequest', {'id': id, 'url': url});

  test('navigation decisions reach the callback and can cancel', () async {
    final webview = await create();
    final requested = <String>[];
    await webview.setOnUrlRequestCallback((url) {
      requested.add(url);
      return !url.contains('blocked');
    });
    expect(calls.last.method, 'setUrlRequestEnabled');
    expect(calls.last.arguments, {'viewId': webview.id, 'enabled': true});
    expect(await request(webview.id, 'https://example.com'), isTrue);
    expect(await request(webview.id, 'https://blocked.example'), isFalse);
    expect(requested, ['https://example.com', 'https://blocked.example']);
    calls.clear();
    await webview.setOnUrlRequestCallback((url) => true);
    expect(calls, isEmpty);
    await webview.setOnUrlRequestCallback(null);
    expect(calls.single.arguments, {'viewId': webview.id, 'enabled': false});
    expect(await request(webview.id, 'https://blocked.example'), isTrue);
    expect(await request(9999, 'https://unknown.example'), isTrue);
  });

  test('synchronous native navigation requests use the same decision',
      () async {
    final webview = await create();
    await webview.setOnUrlRequestCallback((url) => !url.contains('blocked'));
    final decide = fake.onNavigationRequest!;
    expect(decide(webview.id, 'https://example.com'), isTrue);
    expect(decide(webview.id, 'https://blocked.example'), isFalse);
    expect(decide(9999, 'https://blocked.example'), isTrue);
  });

  test('a throwing navigation callback allows the navigation', () async {
    final webview = await create();
    await webview.setOnUrlRequestCallback((url) => throw StateError('bug'));
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      expect(await request(webview.id, 'https://example.com'), isTrue);
    } finally {
      FlutterError.onError = previous;
    }
    expect(errors.single.exception, isStateError);
  });

  test('prompt replies come from the handler on macOS', () async {
    final webview = await create();
    if (!Platform.isMacOS) {
      expect(
          () => webview.setPromptHandler((p, d) => d), throwsUnsupportedError);
      return;
    }
    webview.setPromptHandler((prompt, text) => '$prompt:$text');
    final reply = await sendBrowserEvent(
        'runJavaScriptTextInputPanelWithPrompt',
        {'id': webview.id, 'prompt': 'name', 'defaultText': 'x'});
    expect(reply, 'name:x');
  });

  test('setBrightness forwards the platform brightness', () async {
    if (!(Platform.isMacOS || Platform.isWindows)) return;
    final webview = await create();
    await webview.setBrightness(Brightness.dark);
    expect(calls.last.arguments, {'viewId': webview.id, 'brightness': 0});
    await webview.setBrightness(null);
    expect(calls.last.arguments, {'viewId': webview.id, 'brightness': -1});
  });
}
