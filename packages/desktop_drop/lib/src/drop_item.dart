import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import 'file_mime_type.dart';

/// One representation supplied by the drag source. Multiple representations
/// can describe the same content; applications choose which ones to consume.
@immutable
sealed class DropItem {
  const DropItem();
  String? get mimeType;
}

/// A file reference backed by a local file, browser Blob, or native provider.
/// Some systems start native transfers at drop time. Consume provider-backed
/// content during onDrop; the source may already have expired afterward.
/// A file need not have a filesystem path. Reads are provided by [file].
final class DropFileItem extends DropItem {
  const DropFileItem({
    required this.file,
    required this.name,
    String? mimeType,
    this.localPath,
    this.appleBookmark,
    this.isPromised = false,
  }) : // Preserve the public constructor parameter name.
       // ignore: prefer_initializing_formals
       _mimeType = mimeType;

  factory DropFileItem.fromPath(
    String path, {
    String? name,
    String? mimeType,
    Uint8List? appleBookmark,
    bool isPromised = false,
  }) => DropFileItem(
    file: XFile.fileSystem(path: path),
    name: name ?? path.split(RegExp(r'[/\\]')).last,
    mimeType: mimeType,
    localPath: path,
    appleBookmark: appleBookmark,
    isPromised: isPromised,
  );

  final XFile file;
  final String name;
  final String? _mimeType;

  /// The source's MIME type, or a filename-based guess when it is missing.
  /// This does not read or validate the file's contents.
  @override
  String? get mimeType => fileMimeType(_mimeType, name, localPath);

  /// Present only when this item has an actual local filesystem path.
  final String? localPath;

  /// macOS security-scoped bookmark. Balance successful access with a stop.
  final Uint8List? appleBookmark;
  final bool isPromised;
}

/// A string representation, including text/plain, text/html, text/uri-list,
/// and custom string MIME types. Referenced resources are never downloaded.
final class DropStringItem extends DropItem {
  const DropStringItem({required this.mimeType, required this.value});
  @override
  final String mimeType;
  final String value;
}

/// A directory whose immediate children can be read on demand.
final class DropDirectoryItem extends DropItem {
  const DropDirectoryItem({
    required this.directory,
    required this.name,
    this.localPath,
    this.appleBookmark,
    this.isPromised = false,
  });

  /// Lists immediate children as XFile or XDirectory without reading file
  /// contents. Native sandbox directories can require access through
  /// [appleBookmark] while listing and reading their children.
  final XDirectory directory;
  final String name;
  final String? localPath;
  final Uint8List? appleBookmark;
  final bool isPromised;
  @override
  String? get mimeType => null;
}
