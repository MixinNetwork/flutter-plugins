import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
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

  test('linux drop includes rawText for multiple files with portal key',
      () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    // Multiple files delivered via text/uri-list (no portal key)
    await _invokePlatformMethod(const MethodCall('performOperation_linux', [
      'file:///home/user/Documents/file1.txt\nfile:///home/user/Pictures/photo.png',
      [150.0, 250.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files.length, 2);
    expect(event.files[0].path, '/home/user/Documents/file1.txt');
    expect(event.files[1].path, '/home/user/Pictures/photo.png');
    expect(event.rawText,
        'file:///home/user/Documents/file1.txt\nfile:///home/user/Pictures/photo.png');
  });

  test('linux drop rawText contains only file URIs (no portal key)', () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    // Normal drag from non-sandboxed app (no portal)
    await _invokePlatformMethod(const MethodCall('performOperation_linux', [
      'file:///home/user/Downloads/normal.txt\nfile:///home/user/Downloads/another.txt',
      [50.0, 60.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files.length, 2);
    expect(event.files[0].path, '/home/user/Downloads/normal.txt');
    expect(event.files[1].path, '/home/user/Downloads/another.txt');
    // rawText still captured (may be used by consumers)
    expect(event.rawText,
        'file:///home/user/Downloads/normal.txt\nfile:///home/user/Downloads/another.txt');
  });

  test('linux drop with non-file URI (SMB) still works and rawText captured',
      () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    await _invokePlatformMethod(const MethodCall('performOperation_linux', [
      'smb://server/share/document.pdf',
      [10.0, 20.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files.single.path, 'smb://server/share/document.pdf');
    expect(event.rawText, 'smb://server/share/document.pdf');
  });

  test('linux drop decodes percent-encoded filenames', () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    await _invokePlatformMethod(const MethodCall('performOperation_linux', [
      'file:///home/user/my%20file.txt',
      [5.0, 5.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files.single.path, '/home/user/my file.txt');
    expect(event.rawText, 'file:///home/user/my%20file.txt');
  });

  test('linux drop tolerates trailing blank line in payload', () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    await _invokePlatformMethod(const MethodCall('performOperation_linux', [
      'file:///home/user/a.txt\nfile:///home/user/b.txt\n',
      [1.0, 1.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files.length, 2);
    expect(event.files[0].path, '/home/user/a.txt');
    expect(event.files[1].path, '/home/user/b.txt');
    expect(event.rawText, 'file:///home/user/a.txt\nfile:///home/user/b.txt\n');
  });

  test('linux portal drop returns portal key in rawText with no files',
      () async {
    final events = <DropEvent>[];
    void listener(DropEvent event) => events.add(event);
    DesktopDrop.instance.addRawDropEventListener(listener);
    addTearDown(
        () => DesktopDrop.instance.removeRawDropEventListener(listener));

    // Portal key delivered via application/vnd.portal.filetransfer target
    await _invokePlatformMethod(const MethodCall('performOperation_portal', [
      'abc123portalkey456',
      [100.0, 200.0]
    ]));

    final event = events.single as DropDoneEvent;
    expect(event.files, isEmpty);
    expect(event.rawText, 'abc123portalkey456');
    expect(event.location.dx, 100.0);
    expect(event.location.dy, 200.0);
  });
}
