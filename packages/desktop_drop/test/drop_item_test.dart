import 'dart:io';

import 'package:cross_file_io/cross_file_io.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(CrossFileIO.registerWith);

  test('local dropped file items expose XFile reads and a real path', () async {
    final directory = await Directory.systemTemp.createTemp('desktop_drop_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.txt');
    await source.writeAsString('hello 世界');
    final item = DropFileItem.fromPath(source.path);
    expect(item.name, 'source.txt');
    expect(await item.file.readAsString(), 'hello 世界');
    expect(await item.file.length(), await source.length());
    expect(await item.file.openRead(1, 4).expand((chunk) => chunk).toList(), [
      101,
      108,
      108,
    ]);
  });
}
