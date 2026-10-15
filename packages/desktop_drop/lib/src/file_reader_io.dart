import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

XFile fromPath(String path) => XFile.fileSystem(path: path);

// XFile 0.4 no longer provides saveTo; preserve the DropItem convenience API.
Future<void> saveTo(XFile? source, String destination, Uint8List? bytes) async {
  final target = File(destination);
  if (bytes != null) {
    await target.writeAsBytes(bytes);
  } else if (source is FileSystemXFile) {
    await File(source.path).copy(destination);
  } else {
    final sink = target.openWrite();
    try {
      await sink.addStream(source!.openRead());
    } finally {
      await sink.close();
    }
  }
}
