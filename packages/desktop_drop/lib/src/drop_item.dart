import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

abstract class DropItem extends XFile {
  DropItem(
    String path, {
    String? mimeType,
    String? name,
    int? length,
    Uint8List? bytes,
    DateTime? lastModified,
  }) : super(path,
            mimeType: mimeType,
            name: name,
            length: length,
            bytes: bytes,
            lastModified: lastModified);

  DropItem.fromData(
    Uint8List bytes, {
    String? mimeType,
    String? name,
    int? length,
    DateTime? lastModified,
    String? path,
  }) : super.fromData(
          bytes,
          mimeType: mimeType,
          name: name,
          length: length,
          lastModified: lastModified,
          path: path,
        );
}

class DropItemFile extends DropItem {
  DropItemFile(
    String path, {
    String? mimeType,
    String? name,
    int? length,
    Uint8List? bytes,
    DateTime? lastModified,
  }) : super(
          path,
          mimeType: mimeType,
          name: name,
          length: length,
          bytes: bytes,
          lastModified: lastModified,
        );

  DropItemFile.fromData(
    Uint8List bytes, {
    String? mimeType,
    String? name,
    int? length,
    DateTime? lastModified,
    String? path,
  }) : super.fromData(
          bytes,
          mimeType: mimeType,
          name: name,
          length: length,
          lastModified: lastModified,
          path: path,
        );
}

class DropItemDirectory extends DropItem {
  final List<DropItem> children;

  DropItemDirectory(
    String path,
    this.children, {
    String? mimeType,
    String? name,
    int? length,
    Uint8List? bytes,
    DateTime? lastModified,
  }) : super(
          path,
          mimeType: mimeType,
          name: name,
          length: length,
          bytes: bytes,
          lastModified: lastModified,
        );

  DropItemDirectory.fromData(
    Uint8List bytes,
    this.children, {
    String? mimeType,
    String? name,
    int? length,
    DateTime? lastModified,
    String? path,
  }) : super.fromData(
          bytes,
          mimeType: mimeType,
          name: name,
          length: length,
          lastModified: lastModified,
          path: path,
        );
}
