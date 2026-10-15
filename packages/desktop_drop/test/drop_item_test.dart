import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local dropped files read ranges and save without cross_file', () async {
    final directory = await Directory.systemTemp.createTemp('desktop_drop_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.txt');
    await source.writeAsString('hello 世界');
    final item = DropItemFile(source.path);
    expect(item.name, 'source.txt');
    expect(await item.readAsString(), 'hello 世界');
    expect(await item.length(), await source.length());
    expect(await item.openRead(1, 4).expand((chunk) => chunk).toList(), [
      101,
      108,
      108,
    ]);
    final destination = '${directory.path}/saved.txt';
    await item.saveTo(destination);
    expect(await File(destination).readAsString(), 'hello 世界');
  });

  test(
    'memory files support empty and bounded reads and invalid ranges',
    () async {
      final item = DropItemFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'memory',
      );
      expect(await item.length(), 3);
      expect(await item.openRead(1, 3).expand((chunk) => chunk).toList(), [
        2,
        3,
      ]);
      expect(await item.openRead(0, 0).toList(), isEmpty);
      expect(await item.openRead(1, 100).expand((chunk) => chunk).toList(), [
        2,
        3,
      ]);
      expect(await item.openRead(100).toList(), isEmpty);
      await expectLater(item.openRead(-1).toList(), throwsRangeError);
      await expectLater(item.openRead(2, 1).toList(), throwsRangeError);
      expect(await DropItemFile.fromData(Uint8List(0)).readAsBytes(), isEmpty);
    },
  );
}
