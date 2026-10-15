import 'dart:convert';
import 'dart:typed_data';

import 'file_reader_io.dart'
    if (dart.library.js_interop) 'file_reader_web.dart'
    as reader;

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
abstract class DropItem {
  final String path;
  final String name;
  final String? mimeType;
  final int? _length;
  final DateTime? _lastModified;
  final Uint8List? _bytes;

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
  }) : name = name ?? path.split(RegExp(r'[/\\]')).last,
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
      _length ?? _bytes?.length ?? await reader.length(path);

  Future<DateTime> lastModified() async =>
      _lastModified ??
      (_bytes != null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : await reader.lastModified(path));

  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final from = start ?? 0;
    if (from < 0 || (end != null && end < from)) {
      throw RangeError('Invalid byte range: $from..$end');
    }
    final bytes = _bytes;
    if (bytes == null) {
      yield* reader.openRead(path, from, end);
    } else {
      final until = (end ?? bytes.length).clamp(0, bytes.length);
      for (var offset = from; offset < until; offset += 1024 * 1024) {
        final next = (offset + 1024 * 1024).clamp(0, until);
        yield Uint8List.sublistView(bytes, offset, next);
      }
    }
  }

  Future<Uint8List> readAsBytes() async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in openRead()) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());

  Future<void> saveTo(String destination) =>
      reader.saveTo(path, destination, _bytes);
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
