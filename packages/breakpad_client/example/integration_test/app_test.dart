import 'dart:async';
import 'dart:io';

import 'package:breakpad_client/breakpad_client.dart' as breakpad;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Run by a standalone Dart VM: the test app cannot crash itself, and a
// relaunched test app waits for flutter_tools before running any test code.
const _crashScript = r'''
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef Alloc = Pointer<Uint8> Function(IntPtr);

void main(List<String> args) {
  final alloc = (Platform.isWindows
          ? DynamicLibrary.open('ole32.dll')
          : DynamicLibrary.process())
      .lookupFunction<Alloc, Pointer<Uint8> Function(int)>(
          Platform.isWindows ? 'CoTaskMemAlloc' : 'malloc');
  final init = DynamicLibrary.open(args[0]).lookupFunction<
      Int32 Function(Pointer<Uint8>),
      int Function(Pointer<Uint8>)>('breakpad_client_init_exception_handler');
  final bytes = utf8.encode(args[1]);
  final dir = alloc(bytes.length + 1);
  dir.asTypedList(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 0;
  if (init(dir) != 0) exit(2);
  stdout.writeln('breakpad_client: crashing');
  Pointer<Uint8>.fromAddress(0).value = 1;
}
''';

void main() {
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
      final bundle = File(Platform.resolvedExecutable).parent.path;
      final library = Platform.isWindows
          ? '$bundle\\breakpad_client.dll'
          : '$bundle/lib/libbreakpad_client.so';
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      expect(flutterRoot, isNotNull, reason: 'FLUTTER_ROOT locates dart');
      final dart = '$flutterRoot/bin/cache/dart-sdk/bin/'
          '${Platform.isWindows ? 'dart.exe' : 'dart'}';
      final script = File('${temp.path}${Platform.pathSeparator}crash.dart')
        ..writeAsStringSync(_crashScript);
      final dumps = Directory('${temp.path}${Platform.pathSeparator}dumps')
        ..createSync();
      final process =
          await Process.start(dart, [script.path, library, dumps.path]);
      final output = StringBuffer();
      final streams = [
        process.stdout.transform(systemEncoding.decoder).forEach(output.write),
        process.stderr.transform(systemEncoding.decoder).forEach(output.write),
      ];
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          process.kill();
          throw TimeoutException('crashing child did not exit\n'
              'files: ${dumps.listSync().map((e) => e.path).toList()}\n'
              'output:\n$output');
        },
      );
      await Future.wait(streams);
      expect(exitCode, isNot(0), reason: '$output');
      final minidumps =
          dumps.listSync().where((entry) => entry.path.endsWith('.dmp'));
      expect(minidumps, hasLength(1), reason: '$output');
      expect((minidumps.single as File).lengthSync(), greaterThan(0));
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
