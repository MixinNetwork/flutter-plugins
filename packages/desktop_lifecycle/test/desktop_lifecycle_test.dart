import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_lifecycle/desktop_lifecycle.dart';

void main() {
  const MethodChannel channel = MethodChannel('desktop_lifecycle');

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
    expect(DesktopLifecycle.instance.isActive.value, true);
  });
}
