import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'file_reader_io.dart'
    if (dart.library.js_interop) 'file_reader_web.dart'
    as reader;

/// A dropped item.
///
/// On desktop, this is usually a filesystem path (file or directory).
/// File-backed contents are read through XFile; byte-backed constructors retain
/// their in-memory data for compatibility with the previous API.
///
/// macOS specifics:
/// - If the drag source provided a real file URL (e.g. Finder/JetBrains),
///   [extraAppleBookmark] will typically be non-null and allow security-scoped
///   access when running sandboxed.
/// - If the drag source used a file promise (e.g. VS Code/Electron), the
///   system delivers bytes into a per-drop temporary folder inside your app's
///   container. In that case [fromPromise] is true and [extraAppleBookmark]
///   is usually null/empty. There is no original source path in this flow.
abstract class DropItem {
  final String path;
  final String name;
  final String? mimeType;
  final int? _length;
  final DateTime? _lastModified;
  final Uint8List? _bytes;
  final XFile? _source;
  late final XFile _file = _source ?? reader.fromPath(path);

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
    this.path, {
    this.mimeType,
    String? name,
    int? length,
    Uint8List? bytes,
    DateTime? lastModified,
    this.extraAppleBookmark,
    this.fromPromise = false,
    XFile? file,
  }) : name = name ?? path.split(RegExp(r'[/\\]')).last,
       _source = file,
       // Keep the existing public parameter names for these private fields.
       // ignore: prefer_initializing_formals
       _length = length,
       // ignore: prefer_initializing_formals
       _bytes = bytes,
       // ignore: prefer_initializing_formals
       _lastModified = lastModified;

  DropItem.fromData(
    Uint8List bytes, {
    String? mimeType,
    String? name,
    int? length,
    DateTime? lastModified,
    String? path,
    Uint8List? extraAppleBookmark,
    bool fromPromise = false,
  }) : this(
         path ?? '',
         mimeType: mimeType,
         name: name,
         length: length,
         bytes: bytes,
         lastModified: lastModified,
         extraAppleBookmark: extraAppleBookmark,
         fromPromise: fromPromise,
       );

  Future<int> length() async =>
      _length ??
      _bytes?.length ??
      await _file.length() ??
      (throw StateError('Cannot determine dropped file length: $path'));

  Future<DateTime> lastModified() async =>
      _lastModified ??
      (_bytes == null ? await _file.lastModified() : null) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final from = start ?? 0;
    if (from < 0 || (end != null && end < from)) {
      throw RangeError('Invalid byte range: $from..$end');
    }
    // XFile 0.4 rejects equal bounds; retain the existing empty-range behavior.
    if (end == from) return;
    final bytes = _bytes;
    if (bytes == null) {
      yield* _file.openRead(from, end);
    } else {
      final until = (end ?? bytes.length).clamp(0, bytes.length);
      if (from < until) yield Uint8List.sublistView(bytes, from, until);
    }
  }

  Future<Uint8List> readAsBytes() async => _bytes ?? await _file.readAsBytes();

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      _bytes == null
      ? await _file.readAsString(encoding: encoding)
      : encoding.decode(_bytes);

  Future<void> saveTo(String destination) =>
      reader.saveTo(_bytes == null ? _file : null, destination, _bytes);
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
    super.file,
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
    super.file,
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
