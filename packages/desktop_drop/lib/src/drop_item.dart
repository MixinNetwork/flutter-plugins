import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

abstract class DropItem extends XFile {
  Uint8List? extraAppleBookmark;
  DropItem(
    super.path, {
    super.mimeType,
    super.name,
    super.length,
    super.bytes,
    super.lastModified,
    this.extraAppleBookmark,
  });

  DropItem.fromData(
    super.bytes, {
    super.mimeType,
    super.name,
    super.length,
    super.lastModified,
    super.path,
  }) : super.fromData();
}

class DropItemFile extends DropItem {
  DropItemFile(
    super.path, {
    super.mimeType,
    super.name,
    super.length,
    super.bytes,
    super.lastModified,
    super.extraAppleBookmark,
  });

  DropItemFile.fromData(
    super.bytes, {
    super.mimeType,
    super.name,
    super.length,
    super.lastModified,
    super.path,
  }) : super.fromData();
}

class DropItemDirectory extends DropItem {
  final List<DropItem> children;

  DropItemDirectory(
    super.path,
    this.children, {
    super.mimeType,
    super.name,
    super.length,
    super.bytes,
    super.lastModified,
  });

  DropItemDirectory.fromData(
    super.bytes,
    this.children, {
    super.mimeType,
    super.name,
    super.length,
    super.lastModified,
    super.path,
  }) : super.fromData();
}
