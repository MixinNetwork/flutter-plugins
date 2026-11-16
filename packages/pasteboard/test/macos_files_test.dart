import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('macOS files only returns local file URL paths', () async {
    // flutter test runs in flutter_tester beside the cached macOS framework.
    final frameworkDirectory = File(Platform.resolvedExecutable).parent.path;
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'pasteboard_macos_files_',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final executable = p.join(temporaryDirectory.path, 'files_test');
    final compilation = await Process.run('xcrun', [
      'swiftc',
      '-F',
      frameworkDirectory,
      '-framework',
      'FlutterMacOS',
      '-Xlinker',
      '-rpath',
      '-Xlinker',
      frameworkDirectory,
      'macos/pasteboard/Sources/pasteboard/PasteboardPlugin.swift',
      'test/macos/main.swift',
      '-o',
      executable,
    ]);
    expect(
      compilation.exitCode,
      0,
      reason: '${compilation.stdout}\n${compilation.stderr}',
    );
    final execution = await Process.run(executable, []);
    expect(
      execution.exitCode,
      0,
      reason: '${execution.stdout}\n${execution.stderr}',
    );
  }, skip: !Platform.isMacOS);
}
