import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// A dropped item.
///
/// On desktop, this is usually a filesystem path (file or directory).
///
/// macOS specifics:
/// - If the drag source provided a real file URL (e.g. Finder/JetBrains),
///   [extraAppleBookmark] will typically be non-null and allow security-scoped
///   access when running sandboxed.
/// - If the drag source used a file promise (e.g. VS Code/Electron), the
///   system delivers bytes into a per-drop temporary folder inside your app's
///   container. In that case [fromPromise] is true and [extraAppleBookmark]
///   is usually null/empty. There is no original source path in this flow.
abstract class DropItem extends XFile {
  /// Security-scoped bookmark bytes for the dropped item (macOS only).
  ///
  /// Use with [DesktopDrop.startAccessingSecurityScopedResource] to gain
  /// temporary access to files outside your sandbox. When empty or null,
  /// you typically don't need to call start/stop (e.g. promise files in
  /// your app's container).
  Uint8List? extraAppleBookmark;

  /// True when this item was delivered via a macOS file promise and was
  /// written into your app's temporary Drops directory.
  ///
  /// In this case, the original source path is not available by design.
  final bool fromPromise;
  DropItem(
    super.path, {
    super.mimeType,
    super.name,
    super.length,
    super.bytes,
    super.lastModified,
    this.extraAppleBookmark,
    this.fromPromise = false,
  });

  DropItem.fromData(
    super.bytes, {
    super.mimeType,
    super.name,
    super.length,
    super.lastModified,
    super.path,
    this.extraAppleBookmark,
    this.fromPromise = false,
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
    super.fromPromise,
  });

  DropItemFile.fromData(
    super.bytes, {
    super.mimeType,
    super.name,
    super.length,
    super.lastModified,
    super.path,
    super.fromPromise,
  }) : super.fromData();
}

/// A dropped directory.
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
    super.extraAppleBookmark,
    super.fromPromise,
  });

  DropItemDirectory.fromData(
    super.bytes,
    this.children, {
    super.mimeType,
    super.name,
    super.length,
    super.lastModified,
    super.path,
    super.extraAppleBookmark,
    super.fromPromise,
  }) : super.fromData();
}
