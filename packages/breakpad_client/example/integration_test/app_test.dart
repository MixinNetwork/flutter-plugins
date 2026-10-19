import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:breakpad_client/breakpad_client.dart' as breakpad;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// When set, this entry point crashes instead of running the suite, so a test
// can relaunch the built app as a child process and inspect its minidump.
const _crashDirVariable = 'BREAKPAD_CLIENT_CRASH_DIR';

void main() {
  final crashDir = Platform.environment[_crashDirVariable];
  if (crashDir != null) {
    breakpad.initExceptionHandle(crashDir);
    Pointer<Char>.fromAddress(0).value = 1;
    return;
  }

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('breakpad_client'));
  tearDown(() => temp.deleteSync(recursive: true));

  testWidgets('creates a non-ASCII dump directory and logs it', (tester) async {
    await tester.runAsync(() async {
      final dir = '${temp.path}${Platform.pathSeparator}崩溃 dumps'
          '${Platform.pathSeparator}nested';
      final logs = <String>[];
      breakpad.setLogger(logs.add);
      breakpad.initExceptionHandle(dir);
      await _until(() => logs.contains(dir));
      expect(Directory(dir).existsSync(), isTrue);
    });
  });

  testWidgets('setLogger replaces the previous logger', (tester) async {
    await tester.runAsync(() async {
      final first = <String>[];
      final second = <String>[];
      breakpad.setLogger(first.add);
      breakpad.setLogger(second.add);
      breakpad.initExceptionHandle(temp.path);
      await _until(() => second.contains(temp.path));
      expect(first, isEmpty);
    });
  });

  testWidgets('writes a minidump when the process crashes', (tester) async {
    await tester.runAsync(() async {
      final process = await Process.start(
        Platform.resolvedExecutable,
        [],
        environment: {_crashDirVariable: temp.path},
      );
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          process.kill();
          throw TimeoutException('crashing child did not exit');
        },
      );
      expect(exitCode, isNot(0));
      final dumps =
          temp.listSync().where((entry) => entry.path.endsWith('.dmp'));
      expect(dumps, hasLength(1));
      expect((dumps.single as File).lengthSync(), greaterThan(0));
    });
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
