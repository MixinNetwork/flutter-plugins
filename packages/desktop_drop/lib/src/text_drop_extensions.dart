import 'dart:convert';

import 'drop_item.dart';

/// Helpers for handling memory-backed text/link drops on macOS.
///
/// Dock text/links are delivered as in-memory [DropItem]s with a pseudo-path
/// like `memory://...` and a text-like MIME type (e.g., `text/plain`,
/// `text/html`, `application/rtf`, or `text/uri-list`).
extension DropItemTextExtensions on DropItem {
  /// True when this item is memory-backed (not a real filesystem path).
  bool get isMemoryBacked => path.startsWith('memory://');

  /// True when this item carries a text-like payload.
  bool get isTextLike {
    final m = mimeType ?? '';
    return m.startsWith('text/') ||
        m == 'text/uri-list' ||
        m == 'application/rtf';
  }

  /// Reads the item as a UTF-8 string if it appears to be text-like.
  ///
  /// For `text/uri-list`, the returned string may contain multiple URIs
  /// separated by newlines. For `application/rtf`, this returns the raw
  /// RTF content as text (no conversion to plain text is attempted).
  Future<String?> readAsText({bool allowMalformed = true}) async {
    if (!isMemoryBacked || !isTextLike) return null;
    final bytes = await readAsBytes();
    return Utf8Decoder(allowMalformed: allowMalformed).convert(bytes);
  }

  /// Parses a `text/uri-list` payload into URIs. Returns an empty list for
  /// non-URI items.
  Future<List<Uri>> readAsUris() async {
    if (mimeType != 'text/uri-list') return const [];
    final s = await readAsText() ?? '';
    return s
        .split('\n')
        .map((line) => line.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .map(Uri.parse)
        .toList();
  }
}
