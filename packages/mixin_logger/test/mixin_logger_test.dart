import 'dart:io';
import 'dart:isolate';

import 'package:ansicolor/ansicolor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_logger/mixin_logger.dart';
import 'package:mixin_logger/src/log_file_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  final dir = p.join(Directory.systemTemp.path, 'mixin_logger_test');

  setUp(() {
    // delete the directory if it exists
    final temp = Directory(dir);
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  tearDown(() {
    // clean up logging file.
    final temp = Directory(dir);
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('test logger colors', () async {
    ansiColorDisabled = false;
    v('verbose message');
    d('debug message');
    i('info message');
    w('warning message');
    e('error message');
    wtf('wtf message');
  });

  test('test write log to empty files', () async {
    final dir = p.join(Directory.systemTemp.path, 'mixin_logger_test');
    final fileHandler = LogFileHandler(
      dir,
      maxFileCount: 2,
      maxFileLength: 20, // 20 Byte.
    );
    expect(FileSystemEntity.isDirectorySync(dir), isTrue);
    fileHandler.write('test');
    expect(FileSystemEntity.isFileSync(p.join(dir, 'log_0.log')), isTrue);
    final fileContent = File(p.join(dir, 'log_0.log')).readAsStringSync();
    expect(fileContent, equals('test\n'));
    fileHandler.write('test_longer_than_20_byte_123456789101120');
    expect(FileSystemEntity.isFileSync(p.join(dir, 'log_1.log')), isTrue);
    fileHandler.write('test_file2');
    expect(
      File(p.join(dir, 'log_1.log')).readAsStringSync(),
      equals('test_file2\n'),
    );
  });

  test('test write log to exist files', () {
    {
      File(p.join(dir, 'log_0.log'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'test_longer_than_20_byte_123456789101120',
          flush: true,
          mode: FileMode.append,
        );
    }
    LogFileHandler(
      dir,
      maxFileCount: 2,
      maxFileLength: 20, // 20 Byte.
    ).write('test');
    expect(
      File(p.join(dir, 'log_0.log')).readAsStringSync(),
      equals('test_longer_than_20_byte_123456789101120'),
    );
    expect(FileSystemEntity.isFileSync(p.join(dir, 'log_1.log')), isTrue);
    expect(
      File(p.join(dir, 'log_1.log')).readAsStringSync(),
      equals('test\n'),
    );
  });

  test('test write log to exist files with maxFileCount = 1', () {
    File(p.join(dir, 'log_0.log'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'test_longer_than_20_byte_123456789101120',
        flush: true,
        mode: FileMode.append,
      );
    LogFileHandler(
      dir,
      maxFileCount: 1,
      maxFileLength: 20, // 20 Byte.
    ).write('test');
    expect(
      File(p.join(dir, 'log_1.log')).readAsStringSync(),
      equals('test\n'),
    );
    // log_0.log should be deleted.
    expect(
      FileSystemEntity.typeSync(p.join(dir, 'log_0.log')),
      equals(FileSystemEntityType.notFound),
    );
  });

  test('test write by log manager', () async {
    await LogFileManager.init(dir, 10, 1024 * 1024 * 10);
    final manger = LogFileManager.instance!;
    await manger.write('test');
    await Future.delayed(const Duration(milliseconds: 2000));
    expect(FileSystemEntity.isFileSync(p.join(dir, 'log_0.log')), isTrue);
    final fileContent = File(p.join(dir, 'log_0.log')).readAsStringSync();
    expect(fileContent, equals('test\n'));
  });

  test('test write on other isolate', () async {
    await LogFileManager.init(dir, 10, 1024 * 1024 * 10);
    final manger = LogFileManager.instance!;
    await manger.write('main');
    await Isolate.spawn(_writeLog, 'other isolate');

    await Future.delayed(const Duration(milliseconds: 2000));
    expect(FileSystemEntity.isFileSync(p.join(dir, 'log_0.log')), isTrue);
    final fileContent = File(p.join(dir, 'log_0.log')).readAsStringSync();
    expect(fileContent, equals('main\nother isolate\n'));
  });
}

void _writeLog(String message) {
  LogFileManager.instance!.write(message);
  Isolate.exit();
}
