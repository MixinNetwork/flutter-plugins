import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';

void main() {
  const MethodChannel channel = MethodChannel('ogg_opus_player');

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

  });
}
