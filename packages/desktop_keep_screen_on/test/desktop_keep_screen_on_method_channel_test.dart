import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_keep_screen_on/src/desktop_keep_screen_on_method_channel.dart';

void main() {
  MethodChannelDesktopKeepScreenOn platform = MethodChannelDesktopKeepScreenOn();
  const MethodChannel channel = MethodChannel('desktop_keep_screen_on');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
