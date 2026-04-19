import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_drop/src/events.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _invokePlatformMethod(MethodCall call) async {
  final codec = const StandardMethodCodec();
  final completer = Completer<ByteData?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'desktop_drop',
    codec.encodeMethodCall(call),
    completer.complete,
  );
  await completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DesktopDrop.instance.init();
  });

  test('linux drop keeps non-file uri path', () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    await _invokePlatformMethod(const MethodCall('performOperation_linux', [
      'smb://server/share/file.txt',
      [1.0, 2.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files.single.path, 'smb://server/share/file.txt');
  });

  test('linux drop still converts file uri to local path', () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    await _invokePlatformMethod(const MethodCall('performOperation_linux', [
      'file:///tmp/file.txt',
      [3.0, 4.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files.single.path, '/tmp/file.txt');
  });
}
